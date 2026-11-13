import AppKit
import Observation
import ServiceManagement
import WidgetKit

enum ServiceState: Equatable {
    case checking
    case running
    case notInstalled
    /// Registered, waiting to be turned on in System Settings › Login Items.
    case needsApproval
    case notResponding(String)
}

struct Notice: Identifiable, Equatable {
    enum Action: Equatable {
        case installService
        case openLoginItems
        case openBatterySettings
    }

    var id: String { text }
    var text: String
    /// About the control service itself; pages that already explain it can skip these.
    var isService = false
    var action: Action?
    var actionTitle: String?
}

/// App-wide state: local battery readings plus the daemon's status, refreshed every few seconds.
@Observable
final class AppModel {
    /// Battery readings come from the SMC and refresh every second; the service is asked every
    /// third second.
    private static let refreshInterval = Duration.seconds(1)
    private static let serviceEvery = 3
    /// How long an installed helper may be unreachable while it starts or restarts.
    private static let helperStartGrace: TimeInterval = 20
    private static let conflictingApps = [
        "com.apphousekitchen.aldente-pro": "AlDente",
        "com.apphousekitchen.aldente": "AlDente",
    ]

    private(set) var battery: BatterySnapshot?
    private(set) var batteryError: String?
    private(set) var status: DaemonStatus?
    private(set) var service = ServiceState.checking
    private(set) var history: [HistorySample] = []
    private(set) var logs: [LogEntry] = []
    /// One point a day, for the long-term health chart.
    private(set) var daily: [DailySample] = []
    /// Plugged in, yet the battery runs down: the charger cannot run the Mac.
    private(set) var isChargerWeak = false
    private(set) var macOSLimit: Int?
    private(set) var macOSDrains = false
    private(set) var conflictingApp: String?
    /// Battery current smoothed over about ten seconds, so time estimates do not jump.
    private(set) var smoothedCurrent: Double?
    /// When the helper was first seen reporting a version other than the app's.
    private var versionMismatchSince: Date?
    var message: String?

    @ObservationIgnored private let reader = BatteryReader(smc: try? SMC())
    @ObservationIgnored private let client = DaemonClient()
    @ObservationIgnored private let installer = ServiceInstaller()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var chargerCheck = ChargerCheck()
    @ObservationIgnored private var notifier: Notifier?
    @ObservationIgnored private var lastSnapshot: StatusSnapshot?
    /// What the widgets and controls showed last; they reload when it changes.
    @ObservationIgnored private var lastWidgetState: WidgetState?
    /// A model built for rendering the design: never reloads or sends anything.
    @ObservationIgnored private var isPreview = false

    init() {
        notifier = Notifier()
        refreshTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                if tick % Self.serviceEvery == 0 {
                    await self?.refresh()
                } else {
                    self?.readBattery()
                }
                tick += 1
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        WidgetExtension.replaceStale()
        Updater.shared.start()
    }

    #if DEBUG
        /// Fixed state for rendering the design without a helper. Starts no tasks and talks to
        /// nothing.
        init(
            preview battery: BatterySnapshot?, status: DaemonStatus?, service: ServiceState, history: [HistorySample],
            logs: [LogEntry], macOSLimit: Int?, daily: [DailySample] = []
        ) {
            self.battery = battery
            self.status = status
            self.service = service
            self.history = history
            self.logs = logs
            self.daily = daily
            self.macOSLimit = macOSLimit
            smoothedCurrent = battery?.current
            isPreview = true
        }
    #endif

    var settings: ChargeSettings? { status?.settings }
    var isControllable: Bool { service == .running && status?.adapterKey != nil }

    /// macOS's own charge limit is running the Mac on battery while Chargectl has the charger
    /// connected. Chargectl cannot override it; only turning that limit off can.
    var macOSIsDischarging: Bool {
        // Only without a helper: an installed helper sets macOS's limit itself, also while it starts.
        guard service == .notInstalled, macOSDrains, let macOSLimit, let battery, battery.isPluggedIn,
            battery.percent > macOSLimit,
            battery.current < -0.05
        else { return false }
        return status?.adapterEnabled ?? true
    }

    /// The daemon's view when it runs, otherwise what the registry says.
    var activitySummary: String {
        // With the service running, Chargectl sets macOS's limit itself.
        if service != .running, macOSIsDischarging, let macOSLimit {
            return "macOS is discharging to its \(macOSLimit)% limit"
        }
        if let status { return status.activity.summary }
        guard let battery else { return "reading the battery" }
        if !battery.isPluggedIn { return "on battery" }
        return battery.isCharging ? "charging" : "plugged in, not charging"
    }

    var isDraining: Bool {
        if macOSIsDischarging { return true }
        if let status { return status.activity.isDraining }
        return battery.map { !$0.isPluggedIn } ?? false
    }

    var notices: [Notice] {
        var notices: [Notice] = []
        switch service {
        case .checking, .running:
            break
        case .notInstalled:
            notices.append(
                Notice(
                    text: ServiceInstaller.method == .launchdPlist
                        ? "Charge control needs its helper. Install it once; macOS asks for your password."
                        : "Charge control needs its helper. Install it once, then turn it on in Login Items.",
                    isService: true, action: .installService, actionTitle: "Install Helper"))
        case .needsApproval:
            notices.append(
                Notice(
                    text: "Turn on Chargectl in System Settings › Login Items to start charge control.",
                    isService: true, action: .openLoginItems, actionTitle: "Open Login Items"))
        case .notResponding:
            notices.append(
                Notice(
                    text: "The helper stopped. Install it again to restart charge control.", isService: true,
                    action: .installService, actionTitle: "Install Again"))
        }
        if service == .running, let helperVersion = status?.version, helperVersion != DaemonIdentity.version,
            let since = versionMismatchSince, Date.now.timeIntervalSince(since) > Self.helperStartGrace
        {
            notices.append(
                Notice(
                    text:
                        "The helper is still version \(helperVersion). Install it again to update it to \(DaemonIdentity.version).",
                    isService: true, action: .installService, actionTitle: "Install Again"))
        }
        if service == .running, status?.adapterKey == nil {
            notices.append(Notice(text: "This Mac exposes no wall-power key, so charging cannot be controlled."))
        }
        if let conflictingApp {
            notices.append(Notice(text: "\(conflictingApp) is also running. Quit it so the two don't fight."))
        }
        if macOSIsDischarging, let macOSLimit {
            notices.append(
                Notice(
                    text:
                        "macOS's own \(macOSLimit)% charge limit is running the Mac on battery. Turn it off in Battery settings so Chargectl can keep you on the charger.",
                    action: .openBatterySettings, actionTitle: "Open Battery"))
        } else if service != .running, let macOSLimit, let settings, settings.isEnabled, settings.limit > macOSLimit {
            notices.append(
                Notice(
                    text: "macOS stops charging at \(macOSLimit)%. Turn its limit off in Battery settings."))
        }
        if status?.optimizedChargingEnabled == true {
            notices.append(
                Notice(
                    text:
                        "Optimized Battery Charging is on. It can hold or delay charging by itself; turn it off so Chargectl decides.",
                    action: .openBatterySettings, actionTitle: "Open Battery"))
        }
        if let problem = status?.controlProblem { notices.append(Notice(text: problem)) }
        if isChargerWeak { notices.append(Notice(text: StatusEvent.weakCharger(battery?.adapterWatts).body)) }
        if let error = status?.lastError { notices.append(Notice(text: error)) }
        if let message { notices.append(Notice(text: message)) }
        return notices
    }

    func readBattery() {
        do {
            battery = try reader.read()
            batteryError = nil
            if let current = battery?.current { smoothCurrent(current) }
            if let battery {
                chargerCheck.observe(
                    battery, wallPowerCut: status?.adapterEnabled == false, drainsOnPurpose: isDraining, now: .now)
                if chargerCheck.isWeak != isChargerWeak { isChargerWeak = chargerCheck.isWeak }
            }
        } catch {
            batteryError = "\(error)"
        }
    }

    /// Follows a steady current slowly and a change of direction or a large step at once.
    private func smoothCurrent(_ current: Double) {
        guard let smoothed = smoothedCurrent, (smoothed > 0) == (current > 0), abs(current - smoothed) < 0.5
        else {
            smoothedCurrent = current
            return
        }
        smoothedCurrent = smoothed + (current - smoothed) * 0.15
    }

    /// Time until the charge reaches where Chargectl is taking it.
    var estimate: ChargeEstimate? {
        battery.map {
            ChargeEstimate.make(battery: $0, activity: status?.activity, current: smoothedCurrent ?? $0.current)
        }
    }

    func refresh() async {
        readBattery()
        macOSLimit = NativeChargeLimit.current()
        macOSDrains = macOSLimit != nil && NativeChargeLimit.currentDrains()
        conflictingApp =
            Self.conflictingApps.first { id, _ in
                !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            }?.value
        do {
            status = try await client.status()
            // A new helper takes a few seconds to restart after an update; only a lasting
            // difference is shown.
            if status?.version == DaemonIdentity.version {
                versionMismatchSince = nil
            } else if versionMismatchSince == nil {
                versionMismatchSince = .now
            }
            if service != .running { message = nil }
            service = .running
            unreachableSince = nil
        } catch {
            status = nil
            switch installer.registration {
            case .enabled:
                // The helper restarts after an install or an app update; give it a moment before
                // calling it unresponsive.
                let since = unreachableSince ?? .now
                unreachableSince = since
                service =
                    Date.now.timeIntervalSince(since) < Self.helperStartGrace
                    ? .checking : .notResponding(error.localizedDescription)
            case .needsApproval:
                unreachableSince = nil
                service = .needsApproval
            case .notRegistered:
                unreachableSince = nil
                service = .notInstalled
            }
        }
        repairHelperIfNeeded()
        notifyChanges()
    }

    /// Posts what changed since the last refresh; nothing on the first one.
    private func notifyChanges() {
        guard let notifier else { return }
        var helperProblem: String?
        if case .notResponding = service {
            helperProblem =
                "The helper stopped answering, so charging is not controlled. Open Chargectl to install it again."
        }
        let snapshot = StatusSnapshot(
            activity: status?.activity, mode: status?.mode, helperProblem: helperProblem, weakCharger: isChargerWeak,
            adapterWatts: battery?.adapterWatts, controlProblem: status?.controlProblem != nil)
        if let lastSnapshot { notifier.post(StatusSnapshot.events(from: lastSnapshot, to: snapshot)) }
        lastSnapshot = snapshot
        reloadWidgetsIfNeeded()
    }

    private struct WidgetState: Equatable {
        /// Whether the helper answers, so the widgets refresh as soon as it is back.
        var helperAnswers: Bool
        var activity: ChargeActivity?
        var mode: ChargeMode?
        var settings: ChargeSettings?
        var isPluggedIn: Bool?
        /// The charge in 5% steps, so the ring follows without a reload every minute.
        var charge: Int?
    }

    /// Widgets refresh every five minutes by themselves; a change made here or by the helper shows
    /// at once.
    private func reloadWidgetsIfNeeded() {
        let state = WidgetState(
            helperAnswers: service == .running, activity: status?.activity, mode: status?.mode,
            settings: status?.settings,
            isPluggedIn: battery?.isPluggedIn, charge: battery.map { $0.percent / 5 })
        guard state != lastWidgetState else { return }
        let first = lastWidgetState == nil
        lastWidgetState = state
        guard !first else { return }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    /// Only helpers with the daily record are asked; an older one keeps its version until it is
    /// installed again.
    func loadDaily() async {
        if isPreview { return }
        guard let version = status?.version, DaemonIdentity.hasDailyHistory(version) else { return }
        if let samples = try? await client.daily() { daily = samples }
    }

    func loadHistory() async {
        if isPreview { return }
        history = (try? await client.history()) ?? []
    }

    func loadLogs() async {
        if isPreview { return }
        logs = (try? await client.logs()) ?? []
    }

    func update(_ change: (inout ChargeSettings) -> Void) {
        guard var settings = status?.settings else { return }
        change(&settings)
        settings = settings.normalized()
        guard settings != status?.settings else { return }
        status?.settings = settings
        if isPreview {
            // No helper decides here, so follow the new settings the way it would.
            if let battery {
                status?.activity =
                    !settings.isEnabled
                    ? .off
                    : !battery.isPluggedIn
                        ? .onBattery
                        : battery.percent < settings.limit ? .charging(to: settings.limit) : .holding(settings.limit)
            }
            return
        }
        Task {
            do {
                try await client.update(settings)
                message = nil
            } catch {
                message = error.localizedDescription
            }
            await refresh()
        }
    }

    func perform(_ command: DaemonCommand) {
        if isPreview { return }
        Task {
            do {
                try await client.perform(command)
                message = nil
            } catch {
                message = error.localizedDescription
            }
            await refresh()
        }
    }

    func handle(_ action: Notice.Action) {
        switch action {
        case .installService: installService()
        case .openLoginItems: ServiceInstaller.openLoginItems()
        case .openBatterySettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }
    }

    private(set) var isInstallingService = false
    @ObservationIgnored private var unreachableSince: Date?
    @ObservationIgnored private var didRepairHelper = false
    @ObservationIgnored private var isStartingHelper = false
    @ObservationIgnored private var lastStartAttempt: Date?
    private static let startRetryInterval: TimeInterval = 30

    /// With SMAppService, an update or a stale registration can leave the helper registered but not
    /// running, or running an old build. Registering it again fixes that without a password, so it
    /// happens by itself, once per launch. A plist-installed helper restarts into updates itself.
    ///
    /// A plist-installed helper whose job is not loaded, which happens on the first start after a
    /// macOS update, is started again through HelperStartRule, without a password.
    private func repairHelperIfNeeded() {
        guard !isInstallingService, installer.registration == .enabled else { return }
        switch ServiceInstaller.method {
        case .launchdPlist:
            guard unreachableSince != nil, !isStartingHelper,
                lastStartAttempt.map({ Date.now.timeIntervalSince($0) > Self.startRetryInterval }) ?? true
            else { return }
            isStartingHelper = true
            lastStartAttempt = .now
            Task {
                let started = await Task.detached { ServiceInstaller.startWithoutPassword() }.value
                isStartingHelper = false
                if started {
                    unreachableSince = .now
                    try? await Task.sleep(for: .seconds(2))
                    await refresh()
                }
            }
        case .appService:
            let stopped = unreachableSince.map { Date.now.timeIntervalSince($0) > Self.helperStartGrace } ?? false
            let outdated = versionMismatchSince.map { Date.now.timeIntervalSince($0) > Self.helperStartGrace } ?? false
            guard !didRepairHelper, stopped || outdated else { return }
            didRepairHelper = true
            installService()
        }
    }

    func installService() {
        if isPreview { return }
        guard !isInstallingService else { return }
        isInstallingService = true
        Task {
            do {
                try await installer.install()
                message = nil
            } catch ServiceInstallError.cancelled {
                message = nil
            } catch {
                message = "The helper could not be installed: \(error.localizedDescription)"
            }
            isInstallingService = false
            // launchd needs a moment to start the service.
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    /// The service removes itself (reconnecting wall power first); when it is not running, an
    /// administrator removes its launchd entry instead.
    func uninstallService() {
        Task {
            do {
                // The running helper reconnects wall power and restores the macOS limit first.
                if service == .running { try? await client.perform(.removeService) }
                try await installer.remove()
                message = nil
            } catch ServiceInstallError.cancelled {
                message = nil
            } catch {
                message = "The helper could not be removed: \(error.localizedDescription)"
            }
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    /// Removes everything Chargectl added: restores charging, deletes the daemon and its data,
    /// the Login Items entries, preferences, caches, saved state and crash reports, then deletes
    /// the app itself, and Homebrew's record of it when Homebrew installed it, and quits. Stops at the first step that fails, with a message.
    func uninstallEverything() async {
        // The running helper reconnects wall power, restores the macOS charge limit and removes its
        // own files. Whatever it could not remove, or a helper that is not running, is removed as
        // an administrator.
        if service == .running {
            try? await client.perform(.uninstall)
            for _ in 0..<20 where installer.leavesFiles { try? await Task.sleep(for: .milliseconds(250)) }
        }
        if installer.leavesFiles {
            do {
                try await installer.removeAll()
            } catch ServiceInstallError.cancelled {
                message = "Uninstall stopped. The helper's files are still installed."
                return
            } catch {
                message = "Uninstall stopped: \(error.localizedDescription)"
                return
            }
        }
        ServiceInstaller.unregisterAll()
        // Development builds outside /Applications are left alone; only installed copies go. The app
        // goes first, so WidgetKit cannot start the widget extension again while its data is removed.
        let bundle = Bundle.main.bundleURL
        if bundle.path.hasPrefix("/Applications/") { try? FileManager.default.removeItem(at: bundle) }
        Self.removeUserData()
        Self.reportLeftovers()
        Self.cleanUpAfterQuitting(brew: Self.homebrewInstall)
        exit(0)
    }

    /// Homebrew's `brew`, when Homebrew installed Chargectl as the `chargectl` cask or its tap is
    /// still added. Homebrew keeps its own record of the install, a cached download and the tap,
    /// and its next install or upgrade fails when the app it recorded is gone.
    private static var homebrewInstall: URL? {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let brew = URL(fileURLWithPath: "\(prefix)/bin/brew")
            let files = FileManager.default
            if files.isExecutableFile(atPath: brew.path),
                files.fileExists(atPath: "\(prefix)/Caskroom/chargectl")
                    || files.fileExists(atPath: "\(prefix)/Library/Taps/tyldra-org/homebrew-tools")
            {
                return brew
            }
        }
        return nil
    }

    /// Starts UninstallCleanup.script, which outlives the app: once the app has quit it removes
    /// what quitting wrote again, the Dock tile and Homebrew's record.
    private static func cleanUpAfterQuitting(brew: URL?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", UninstallCleanup.script, "chargectl-cleanup", brew?.path ?? "",
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Everything in UninstallCleanup.libraryItems, while the app is still on screen: macOS may ask
    /// to allow removing the widgets' data, which it protects as another app's.
    private static func removeUserData() {
        let identifier = UninstallCleanup.bundleIdentifier
        run("/usr/bin/pkill", ["-U", String(getuid()), "-x", UninstallCleanup.widgetsProcess])
        UserDefaults.standard.removePersistentDomain(forName: identifier)
        CFPreferencesAppSynchronize(identifier as CFString)
        // Goes through cfprefsd, so its cached copy cannot write the file back after it is deleted.
        run("/usr/bin/defaults", ["delete", identifier])
        DarwinDirectories.removeEntries(withPrefix: identifier)
        let files = FileManager.default
        for item in UninstallCleanup.libraryItems { try? files.removeItem(at: library.appendingPathComponent(item)) }
        let reports = library.appendingPathComponent("Logs/DiagnosticReports")
        for name in (try? files.contentsOfDirectory(atPath: reports.path)) ?? []
        where UninstallCleanup.crashReportPrefixes.contains(where: name.hasPrefix) {
            try? files.removeItem(at: reports.appendingPathComponent(name))
        }
        let trash = files.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        for name in (try? files.contentsOfDirectory(atPath: trash.path)) ?? []
        where name.hasPrefix("Chargectl") && name.hasSuffix(".app") {
            try? files.removeItem(at: trash.appendingPathComponent(name))
        }
    }

    /// The widgets' sandbox folders when they could not be removed, which happens when macOS
    /// protects them as another app's data, shown in Finder so they can be dragged to the Trash.
    /// The other items are not checked: this process may write some of them once more before it
    /// quits, and the script after quitting removes them again.
    private static func reportLeftovers() {
        let files = FileManager.default
        let left = UninstallCleanup.libraryItems.filter { $0.hasSuffix(UninstallCleanup.widgetsIdentifier) }
            .map { library.appendingPathComponent($0) }
            .filter { files.fileExists(atPath: $0.path) }
        guard !left.isEmpty else { return }
        let home = files.homeDirectoryForCurrentUser.path
        let alert = NSAlert()
        alert.messageText =
            "macOS kept Chargectl from removing \(left.count == 1 ? "a folder" : "\(left.count) folders")"
        alert.informativeText =
            left.map { "~" + $0.path.dropFirst(home.count) }.joined(separator: "\n")
            + "\n\nEverything else is removed. Drag these to the Trash in Finder to finish."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Done")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting(left) }
    }

    private static var library: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    }

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
