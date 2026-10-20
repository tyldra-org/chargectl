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

/// Command-line entry points for scripts/install.sh and scripts/uninstall.sh. Only the app
/// itself can register its service with SMAppService, which is what lets macOS list the service
/// under Chargectl's name and icon in Login Items.
enum CommandLineActions {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.contains("--register-service") {
            exit(registerService())
        }
        if arguments.contains("--unregister-service") {
            try? SMAppService.daemon(plistName: DaemonIdentity.plistName).unregister()
            exit(0)
        }
        if arguments.contains("--unregister-services") {
            ServiceInstaller.unregisterAll()
            exit(0)
        }
    }

    /// Prints the result for the script: 0 running, 2 waiting for approval, 1 failed.
    private static func registerService() -> Int32 {
        let service = SMAppService.daemon(plistName: DaemonIdentity.plistName)
        do {
            try service.register()
        } catch {
            if service.status != .enabled && service.status != .requiresApproval {
                print("failed: \(error.localizedDescription)")
                return 1
            }
        }
        switch service.status {
        case .enabled:
            print("enabled")
            return 0
        case .requiresApproval:
            print("requires approval")
            return 2
        default:
            print("failed: status \(service.status.rawValue)")
            return 1
        }
    }
}
