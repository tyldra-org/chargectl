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

/// Installs Chargectl Service, the root launch daemon that controls charging. How depends on
/// the app's signature, because of how macOS approves background items:
///
/// - Signed with a Team ID: SMAppService. Login Items lists the helper under Chargectl, the user
///   turns it on once, and the approval belongs to the team, so updates keep working.
/// - Signed ad hoc, as releases are now: a launchd plist installed with the administrator
///   password, the way charge limiters installed helpers before SMAppService. SMAppService ties
///   an ad-hoc helper's approval to that exact build, so after every update macOS refuses to start
///   it ("Launch Constraint Violation"), and registering again does not refresh the approval. The
///   plist runs a root-owned copy of the helper (HelperInstall), which an update replaces only
///   when the new helper is signed with Chargectl's release certificate; otherwise the app asks
///   to install it again.
struct ServiceInstaller {
    enum Method: Equatable {
        case appService
        case launchdPlist
    }

    enum Registration: Equatable {
        case notRegistered
        case needsApproval
        case enabled
    }

    static let method: Method = CodeSigning.ownTeam() == nil ? .launchdPlist : .appService
    static let label = DaemonIdentity.machService
    static let plistPath = HelperInstall.plistPath
    static let dataPath = "/Library/Application Support/Chargectl"

    private static var service: SMAppService { .daemon(plistName: DaemonIdentity.plistName) }

    var registration: Registration {
        switch Self.method {
        case .launchdPlist:
            return FileManager.default.fileExists(atPath: Self.plistPath) ? .enabled : .notRegistered
        case .appService:
            switch Self.service.status {
            case .enabled: return .enabled
            case .requiresApproval: return .needsApproval
            default: return .notRegistered
            }
        }
    }

    var isInstalled: Bool { registration != .notRegistered }

    /// Installs the helper, or installs it again over a copy that stopped or runs an old version.
    func install() async throws {
        switch Self.method {
        case .launchdPlist:
            // A copy registered through SMAppService uses the same label; launchd runs only one.
            await Self.unregisterAppService()
            try await Self.runAsAdministrator(
                HelperInstall.installCommand(app: Bundle.main.bundleURL.path),
                prompt: "Chargectl needs to install its helper.")
        case .appService:
            if FileManager.default.fileExists(atPath: Self.plistPath) {
                try await Self.runAsAdministrator(
                    HelperInstall.removeCommand, prompt: "Chargectl needs to replace its old helper.")
            }
            // Registering an enabled service again changes nothing; a fresh registration makes
            // launchd take the helper inside this copy of the app.
            if Self.service.status == .enabled { try? await Self.service.unregister() }
            do {
                try Self.service.register()
            } catch {
                guard Self.service.status == .enabled || Self.service.status == .requiresApproval else {
                    throw ServiceInstallError.failed(error.localizedDescription)
                }
            }
            if Self.service.status == .requiresApproval { Self.openLoginItems() }
        }
    }

    /// Removes the helper's launchd job. The running helper deletes its own plist first, so the
    /// password is asked only when it could not.
    func remove() async throws {
        await Self.unregisterAppService()
        if FileManager.default.fileExists(atPath: Self.plistPath) || HelperInstall.programExists {
            try await Self.runAsAdministrator(
                HelperInstall.removeCommand, prompt: "Chargectl needs to remove its helper.")
        }
    }

    /// Starts an installed helper whose launchd job is not loaded, through HelperStartRule. Blocks;
    /// call off the main actor. Returns false when the job is loaded, there is no rule, or the user
    /// is not an administrator.
    nonisolated static func startWithoutPassword() -> Bool {
        guard FileManager.default.fileExists(atPath: HelperStartRule.plistPath),
            run("/bin/launchctl", ["print", "system/\(DaemonIdentity.machService)"]) != 0
        else { return false }
        _ = run("/usr/bin/sudo", ["-n"] + HelperStartRule.enable)
        return run("/usr/bin/sudo", ["-n"] + HelperStartRule.bootstrap) == 0
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
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
        let helper = HelperInstall.bundledProgram(app: Bundle.main.bundleURL.path)
        try await Self.runAsAdministrator(
            [
                "/bin/launchctl bootout system/\(Self.label) 2>/dev/null",
                // Reconnect wall power and restore the macOS charge limit before the files go.
                "\(HelperInstall.quote(helper)) --restore 2>/dev/null",
                "/bin/rm -f \(Self.plistPath) \(HelperStartRule.path) \(HelperInstall.programFiles.map(HelperInstall.quote).joined(separator: " "))",
                "/bin/rm -rf '\(Self.dataPath)'",
                rootFolders,
                "/bin/rm -f /Library/Logs/DiagnosticReports/Chargectl* /Library/Logs/DiagnosticReports/Retired/Chargectl* /Library/Logs/DiagnosticReports/chargectld* /Library/Logs/DiagnosticReports/Retired/chargectld*",
                "true",
            ].joined(separator: "; "), prompt: "Chargectl needs to remove its helper.")
    }

    /// Whether anything of the helper is still on disk.
    var leavesFiles: Bool {
        FileManager.default.fileExists(atPath: Self.plistPath) || HelperInstall.programExists
            || FileManager.default.fileExists(atPath: Self.dataPath)
    }

    /// Removes an SMAppService registration of the helper, if there is one.
    static func unregisterAppService() async {
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        try? await service.unregister()
    }

    /// Removes the Login Items entries an SMAppService registration or the login item created,
    /// whatever state they are in. Errors mean the entry was not registered, which is the goal.
    static func unregisterAll() {
        try? service.unregister()
        try? SMAppService.mainApp.unregister()
    }

    /// Runs a shell command as root after macOS's administrator password dialog.
    private static func runAsAdministrator(_ command: String, prompt: String) async throws {
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
