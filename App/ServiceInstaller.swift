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

/// Installs Chargectl Service as a launchd daemon with administrator rights, the way charge
/// limiters such as AlDente install their helpers. macOS shows its password dialog; an
/// administrator-installed daemon counts as approved, so it is on straight away and starts with
/// the Mac. The daemon runs from inside the app bundle, so app updates update it too.
struct ServiceInstaller {
    static let label = DaemonIdentity.machService
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    var isInstalled: Bool { FileManager.default.fileExists(atPath: Self.plistPath) }

    func install() async throws {
        // Older versions registered the service through SMAppService under the same label;
        // launchd refuses a second job with that label.
        await Self.unregisterAppService()
        let program = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Chargectl Service").path
        let plist = Self.launchdPlist(program: program).base64EncodedString()
        let path = Self.plistPath
        let label = Self.label
        let job = "system/\(label)"
        try await Self.runAsAdministrator(
            [
                // Stop a helper that is already loaded, and wait until launchd has let go of it:
                // bootout returns early, and bootstrapping too soon fails with "Bootstrap failed: 5".
                "/bin/launchctl bootout \(job) 2>/dev/null",
                "for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do /bin/launchctl print \(job) >/dev/null 2>&1 || break; /bin/sleep 0.25; done",
                "/bin/echo \(plist) | /usr/bin/base64 -D > \(path) && /usr/sbin/chown root:wheel \(path) && /bin/chmod 644 \(path)",
                // Unregistering an SMAppService copy leaves the label disabled in launchd, which
                // also makes bootstrap fail.
                "/bin/launchctl enable \(job)",
                "for attempt in 1 2 3; do /bin/launchctl bootstrap system \(path) 2>/dev/null && break; /bin/launchctl print \(job) >/dev/null 2>&1 && break; /bin/sleep 1; /bin/launchctl bootout \(job) 2>/dev/null; /bin/launchctl enable \(job); done",
                "/bin/launchctl print \(job) >/dev/null 2>&1 || { echo 'launchd did not start the helper' >&2; exit 1; }",
            ].joined(separator: "; "))
    }

    /// For when the service cannot remove itself (it is not running).
    func remove() async throws {
        try await Self.runAsAdministrator(
            "/bin/launchctl bootout system/\(Self.label) 2>/dev/null; /bin/rm -f \(Self.plistPath)")
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
                "/bin/rm -f \(Self.plistPath)",
                "/bin/rm -rf '\(Self.dataPath)'",
                rootFolders,
                "true",
            ].joined(separator: "; "))
    }

    static let dataPath = "/Library/Application Support/Chargectl"

    /// Whether anything of the helper is still on disk.
    var leavesFiles: Bool {
        FileManager.default.fileExists(atPath: Self.plistPath) || FileManager.default.fileExists(atPath: Self.dataPath)
    }

    /// Removes an SMAppService registration of the helper, if there is one. Unregistering also
    /// disables the label in launchd, so it is skipped when nothing is registered.
    static func unregisterAppService() async {
        let service = SMAppService.daemon(plistName: DaemonIdentity.plistName)
        guard service.status == .enabled || service.status == .requiresApproval else { return }
        try? await service.unregister()
    }

    /// Removes the Login Items entries an SMAppService registration or the login item created,
    /// whatever state they are in. Errors mean the entry was not registered, which is the goal.
    static func unregisterAll() {
        try? SMAppService.daemon(plistName: DaemonIdentity.plistName).unregister()
        try? SMAppService.mainApp.unregister()
    }

    static func launchdPlist(program: String) -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "Program": program,
            "AssociatedBundleIdentifiers": [DaemonIdentity.appIdentifier],
            "MachServices": [label: true],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
        ]
        // A dictionary of plist types always serializes.
        return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
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
