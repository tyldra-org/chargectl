import AppKit
import Observation
import ServiceManagement

enum ServiceState: Equatable {
    case checking
    case running
    case notInstalled
    case notResponding(String)
}

struct Notice: Identifiable, Equatable {
    enum Action: Equatable {
        case installService
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
    private(set) var macOSLimit: Int?
    private(set) var macOSDrains = false
    private(set) var conflictingApp: String?
    var message: String?

    @ObservationIgnored private let reader = BatteryReader(smc: try? SMC())
    @ObservationIgnored private let client = DaemonClient()
    @ObservationIgnored private let installer = ServiceInstaller()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
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
    }

    var settings: ChargeSettings? { status?.settings }
    var isControllable: Bool { service == .running && status?.adapterKey != nil }

    /// macOS's own charge limit is running the Mac on battery while Chargectl has the charger
    /// connected. Chargectl cannot override it; only turning that limit off can.
    var macOSIsDischarging: Bool {
        guard service != .running, macOSDrains, let macOSLimit, let battery, battery.isPluggedIn,
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
                    text: "Charge control needs its helper. Install it once; macOS asks for your password.",
                    isService: true, action: .installService, actionTitle: "Install Helper"))
        case .notResponding(let reason):
            notices.append(
                Notice(
                    text: "The helper is not answering. \(reason)", isService: true, action: .installService,
                    actionTitle: "Install Again"))
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
        if let error = status?.lastError { notices.append(Notice(text: error)) }
        if let message { notices.append(Notice(text: message)) }
        return notices
    }

    func readBattery() {
        do {
            battery = try reader.read()
            batteryError = nil
        } catch {
            batteryError = "\(error)"
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
            if service != .running { message = nil }
            service = .running
            unreachableSince = nil
        } catch {
            status = nil
            if installer.isInstalled {
                // The helper restarts after an install or an app update; give it a moment before
                // calling it unresponsive.
                let since = unreachableSince ?? .now
                unreachableSince = since
                service =
                    Date.now.timeIntervalSince(since) < Self.helperStartGrace
                    ? .checking : .notResponding(error.localizedDescription)
            } else {
                unreachableSince = nil
                service = .notInstalled
            }
        }
    }

    func loadHistory() async {
        history = (try? await client.history()) ?? []
    }

    func loadLogs() async {
        logs = (try? await client.logs()) ?? []
    }

    func update(_ change: (inout ChargeSettings) -> Void) {
        guard var settings = status?.settings else { return }
        change(&settings)
        settings = settings.normalized()
        guard settings != status?.settings else { return }
        status?.settings = settings
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
        case .openBatterySettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }
    }

    private(set) var isInstallingService = false
    @ObservationIgnored private var unreachableSince: Date?

    func installService() {
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
                if service == .running {
                    try await client.perform(.removeService)
                } else if installer.isInstalled {
                    try await installer.remove()
                }
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
    /// the app itself and quits. Stops at the first step that fails, with a message.
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
        if let identifier = Bundle.main.bundleIdentifier { Self.removeUserData(identifier) }
        // Development builds outside /Applications are left alone; only installed copies go.
        let bundle = Bundle.main.bundleURL
        if bundle.path.hasPrefix("/Applications/") { try? FileManager.default.removeItem(at: bundle) }
        exit(0)
    }

    private static func removeUserData(_ identifier: String) {
        UserDefaults.standard.removePersistentDomain(forName: identifier)
        CFPreferencesAppSynchronize(identifier as CFString)
        // Goes through cfprefsd, so its cached copy cannot write the file back after it is deleted.
        let defaults = Process()
        defaults.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        defaults.arguments = ["delete", identifier]
        defaults.standardError = FileHandle.nullDevice
        try? defaults.run()
        defaults.waitUntilExit()
        DarwinDirectories.removeEntries(withPrefix: identifier)
        let files = FileManager.default
        let library = files.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let paths = [
            "Preferences/\(identifier).plist",
            "Caches/\(identifier)",
            "HTTPStorages/\(identifier)",
            "HTTPStorages/\(identifier).binarycookies",
            "Saved Application State/\(identifier).savedState",
            "Application Support/\(identifier)",
            "WebKit/\(identifier)",
        ]
        for path in paths { try? files.removeItem(at: library.appendingPathComponent(path)) }
        let reports = library.appendingPathComponent("Logs/DiagnosticReports")
        for name in (try? files.contentsOfDirectory(atPath: reports.path)) ?? []
        where name.hasPrefix("Chargectl") || name.hasPrefix("chargectld") {
            try? files.removeItem(at: reports.appendingPathComponent(name))
        }
        let trash = files.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        for name in (try? files.contentsOfDirectory(atPath: trash.path)) ?? []
        where name.hasPrefix("Chargectl") && name.hasSuffix(".app") {
            try? files.removeItem(at: trash.appendingPathComponent(name))
        }
    }

}
