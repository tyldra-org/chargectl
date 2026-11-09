import Foundation
import IOKit.pwr_mgt
import os

/// Owns the control loop: reads the battery, asks ChargePolicy what to do, and applies it.
final class ChargeController {
    private static let tickInterval: TimeInterval = 5
    private static let sampleInterval: TimeInterval = 60
    private static let historyWindow: TimeInterval = 24 * 60 * 60
    private static let logLimit = 2000
    /// Trimmed entries a line file may still hold before it is rewritten: about an hour of
    /// history, a quarter of the log.
    private static let staleHistoryLines = 60
    private static let staleLogLines = logLimit / 4
    /// Battery reads that may fail in a row before wall power is reconnected.
    private static let failedReadsBeforeReconnect = 3
    /// Days kept in the long-term record: ten years.
    private static let dailyLimit = 3650
    /// The lowest charge the Mac may sleep at with wall power cut (see prepareForSleep).
    static let sleepReserve = 30

    /// What the app reads over XPC, published after every change.
    let board = StatusBoard()

    private let store: Store
    private let smc: SMC?
    private let reader: any BatterySource
    private let adapter: (any WallPowerSwitch)?
    /// Loaded in the background by start(): PowerUI and PowerUIAgent can take a minute to answer
    /// right after the Mac starts, and the app must reach the helper meanwhile.
    private var macOSLimit: (any MacOSLimitControl)?
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
    /// Entries in the history and log files, including ones already trimmed from memory.
    private var historyLines: Int
    private var logLines: Int
    private var lastBattery: BatterySnapshot?
    private var lastError: String?
    /// Optimized Battery Charging, read once per tick rather than for every status request.
    private var optimizedCharging: Bool?
    /// Battery reads that failed in a row.
    private var failedReads = 0
    private var controlCheck = ControlCheck()
    /// One sample a day, oldest first.
    private var daily: [DailySample]
    private var appliedLED: MagSafeLEDMode?
    private var timer: Timer?
    private var sleepWatcher: SleepWatcher?
    private var observer = PowerObserver()
    /// The service's own executable: inside Chargectl.app for SMAppService, a root-owned copy in
    /// /Library/PrivilegedHelperTools for a plist install.
    /// Absolute: launchd starts an SMAppService daemon with a path relative to the app bundle in
    /// argv[0], which does not resolve from the service's working directory.
    private let executablePath: String
    /// The app this helper belongs to: given by a plist install as --app, otherwise the bundle the
    /// helper runs from.
    private let appPath: String
    /// The helper inside that app, and its date when last seen. Installing a new app replaces it;
    /// deleting the app removes it.
    private let bundledProgram: String
    private var bundledProgramDate: Date?
    private var pendingExecutableChange: ExecutableChange?
    private var pendingExecutableChangeSince: Date?
    private static let removalGrace: TimeInterval = 30
    /// When the app was last seen running; an update within reopenWindow of it reopens the app.
    private var appLastSeen: Date?
    /// The last tick that saw this executable in place. App processes started before it run old
    /// code; a later one is the new version, perhaps started by the app's own updater.
    private var lastSeenUnchanged = Date.now
    private static let reopenWindow: TimeInterval = 120
    /// No settings were saved yet; the first limit is taken from macOS's own setting.
    private var isFirstRun: Bool
    /// Set once the app uninstalls Chargectl: nothing is written to disk after that.
    private var isRemoved = false

    convenience init(store: Store) {
        let smc = try? SMC()
        self.init(
            store: store, smc: smc, battery: BatteryReader(smc: smc), wallPower: smc.flatMap(AdapterSwitch.init(smc:)))
    }

    init(store: Store, smc: SMC?, battery: any BatterySource, wallPower: (any WallPowerSwitch)?) {
        self.store = store
        self.smc = smc
        reader = battery
        adapter = wallPower
        let stored = store.load(ChargeSettings.self, from: .settings)
        settings = stored ?? ChargeSettings()
        isFirstRun = stored == nil
        state = store.load(ControlState.self, from: .state) ?? ControlState()
        // A starting helper cannot know whether the charger was connected meanwhile; above the
        // limit with automatic discharge off, it holds the charge as if just plugged in.
        state.wasPluggedIn = false
        if state.holdLevel != nil { state.phase = .sailing }
        history = store.loadLines(HistorySample.self, from: .history)
        daily = store.loadLines(DailySample.self, from: .daily)
        logs = store.loadLines(LogEntry.self, from: .logs)
        historyLines = history.count
        logLines = logs.count
        savedMacOSLimit = store.load(MacOSChargeLimit.Setting.self, from: .macOSLimit)
        let executable = Self.ownExecutablePath()
        let arguments = CommandLine.arguments
        executablePath = executable
        appPath =
            arguments.firstIndex(of: "--app").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            ?? HelperInstall.app(containing: executable)
        bundledProgram = HelperInstall.bundledProgram(app: appPath)
        bundledProgramDate = Self.modificationDate(bundledProgram)
        publish()
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

    /// Called by start() once macOS's limit is loaded; tests call it directly.
    func finishStarting(macOSLimit limit: (any MacOSLimitControl)?) {
        compactStoredLines()
        moveOutOfApp()
        macOSLimit = limit
        if limit == nil {
            log("macOS charge limit is not available; holding the limit by switching wall power", level: .warning)
        } else {
            log(
                "PowerUIAgent preferences: \(MacOSChargeLimit.preferencesSummary(keys: ["mclLimitValue", "MCLFeatureState"]))"
            )
        }
        adoptMacOSLimitOnFirstRun()
        installStartRule()
        isReady = true
        tick()
    }

    func tick(now: Date = .now) {
        guard isReady, !isRemoved else { return }
        defer { publish() }
        if followAppUpdates() { return }
        let battery: BatterySnapshot
        do {
            battery = try reader.read(now: now)
            failedReads = 0
        } catch {
            report("battery read failed: (error)")
            failedReads += 1
            // Nothing can be decided without a reading; never leave the Mac running down its
            // battery because of it.
            if failedReads >= Self.failedReadsBeforeReconnect, let adapter, (try? adapter.isConnected()) == false {
                connectWallPower(true)
                state.adapterEnabled = true
                save(state, to: .state)
                log("wall power reconnected: the battery cannot be read", level: .warning)
            }
            return
        }
        lastBattery = battery
        // One read of macOS's limit per tick: each is a call to PowerUIAgent.
        let macOSSetting = macOSLimit.flatMap { try? $0.current() }
        optimizedCharging = macOSLimit?.isOptimizedChargingEnabled()
        observe(battery, macOSLimit: macOSSetting)
        adoptMacOSLimitChangedInSettings(current: macOSSetting)
        expireFullBy(now: now)
        var decision = decide(battery, now: now)
        if effectiveSettings.isEnabled {
            if let target = decision.macOSLimit, !applyMacOSLimit(target, current: macOSSetting) {
                // macOS refused a limit below 80%: decide again, now holding it with wall power.
                decision = decide(battery, now: now)
                if let target = decision.macOSLimit { applyMacOSLimit(target) }
            }
        } else {
            restoreMacOSLimit()
        }
        if let event = decision.event { log(event, source: .chargectl) }
        if decision.activity != activity {
            activity = decision.activity
            log(activity.summary, source: .chargectl)
        }
        connectWallPower(decision.state.adapterEnabled)
        if decision.state != state {
            state = decision.state
            save(state, to: .state)
        }
        applyLED()
        record(battery, now: now)
        recordDay(battery, now: now)
        checkControl(battery)
    }

    /// Clears a one-off Full by once its time has passed.
    private func expireFullBy(now: Date) {
        guard let schedule = settings.fullBy, schedule.once != nil, schedule.nextDeadline(after: now) == nil else {
            return
        }
        if case .fullBy = state.mode { return }
        settings.fullBy = nil
        save(settings, to: .settings)
    }

    /// The next Full by time, unless it is the one the user stopped.
    private func nextFullBy(now: Date) -> Date? {
        guard let deadline = settings.fullBy?.nextDeadline(after: now), deadline != state.skippedDeadline else {
            return nil
        }
        return deadline
    }

    /// At the first reading of a day, sums up the day before from its minute samples.
    private func recordDay(_ battery: BatterySnapshot, now: Date) {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
            daily.last.map({ $0.day < yesterday }) ?? true,
            let sample = DailySample.summarize(day: yesterday, samples: history, battery: battery, calendar: calendar)
        else { return }
        daily.append(sample)
        append(sample, to: .daily)
        if daily.count > Self.dailyLimit + 30 {
            daily.removeFirst(daily.count - Self.dailyLimit)
            if !isRemoved { store.replaceLines(daily, in: .daily) }
        }
    }

    /// Reports when cutting wall power stops having an effect, and when it works again.
    private func checkControl(_ battery: BatterySnapshot) {
        guard let adapter, let connected = try? adapter.isConnected() else { return }
        let before = controlCheck.problem
        controlCheck.observe(wallPowerCut: !connected, pluggedIn: battery.isPluggedIn, current: battery.current)
        guard controlCheck.problem != before else { return }
        if let problem = controlCheck.problem {
            log(problem, level: .warning)
        } else {
            log("cutting wall power works again", source: .chargectl)
        }
    }

    private func decide(_ battery: BatterySnapshot, now: Date) -> ChargeDecision {
        let input = PolicyInput(
            percent: battery.percent, isPluggedIn: battery.isPluggedIn, temperature: battery.temperature,
            canSetMacOSLimit: macOSLimit != nil, isCharging: battery.current > ObservedPower.flowThreshold,
            macOSLimitFloor: macOSLimitFloor, fullBy: nextFullBy(now: now))
        return ChargePolicy.decide(input, settings: effectiveSettings, state: state, now: now)
    }

    /// Whether launchd runs the helper straight from the app: SMAppService, or a plist install
    /// from before 0.1.11 until the Mac restarts.
    private var runsFromApp: Bool { executablePath == bundledProgram }

    /// Restarts into a new app version, and removes itself when Chargectl.app is gone, so a
    /// deleted app never leaves a root service behind. A change must be seen on two ticks in a
    /// row, because installing replaces the app in steps. Returns true when the process is ending.
    private func followAppUpdates() -> Bool {
        let date = Self.modificationDate(bundledProgram)
        guard date != bundledProgramDate else {
            pendingExecutableChange = nil
            lastSeenUnchanged = .now
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
        case .replaced(let date):
            reopenUpdatedApp()
            pendingExecutableChange = nil
            bundledProgramDate = date
            guard runsFromApp || installUpdatedProgram() else { return false }
            log("Chargectl was updated; restarting the helper", source: .chargectl)
            shutdown()
            // launchd starts the new executable again (KeepAlive).
            exit(0)
        }
    }

    /// Copies the updated app's helper over the root-owned one, when the new helper is signed with
    /// Chargectl's release certificate. Otherwise this helper keeps running and the app asks to
    /// install it again, with the administrator password.
    private func installUpdatedProgram() -> Bool {
        guard let requirement = DaemonIdentity.requirement(identifier: DaemonIdentity.serviceIdentifier) else {
            log(
                "Chargectl was updated; the helper stays at \(DaemonIdentity.version) until it is installed again",
                source: .chargectl)
            return false
        }
        do {
            try ProgramUpdate.install(from: bundledProgram, to: executablePath, requirement: requirement)
            return true
        } catch {
            report("the updated helper was not installed: \(error)")
            return false
        }
    }

    /// A plist install from before 0.1.11 runs the helper from inside Chargectl.app, which the user
    /// can replace. Copies it to its root-owned place and points the plist there; launchd reads
    /// the plist again when the Mac restarts.
    private func moveOutOfApp() {
        let plistURL = URL(fileURLWithPath: HelperInstall.plistPath)
        guard getuid() == 0, runsFromApp, executablePath != HelperInstall.programPath,
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let program = plist["Program"] as? String,
            URL(fileURLWithPath: program).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().path
        else { return }
        do {
            // Taken as is: this is the code already running as root.
            try ProgramUpdate.install(from: executablePath, to: HelperInstall.programPath, requirement: nil)
            let moved = try PropertyListSerialization.data(
                fromPropertyList: HelperInstall.plist(app: appPath), format: .xml, options: 0)
            try moved.write(to: plistURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: plistURL.path)
            log(
                "the helper now runs from \(HelperInstall.programPath), outside the app, from the next restart",
                source: .chargectl)
        } catch {
            report("could not move the helper out of the app: \(error)")
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
        let old = AppProcesses.running(startedBefore: lastSeenUnchanged)
        let wasRunning =
            !old.isEmpty || appLastSeen.map { Date.now.timeIntervalSince($0) < Self.reopenWindow } == true
        for pid in old { kill(pid, SIGTERM) }
        // The app's own updater may already have started the new version.
        guard wasRunning, AppProcesses.running().allSatisfy(old.contains) else { return }
        if AppProcesses.openForConsoleUser(appPath) {
            log("reopened Chargectl after the update", source: .chargectl)
        }
    }

    /// Writes HelperStartRule while the helper runs from a launchd plist, so the app can start it
    /// again after a macOS update without asking for a password. visudo checks the file before it
    /// is moved into place; a broken sudoers file would lock the administrator out of sudo.
    private func installStartRule() {
        let files = FileManager.default
        guard getuid() == 0, files.fileExists(atPath: HelperStartRule.plistPath) else { return }
        let contents = Data(HelperStartRule.contents.utf8)
        if files.contents(atPath: HelperStartRule.path) == contents { return }
        let folder = (HelperStartRule.path as NSString).deletingLastPathComponent
        let staging = "\(folder)/.chargectl.tmp"
        do {
            if !files.fileExists(atPath: folder) {
                try files.createDirectory(
                    atPath: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
            }
            try contents.write(to: URL(fileURLWithPath: staging))
            try files.setAttributes(
                [.posixPermissions: 0o440, .ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: staging)
            let visudo = Process()
            visudo.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
            visudo.arguments = ["-c", "-q", "-f", staging]
            visudo.standardOutput = FileHandle.nullDevice
            visudo.standardError = FileHandle.nullDevice
            try visudo.run()
            visudo.waitUntilExit()
            guard visudo.terminationStatus == 0 else {
                try? files.removeItem(atPath: staging)
                report("the start rule did not pass visudo; not installed")
                return
            }
            guard rename(staging, HelperStartRule.path) == 0 else { throw POSIXError(.EIO) }
            log("the app can now start the helper without a password", source: .chargectl)
        } catch {
            try? files.removeItem(atPath: staging)
            report("could not write \(HelperStartRule.path): \(error.localizedDescription)")
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
    private func adoptMacOSLimitChangedInSettings(current: MacOSChargeLimit.Setting?) {
        // A limit macOS switched off itself (its occasional charge to 100%, "Charge to Full
        // Now") is not a new choice; Chargectl turns it back on.
        // During Top Up, Discharge and Calibrate, Chargectl sets macOS's limit for the job; a change
        // then is its own doing, not the user's.
        guard settings.isEnabled, state.mode == .automatic, let applied = appliedMacOSLimit, let current,
            current.isEnabled, current != applied
        else { return }
        appliedMacOSLimit = current
        let limit = current.limit
        guard limit != settings.limit else { return }
        let previous = settings.limit
        settings.limit = limit
        settings = settings.normalized()
        save(settings, to: .settings)
        state.phase = .charging
        log("limit changed in System Settings: \(previous)% → \(settings.limit)%", source: .chargectl)
    }

    // MARK: Client requests

    func status() -> DaemonStatus {
        DaemonStatus(
            version: DaemonIdentity.version, settings: settings, mode: state.mode, activity: activity,
            adapterEnabled: state.adapterEnabled, adapterKey: adapter?.key, lastError: lastError,
            optimizedChargingEnabled: optimizedCharging, controlProblem: controlCheck.problem)
    }

    /// Hands the app's view of the helper to the XPC service.
    private func publish() {
        board.publish(status: status(), history: history, logs: logs, daily: daily)
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
            // A stopped Full by charge must not start again for the same time.
            if case .fullBy(let deadline) = state.mode { state.skippedDeadline = deadline }
            state.mode = .automatic
        case .skipFullBy:
            if case .fullBy(let deadline) = state.mode {
                state.skippedDeadline = deadline
                state.mode = .automatic
            } else if let next = settings.fullBy?.nextDeadline(after: .now) {
                state.skippedDeadline = next
            } else {
                return "There is no full charge to skip."
            }
            log(
                "full charge for \(state.skippedDeadline.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "") skipped",
                source: .chargectl)
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
        try? FileManager.default.removeItem(atPath: HelperStartRule.path)
        if getuid() == 0 {
            try? FileManager.default.removeItem(atPath: HelperInstall.stagingPath)
            // The running process keeps its copy open; launchd stops it moments later.
            try? FileManager.default.removeItem(atPath: HelperInstall.programPath)
        }
        let plist = HelperStartRule.plistPath
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

    /// The limit is kept by switching wall power rather than by macOS's own limit, which does not
    /// go this low on this Mac or is not available.
    private var holdsLimitWithWallPower: Bool {
        effectiveSettings.isEnabled && state.mode == .automatic && settings.limit < 100
            && (macOSLimit == nil || settings.limit < macOSLimitFloor)
    }

    /// Reports the adapter as missing when this Mac cannot be controlled, so the policy turns off.
    private var effectiveSettings: ChargeSettings {
        var settings = settings
        if adapter == nil { settings.isEnabled = false }
        return settings
    }

    /// Returns false when macOS refused a limit below 80% for the first time: from then on such
    /// limits are held by switching wall power, so the decision has to be made again.
    @discardableResult
    /// - Parameter cached: macOS's limit as read earlier in this tick; nil reads it again.
    private func applyMacOSLimit(_ limit: Int, current cached: MacOSChargeLimit.Setting? = nil) -> Bool {
        guard let macOSLimit else { return true }
        do {
            let current = try cached ?? macOSLimit.current()
            if savedMacOSLimit == nil {
                savedMacOSLimit = current
                save(current, to: .macOSLimit)
            }
            guard !MacOSLimitTarget.isMet(by: current.isEnabled, at: current.limit, for: limit) else {
                appliedMacOSLimit = current
                return true
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
                return false
            }
        }
        return true
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

    func prepareForSleep() {
        guard let adapter else { return }
        let connected = (try? adapter.isConnected()) ?? true
        if holdsLimitWithWallPower, let battery = lastBattery, battery.isPluggedIn,
            battery.percent >= max(settings.lowerBound, Self.sleepReserve)
        {
            // macOS's own limit cannot hold this one while the Mac sleeps, so with the charger's
            // power on it would charge to macOS's limit or full. Cut, the battery only drifts down
            // a little; charging resumes on wake if it fell below the lower bound.
            if connected {
                connectWallPower(false)
                state.adapterEnabled = false
                save(state, to: .state)
            }
            log("sleeping with wall power cut to keep the \(settings.limit)% limit", source: .chargectl)
            return
        }
        guard !connected else { return }
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
        let sample = HistorySample(
            date: now, percent: battery.percent, temperature: battery.temperature,
            systemPower: battery.systemPower, wallPower: battery.wallPower, batteryPower: battery.batteryPower)
        history.append(sample)
        let cutoff = now.addingTimeInterval(-Self.historyWindow)
        history.removeAll { $0.date < cutoff }
        append(sample, to: .history)
        historyLines += 1
        if historyLines > history.count + Self.staleHistoryLines { compactStoredLines() }
    }

    private func save<Value: Encodable>(_ value: Value, to file: Store.File) {
        guard !isRemoved else { return }
        store.save(value, to: file)
    }

    private func append<Value: Encodable>(_ value: Value, to file: Store.File) {
        guard !isRemoved else { return }
        store.append(value, to: file)
    }

    /// Rewrites the history and log files with only what is kept in memory.
    private func compactStoredLines() {
        guard !isRemoved else { return }
        let cutoff = Date.now.addingTimeInterval(-Self.historyWindow)
        history.removeAll { $0.date < cutoff }
        if logs.count > Self.logLimit { logs.removeFirst(logs.count - Self.logLimit) }
        store.replaceLines(history, in: .history)
        store.replaceLines(logs, in: .logs)
        historyLines = history.count
        logLines = logs.count
    }

    // MARK: Logging

    /// Logs what the hardware did since the last tick.
    private func observe(_ battery: BatterySnapshot, macOSLimit limit: MacOSChargeLimit.Setting?) {
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
        let entry = LogEntry(date: .now, level: level, message: message, percent: lastBattery?.percent, source: source)
        logs.append(entry)
        if logs.count > Self.logLimit { logs.removeFirst(logs.count - Self.logLimit) }
        append(entry, to: .logs)
        board.publish(logs: logs)
        logLines += 1
        if logLines > logs.count + Self.staleLogLines { compactStoredLines() }
    }

    /// Logs a failure once, not on every tick.
    private func report(_ message: String) {
        guard message != lastError else { return }
        lastError = message
        log(message, level: .warning)
    }
}
