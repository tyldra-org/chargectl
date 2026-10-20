import Foundation
import ServiceManagement

enum ServiceInstallError: LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Installation was cancelled."
        case .failed(let reason): reason
        }
    }
}

/// Installs Chargectl Service with SMAppService. macOS lists it under Chargectl in System
/// Settings › General › Login Items & Extensions and asks the user to turn it on there once;
/// after that launchd runs it as root, also while the app is closed.
struct ServiceInstaller {
    enum Registration: Equatable {
        case notRegistered
        case needsApproval
        case enabled
    }

    static let label = DaemonIdentity.machService
    /// Where versions before SMAppService installed the helper with an administrator prompt.
    static let legacyPlistPath = "/Library/LaunchDaemons/\(label).plist"

    private var service: SMAppService { .daemon(plistName: DaemonIdentity.plistName) }

    var registration: Registration {
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return FileManager.default.fileExists(atPath: Self.legacyPlistPath) ? .enabled : .notRegistered
        }
    }

    var isInstalled: Bool { registration != .notRegistered }

    func install() async throws {
        // A helper installed by an older version uses the same label; launchd runs only one.
        if FileManager.default.fileExists(atPath: Self.legacyPlistPath) {
            try await Self.runAsAdministrator(
                "/bin/launchctl bootout system/\(Self.label) 2>/dev/null; /bin/rm -f \(Self.legacyPlistPath)")
        }
        do {
            try service.register()
        } catch {
            guard service.status == .enabled || service.status == .requiresApproval else {
                throw ServiceInstallError.failed(error.localizedDescription)
            }
        }
        if service.status == .requiresApproval { Self.openLoginItems() }
    }

    func remove() async throws {
        if service.status == .enabled || service.status == .requiresApproval {
            try await service.unregister()
        }
        if FileManager.default.fileExists(atPath: Self.legacyPlistPath) {
            try await Self.runAsAdministrator(
                "/bin/launchctl bootout system/\(Self.label) 2>/dev/null; /bin/rm -f \(Self.legacyPlistPath)")
        }
    }

    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Everything the helper leaves outside the user's home folder: its launchd job and plist,
    /// its data, and root's cache and temporary folders. Used by Uninstall when the helper could
    /// not clean up after itself.
    func removeAll() async throws {
        let rootFolders =
            "for d in \"$(/usr/bin/getconf DARWIN_USER_CACHE_DIR)\" \"$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)\"; do /bin/rm -rf \"$d\"com.tyldra.chargectl*; done"
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Chargectl Service").path
        try await Self.runAsAdministrator(
            [
                "/bin/launchctl bootout system/\(Self.label) 2>/dev/null",
                // Reconnect wall power and restore the macOS charge limit before the files go.
                "'\(helper)' --restore 2>/dev/null",
                "/bin/rm -f \(Self.legacyPlistPath)",
                "/bin/rm -rf '\(Self.dataPath)'",
                rootFolders,
                "true",
            ].joined(separator: "; "))
    }

    static let dataPath = "/Library/Application Support/Chargectl"

    /// Whether anything of the helper is still on disk.
    var leavesFiles: Bool {
        FileManager.default.fileExists(atPath: Self.legacyPlistPath)
            || FileManager.default.fileExists(atPath: Self.dataPath)
    }

    /// Removes the Login Items entries an SMAppService registration or the login item created,
    /// whatever state they are in. Errors mean the entry was not registered, which is the goal.
    static func unregisterAll() {
        try? SMAppService.daemon(plistName: DaemonIdentity.plistName).unregister()
        try? SMAppService.mainApp.unregister()
    }

    /// Runs a shell command as root after macOS's administrator password dialog.
    private static func runAsAdministrator(_ command: String) async throws {
        let prompt = "Chargectl needs to install its helper to control charging."
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else if output.contains("-128") {
                    continuation.resume(throwing: ServiceInstallError.cancelled)
                } else {
                    continuation.resume(
                        throwing: ServiceInstallError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Command-line entry points for scripts/install.sh and scripts/uninstall.sh: only the app can
/// remove its own SMAppService registrations and login item.
enum CommandLineActions {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.contains("--unregister-service") {
            let service = SMAppService.daemon(plistName: DaemonIdentity.plistName)
            if service.status == .enabled || service.status == .requiresApproval { try? service.unregister() }
            exit(0)
        }
        if arguments.contains("--unregister-services") {
            ServiceInstaller.unregisterAll()
            exit(0)
        }
    }
}
