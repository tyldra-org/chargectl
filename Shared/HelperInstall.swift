import Foundation

/// The helper as a launchd daemon installed with the administrator password, the route for
/// builds without an Apple team (see ServiceInstaller).
///
/// launchd runs a root-owned copy of the helper in /Library/PrivilegedHelperTools, never the copy
/// inside Chargectl.app: the app belongs to the user who installed it, so anything running as that
/// user could replace the file there and have launchd run it as root. The copy is told where the
/// app is, so it can follow the app's updates and notice when the app is deleted.
nonisolated enum HelperInstall {
    static let plistPath = "/Library/LaunchDaemons/\(DaemonIdentity.machService).plist"
    static let folder = "/Library/PrivilegedHelperTools"
    /// The helper's file name, in the app and in folder. Login Items names a launchd job that
    /// belongs to no Apple team after its program's file, so this is the name it shows.
    static let programName = "Chargectl Service"
    static let programPath = "\(folder)/\(programName)"
    /// Where a new copy is written before it is checked and moved over programPath.
    static let stagingPath = "\(programPath).new"
    /// The copy 0.2.0 to 0.2.4 installed, named after the label. Login Items showed it as
    /// "com.tyldra.chargectl.daemon" with a blank document icon, reading ".daemon" as a file type.
    static let legacyProgramPath = "\(folder)/\(DaemonIdentity.machService)"
    /// Every file a plist install may have put in folder.
    static let programFiles = [programPath, stagingPath, legacyProgramPath, "\(legacyProgramPath).new"]

    /// The helper inside a copy of Chargectl.app.
    static func bundledProgram(app: String) -> String {
        "\(app)/Contents/MacOS/\(programName)"
    }

    /// The app a bundled helper belongs to: Chargectl.app/Contents/MacOS/Chargectl Service.
    static func app(containing program: String) -> String {
        URL(fileURLWithPath: program).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path
    }

    static func plist(app: String) -> [String: Any] {
        [
            "Label": DaemonIdentity.machService,
            "ProgramArguments": [programPath, "--app", app],
            "AssociatedBundleIdentifiers": [DaemonIdentity.appIdentifier],
            "MachServices": [DaemonIdentity.machService: true],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
        ]
    }

    /// Shell commands, run as root, that copy the helper out of the app, write the plist and start
    /// the job. Stops a loaded copy first and waits until launchd has let go of it: bootout
    /// returns early, and bootstrapping too soon fails with "Bootstrap failed: 5". Unregistering an
    /// SMAppService copy leaves the label disabled, which also makes bootstrap fail, hence the
    /// enable.
    static func installCommand(app: String) -> String {
        let data =
            (try? PropertyListSerialization.data(fromPropertyList: plist(app: app), format: .xml, options: 0))
            ?? Data()
        let job = "system/\(DaemonIdentity.machService)"
        let staging = quote(stagingPath)
        return [
            "/bin/launchctl bootout \(job) 2>/dev/null",
            "for i in $(/usr/bin/jot 20); do /bin/launchctl print \(job) >/dev/null 2>&1 || break; /bin/sleep 0.25; done",
            "[ -d \(folder) ] || { /bin/mkdir -p \(folder) && /usr/sbin/chown root:wheel \(folder) && /bin/chmod 1755 \(folder); }",
            "/bin/rm -f \(staging)",
            "{ /usr/bin/ditto \(quote(bundledProgram(app: app))) \(staging) && /usr/sbin/chown root:wheel \(staging)"
                + " && /bin/chmod 755 \(staging) && /usr/bin/xattr -c \(staging) && /bin/mv -f \(staging) \(quote(programPath)); }"
                + " || { echo 'The helper could not be copied.' >&2; exit 1; }",
            "/bin/rm -f \(quote(legacyProgramPath)) \(quote("\(legacyProgramPath).new"))",
            "/bin/echo \(data.base64EncodedString()) | /usr/bin/base64 -D > \(plistPath)",
            "/usr/sbin/chown root:wheel \(plistPath)",
            "/bin/chmod 644 \(plistPath)",
            "/bin/launchctl enable \(job)",
            "for attempt in 1 2 3; do /bin/launchctl bootstrap system \(plistPath) 2>/dev/null && break; /bin/launchctl print \(job) >/dev/null 2>&1 && break; /bin/sleep 1; /bin/launchctl bootout \(job) 2>/dev/null; /bin/launchctl enable \(job); done",
            "/bin/launchctl print \(job) >/dev/null 2>&1 || { echo 'launchd did not start the helper' >&2; exit 1; }",
        ].joined(separator: "; ")
    }

    /// Stops the job and deletes its plist and program. Run as root.
    static var removeCommand: String {
        "/bin/launchctl bootout system/\(DaemonIdentity.machService) 2>/dev/null; /bin/rm -f \(plistPath) \(programFiles.map(quote).joined(separator: " "))"
    }

    /// Whether any copy of the helper is still in folder.
    static var programExists: Bool {
        programFiles.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// A shell word that stands for exactly text.
    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
