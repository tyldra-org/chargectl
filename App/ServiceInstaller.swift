import ServiceManagement

enum ServiceRegistration: Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
}

/// Registers chargectld (bundled in Contents/Library/LaunchDaemons) with launchd.
struct ServiceInstaller {
    private var service: SMAppService { .daemon(plistName: DaemonIdentity.plistName) }

    var registration: ServiceRegistration {
        switch service.status {
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .enabled: .enabled
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        try await service.unregister()
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Removes the daemon and login-item entries from System Settings › Login Items, whatever
    /// state they are in. Errors mean the entry was not registered, which is the goal anyway.
    static func unregisterAll() {
        try? SMAppService.daemon(plistName: DaemonIdentity.plistName).unregister()
        try? SMAppService.mainApp.unregister()
    }
}

/// `Chargectl --unregister-services` lets scripts/uninstall.sh clear the Login Items entries,
/// which only the app itself can do.
enum CommandLineActions {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--unregister-services") else { return }
        ServiceInstaller.unregisterAll()
        exit(0)
    }
}
