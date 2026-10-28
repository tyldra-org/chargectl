import Foundation
import IOKit.pwr_mgt
import os

/// Owns the control loop: reads the battery, asks ChargePolicy what to do, and applies it.
final class ChargeController {
    private static let tickInterval: TimeInterval = 5
    private static let sampleInterval: TimeInterval = 60
    private static let historyWindow: TimeInterval = 24 * 60 * 60
    private static let logLimit = 300

    private let store: Store
    private let smc: SMC?
    private let reader: BatteryReader
    private let adapter: AdapterSwitch?
    /// Loaded in the background by start(): PowerUI and PowerUIAgent can take a minute to answer
    /// right after the Mac starts, and the app must reach the helper meanwhile.
    private var macOSLimit: MacOSChargeLimit?
    /// False until macOSLimit is loaded; no decisions are made before that.
    private var isReady = false
    /// The user's own macOS charge limit, restored when Chargectl stops controlling it.
    private var savedMacOSLimit: MacOSChargeLimit.Setting?
    /// The macOS limit Chargectl last set. A different value means someone changed it in System
    /// Settings, and Chargectl adopts it as its own limit.
    private var appliedMacOSLimit: MacOSChargeLimit.Setting?
    /// Lowered once PowerUIAgent refuses a limit below 80%; wall power is switched instead.
    private var macOSLimitFloor = ChargeSettings.limitRange.lowerBound
    private let logger = Logger(subsystem: "com.tyldra.chargectl", category: "daemon")

    private var settings: ChargeSettings
    private var state: ControlState
    private var activity = ChargeActivity.starting
    private var history: [HistorySample]
    private var logs: [LogEntry]
    private var lastBattery: BatterySnapshot?
    private var lastError: String?
    private var appliedLED: MagSafeLEDMode?
    private var timer: Timer?
    private var sleepWatcher: SleepWatcher?
    private var observer = PowerObserver()
    /// The service's own executable inside Chargectl.app and its date when this process started.
    /// Installing a new app replaces it; the service then restarts into the new version.
    /// Absolute: launchd starts an SMAppService daemon with a path relative to the app bundle in
    /// argv[0], which does not resolve from the service's working directory.
    private let executablePath = ChargeController.ownExecutablePath()
    private let launchedExecutableDate: Date?
    private var pendingExecutableChange: ExecutableChange?
    private var pendingExecutableChangeSince: Date?
    private static let removalGrace: TimeInterval = 30
    /// When the app was last seen running; an update within reopenWindow of it reopens the app.
    private var appLastSeen: Date?
    private static let reopenWindow: TimeInterval = 120
    /// No settings were saved yet; the first limit is taken from macOS's own setting.
    private var isFirstRun: Bool
    /// Set once the app uninstalls Chargectl: nothing is written to disk after that.
    private var isRemoved = false

    init(store: Store) {
        self.store = store
        let smc = try? SMC()
        self.smc = smc
        reader = BatteryReader(smc: smc)
        adapter = smc.flatMap(AdapterSwitch.init(smc:))
        let stored = store.load(ChargeSettings.self, from: .settings)
        settings = stored ?? ChargeSettings()
        isFirstRun = stored == nil
        state = store.load(ControlState.self, from: .state) ?? ControlState()
        // A starting helper cannot know whether the charger was connected meanwhile; above the
        // limit with automatic discharge off, it holds the charge as if just plugged in.
        state.wasPluggedIn = false
        history = store.load([HistorySample].self, from: .history) ?? []
        logs = store.load([LogEntry].self, from: .logs) ?? []
        savedMacOSLimit = store.load(MacOSChargeLimit.Setting.self, from: .macOSLimit)
        launchedExecutableDate = Self.modificationDate(executablePath)
    }

    func start() {
        log("chargectld \(DaemonIdentity.version) started")
        if getuid() != 0 { log("not running as root; wall power cannot be switched", level: .warning) }
        if smc == nil {
            log("AppleSMC is unavailable; charge control is off", level: .warning)
        } else if let adapter {
            log("switching wall power with SMC key \(adapter.key)")
        } else {
            log("no wall-power key on this Mac; charge control is off", level: .warning)
        }
        sleepWatcher = SleepWatcher(
            willSleep: { [weak self] in self?.prepareForSleep() },
            didWake: { [weak self] in self?.tick() })
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.global(qos: .userInitiated).async {
            let limit = MacOSChargeLimit()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishStarting(macOSLimit: limit) }
            }
        }
    }

    private func finishStarting(macOSLimit limit: MacOSChargeLimit?) {
        macOSLimit = limit
        if limit == nil {
            log("macOS charge limit is not available; holding the limit by switching wall power", level: .warning)
        } else {
            log(
                "PowerUIAgent preferences: \(MacOSChargeLimit.preferencesSummary(keys: ["mclLimitValue", "MCLFeatureState"]))"
            )
        }
        adoptMacOSLimitOnFirstRun()
        isReady = true
        tick()
    }

    func tick(now: Date = .now) {
        guard isReady, !isRemoved else { return }
        if followAppUpdates() { return }
        let battery: BatterySnapshot
        do {
            battery = try reader.read(now: now)
        } catch {
            report("battery read failed: \(error)")
            return
        }
        lastBattery = battery
        observe(battery)
        adoptMacOSLimitChangedInSettings()
        let input = PolicyInput(
            percent: battery.percent, isPluggedIn: battery.isPluggedIn, temperature: battery.temperature,
            canSetMacOSLimit: macOSLimit != nil, isCharging: battery.current > ObservedPower.flowThreshold,
            macOSLimitFloor: macOSLimitFloor)
        let decision = ChargePolicy.decide(input, settings: effectiveSettings, state: state, now: now)
        if let event = decision.event { log(event, source: .chargectl) }
        if decision.activity != activity {
            activity = decision.activity
            log(activity.summary, source: .chargectl)
        }
        if effectiveSettings.isEnabled {
            if let target = decision.macOSLimit { applyMacOSLimit(target) }
        } else {
            restoreMacOSLimit()
        }
        connectWallPower(decision.state.adapterEnabled)
        if decision.state != state {
            state = decision.state
            save(state, to: .state)
        }
        applyLED()
        record(battery, now: now)
    }

    /// Restarts into a new app version, and removes itself when Chargectl.app is gone, so a
    /// deleted app never leaves a root service behind. A change must be seen on two ticks in a
    /// row, because installing replaces the app in steps. Returns true when the process is ending.
    private func followAppUpdates() -> Bool {
        let date = Self.modificationDate(executablePath)
        guard date != launchedExecutableDate else {
            pendingExecutableChange = nil
            if !AppProcesses.running().isEmpty { appLastSeen = .now }
            return false
        }
        let change: ExecutableChange = date.map { .replaced($0) } ?? .removed
        guard pendingExecutableChange == change, let since = pendingExecutableChangeSince else {
            pendingExecutableChange = change
            pendingExecutableChangeSince = .now
            return false
        }
        // An installer moves the old app away before the new one arrives; only an app that stays
        // gone counts as deleted.
        if change == .removed, Date.now.timeIntervalSince(since) < Self.removalGrace { return false }
        switch change {
        case .removed:
            // Deleting the app is an uninstall: hand charging back to macOS and remove the helper's
            // plist, data and caches. A helper registered through SMAppService has no plist of its
            // own; without the app, launchd would keep trying to start a missing program.
            _ = removeEverything()
            bootOutSoon()
            return true
        case .replaced:
            log("Chargectl was updated; restarting the helper", source: .chargectl)
            reopenUpdatedApp()
            shutdown()
            // launchd starts the new executable again (KeepAlive).
            exit(0)
        }
    }

    private enum ExecutableChange: Equatable {
        case replaced(Date)
        case removed
    }

    /// Stops every copy of the app still running old code, and opens the new version for the
    /// signed-in user when the app was running shortly before the update: an installer such as
    /// Homebrew stops the app before it replaces it.
    private func reopenUpdatedApp() {
        let running = AppProcesses.running()
        let wasRunning =
            !running.isEmpty || appLastSeen.map { Date.now.timeIntervalSince($0) < Self.reopenWindow } == true
        for pid in running { kill(pid, SIGTERM) }
        guard wasRunning else { return }
        let app = URL(fileURLWithPath: executablePath).deletingLastPathComponent()  // MacOS
            .deletingLastPathComponent().deletingLastPathComponent().path  // Contents, Chargectl.app
        if AppProcesses.openForConsoleUser(app) {
            log("reopened Chargectl after the update", source: .chargectl)
        }
    }

    /// Crash reports macOS wrote for the helper, which only root can delete.
    private static func removeCrashReports() {
        let files = FileManager.default
        for folder in ["/Library/Logs/DiagnosticReports", "/Library/Logs/DiagnosticReports/Retired"] {
            for name in (try? files.contentsOfDirectory(atPath: folder)) ?? []
            where name.hasPrefix("Chargectl") || name.hasPrefix("chargectld") {
                try? files.removeItem(atPath: "\(folder)/\(name)")
            }
        }
    }

    private static func ownExecutablePath() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return CommandLine.arguments[0] }
        return String(cString: buffer)
    }

    private static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// On a fresh install, start from the limit set in System Settings › Battery, so nothing
    /// changes until the user picks another one. macOS's limit off means charging to 100%.
    private func adoptMacOSLimitOnFirstRun() {
        guard isFirstRun else { return }
        isFirstRun = false
        guard let current = try? macOSLimit?.current() else { return }
        settings.limit = current.isEnabled ? current.limit : 100
        settings = settings.normalized()
        save(settings, to: .settings)
        log(
            current.isEnabled
                ? "starting with the macOS charge limit, \(settings.limit)%"
                : "macOS charge limit is off; starting at 100%", source: .chargectl)
    }

    /// Keeps Chargectl and System Settings › Battery in step: a limit chosen there becomes
    /// Chargectl's limit.
    private func adoptMacOSLimitChangedInSettings() {
        // A limit macOS switched off itself (its occasional charge to 100%, "Charge to Full
        // Now") is not a new choice; Chargectl turns it back on.
        // During Top Up, Discharge and Calibrate, Chargectl sets macOS's limit for the job; a change
        // then is its own doing, not the user's.
        guard settings.isEnabled, state.mode == .automatic, let applied = appliedMacOSLimit,
            let current = try? macOSLimit?.current(), current.isEnabled, current != applied
        else { return }
        appliedMacOSLimit = current
        let limit = current.limit
        guard limit != settings.limit else { return }
        let previous = settings.limit
        settings.limit = limit
        settings = settings.normalized()
        save(settings, to: .settings)
        state.holdLevel = nil
        state.isSailing = false
        log("limit changed in System Settings: \(previous)% → \(settings.limit)%", source: .chargectl)
    }

    // MARK: Client requests

    func status() -> DaemonStatus {
        DaemonStatus(
            version: DaemonIdentity.version, settings: settings, mode: state.mode, activity: activity,
            adapterEnabled: state.adapterEnabled, adapterKey: adapter?.key, lastError: lastError,
            optimizedChargingEnabled: macOSLimit?.isOptimizedChargingEnabled())
    }

    func historySamples() -> [HistorySample] { history }

    func logEntries() -> [LogEntry] { logs }

    func update(_ newSettings: ChargeSettings) {
        let newSettings = newSettings.normalized()
        guard newSettings != settings else { return }
        let changes = newSettings.changes(from: settings)
        settings = newSettings
        save(settings, to: .settings)
        log("settings: " + changes.joined(separator: ", "), source: .chargectl)
        tick()
    }

    /// Returns a message for the user when the command cannot run.
    func perform(_ command: DaemonCommand) -> String? {
        switch command {
        case .uninstall: return removeEverything()
        case .removeService: return removeService()
        default: break
        }
        guard adapter != nil else { return "This Mac has no wall-power key, so charging cannot be controlled." }
        let percent = lastBattery?.percent ?? 0
        switch command {
        case .topUp:
            state.mode = .topUp
            log("top up to 100% started", source: .chargectl)
        case .discharge:
            guard percent > settings.limit else { return "The battery is already at or below \(settings.limit)%." }
            state.mode = .discharge(to: settings.limit)
            log("discharge to \(settings.limit)% started", source: .chargectl)
        case .calibrate:
            state.mode = .calibrate(.draining, since: .now)
            log("calibration started: draining to \(ChargePolicy.calibrationFloor)%", source: .chargectl)
        case .stop:
            guard state.mode != .automatic else { return nil }
            log("\(state.mode.title) stopped", source: .chargectl)
            state.mode = .automatic
        case .reset:
            settings = ChargeSettings()
            state.mode = .automatic
            save(settings, to: .settings)
            log("settings reset: \(settings.summary)", source: .chargectl)
        case .uninstall, .removeService:
            break
        }
        save(state, to: .state)
        tick()
        return nil
    }

    /// Runs on SIGTERM: shutdown, restart and updates. Reconnects wall power but keeps macOS's
    /// charge limit, so the limit holds until the helper runs again. Turning charge control off,
    /// removing the helper and uninstalling restore the user's own macOS limit.
    func shutdown() {
        timer?.invalidate()
        if let adapter, (try? adapter.isConnected()) == false { try? adapter.set(connected: true) }
        if appliedLED == .off { try? smc?.write(SMCKey.magSafeLED, bytes: [0]) }
        if !isRemoved { log("stopped; wall power reconnected", source: .chargectl) }
    }

    /// Hands charging back to macOS and deletes every file the daemon wrote. The app then
    /// unregisters the daemon, so launchd stops it.
    private func removeEverything() -> String? {
        restoreSystemDefaults()
        isRemoved = true
        unloadIfInstalledByScript()
        DarwinDirectories.removeEntries(withPrefix: "com.tyldra.chargectl")
        Self.removeCrashReports()
        do {
            try store.removeAll()
            return nil
        } catch {
            return
                "Charging is back to normal, but \(store.directory.path) could not be deleted: \(error.localizedDescription)"
        }
    }

    /// Stops enforcing and removes the service but keeps settings, history and logs.
    private func removeService() -> String? {
        restoreSystemDefaults()
        log("control service removed; wall power restored", source: .chargectl)
        unloadIfInstalledByScript()
        return nil
    }

    /// scripts/install.sh registers the daemon with a plist in /Library/LaunchDaemons instead of
    /// SMAppService. Only root can undo that, so the daemon deletes the plist and unloads itself.
    /// SMAppService registrations are left to the app, which unregisters them.
    private func unloadIfInstalledByScript() {
        let plist = "/Library/LaunchDaemons/\(DaemonIdentity.machService).plist"
        guard FileManager.default.fileExists(atPath: plist) else { return }
        do {
            try FileManager.default.removeItem(atPath: plist)
        } catch {
            report("could not delete \(plist): \(error.localizedDescription)")
            return
        }
        bootOutSoon()
    }

    /// Asks launchd to stop and unload this job. Delayed so an XPC reply reaches the app first.
    private func bootOutSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let launchctl = Process()
            launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            launchctl.arguments = ["bootout", "system/\(DaemonIdentity.machService)"]
            try? launchctl.run()
        }
    }

    private func restoreSystemDefaults() {
        timer?.invalidate()
        restoreMacOSLimit()
        if let adapter, (try? adapter.isConnected()) == false { try? adapter.set(connected: true) }
        if appliedLED == .off { try? smc?.write(SMCKey.magSafeLED, bytes: [0]) }
    }

    /// `Chargectl Service --restore`, run as root by Uninstall when the helper is not running:
    /// reconnects wall power, gives the MagSafe LED back to macOS and restores the user's macOS
    /// charge limit, without starting the control loop.
    func restoreForUninstall() {
        appliedLED = .off
        restoreSystemDefaults()
    }

    // MARK: Applying decisions

    /// Reports the adapter as missing when this Mac cannot be controlled, so the policy turns off.
    private var effectiveSettings: ChargeSettings {
        var settings = settings
        if adapter == nil { settings.isEnabled = false }
        return settings
    }

    private func applyMacOSLimit(_ limit: Int) {
        guard let macOSLimit else { return }
        do {
            let current = try macOSLimit.current()
            if savedMacOSLimit == nil {
                savedMacOSLimit = current
                save(current, to: .macOSLimit)
            }
            guard !MacOSLimitTarget.isMet(by: current.isEnabled, at: current.limit, for: limit) else {
                appliedMacOSLimit = current
                return
            }
            try macOSLimit.set(limit: limit)
            appliedMacOSLimit = try macOSLimit.current()
        } catch {
            // Whatever macOS kept is Chargectl's doing, not a change made in System Settings.
            appliedMacOSLimit = try? macOSLimit.current()
            report("setting the macOS charge limit to \(limit)% failed: \(error)")
            if limit < ChargePolicy.macOSLimitAPIFloor, macOSLimitFloor < ChargePolicy.macOSLimitAPIFloor {
                macOSLimitFloor = ChargePolicy.macOSLimitAPIFloor
                log("limits below 80% will be held by switching wall power", level: .warning)
                tick()
            }
        }
    }

    /// Puts back the limit the user had before Chargectl took it over.
    private func restoreMacOSLimit() {
        guard let macOSLimit, let saved = savedMacOSLimit else { return }
        do {
            try macOSLimit.apply(saved)
            savedMacOSLimit = nil
            appliedMacOSLimit = nil
            store.remove(.macOSLimit)
            log(
                saved.isEnabled
                    ? "macOS charge limit restored to \(saved.limit)%" : "macOS charge limit turned off again")
        } catch {
            report("restoring the macOS charge limit failed: \(error)")
        }
    }

    private func connectWallPower(_ connected: Bool) {
        guard let adapter else { return }
        do {
            guard try adapter.isConnected() != connected else { return }
            try adapter.set(connected: connected)
            lastError = nil
        } catch {
            report("switching wall power failed: \(error)")
        }
    }

    private func prepareForSleep() {
        guard let adapter, (try? adapter.isConnected()) == false else { return }
        if settings.holdAsleep {
            log("sleeping with wall power cut to keep discharging", source: .chargectl)
            return
        }
        connectWallPower(true)
        state.adapterEnabled = true
        save(state, to: .state)
    }

    private func applyLED() {
        guard appliedLED != settings.magSafeLED, let smc, smc.hasKey(SMCKey.magSafeLED) else { return }
        do {
            try smc.write(SMCKey.magSafeLED, bytes: [settings.magSafeLED == .off ? 1 : 0])
            appliedLED = settings.magSafeLED
        } catch {
            report("setting the MagSafe LED failed: \(error)")
        }
    }

    private func record(_ battery: BatterySnapshot, now: Date) {
        if let last = history.last, now.timeIntervalSince(last.date) < Self.sampleInterval { return }
        history.append(
            HistorySample(
                date: now, percent: battery.percent, temperature: battery.temperature,
                systemPower: battery.systemPower, wallPower: battery.wallPower, batteryPower: battery.batteryPower))
        let cutoff = now.addingTimeInterval(-Self.historyWindow)
        history.removeAll { $0.date < cutoff }
        save(history, to: .history)
    }

    private func save<Value: Encodable>(_ value: Value, to file: Store.File) {
        guard !isRemoved else { return }
        store.save(value, to: file)
    }

    // MARK: Logging

    /// Logs what the hardware did since the last tick.
    private func observe(_ battery: BatterySnapshot) {
        let limit = macOSLimit.flatMap { try? $0.current() }
        let power = ObservedPower(
            percent: battery.percent, chargerAttached: battery.isPluggedIn,
            wallPowerConnected: adapter.flatMap { try? $0.isConnected() }, current: battery.current,
            macOSLimit: limit.flatMap { $0.isEnabled ? $0.limit : nil })
        for line in observer.changes(power) { log(line, source: .observed) }
    }

    private func log(_ message: String, level: LogEntry.Level = .info, source: LogEntry.Source? = nil) {
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        }
        logs.append(
            LogEntry(date: .now, level: level, message: message, percent: lastBattery?.percent, source: source))
        if logs.count > Self.logLimit { logs.removeFirst(logs.count - Self.logLimit) }
        save(logs, to: .logs)
    }

    /// Logs a failure once, not on every tick.
    private func report(_ message: String) {
        guard message != lastError else { return }
        lastError = message
        log(message, level: .warning)
    }
}
