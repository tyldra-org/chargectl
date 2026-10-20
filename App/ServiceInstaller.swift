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
        try? await SMAppService.daemon(plistName: DaemonIdentity.plistName).unregister()
        let program = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/Chargectl Service").path
        let plist = Self.launchdPlist(program: program).base64EncodedString()
        let path = Self.plistPath
        let label = Self.label
        try await Self.runAsAdministrator(
            [
                "/bin/launchctl bootout system/\(label) 2>/dev/null || true",
                "/bin/echo \(plist) | /usr/bin/base64 -D > \(path)",
                "/usr/sbin/chown root:wheel \(path)",
                "/bin/chmod 644 \(path)",
                "/bin/launchctl bootstrap system \(path)",
            ].joined(separator: " && "))
    }

    /// For when the service cannot remove itself (it is not running).
    func remove() async throws {
        try await Self.runAsAdministrator(
            "/bin/launchctl bootout system/\(Self.label) 2>/dev/null; /bin/rm -f \(Self.plistPath)")
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
            try? SMAppService.daemon(plistName: DaemonIdentity.plistName).unregister()
            exit(0)
        }
        if arguments.contains("--unregister-services") {
            ServiceInstaller.unregisterAll()
            exit(0)
        }
    }
}
