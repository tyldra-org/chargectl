import Foundation

/// What a deleted Chargectl.app left in each user's Library: preferences, caches, widget data,
/// crash reports and the Dock tile. Removed as that user with UninstallCleanup.afterAppDeleted,
/// when the helper finds the app gone without Uninstall, for example dragged to the Trash.
nonisolated enum UserCleanup {
    static func removeForEveryUser() {
        guard getuid() == 0 else { return }
        let files = FileManager.default
        for name in (try? files.contentsOfDirectory(atPath: "/Users")) ?? [] where !name.hasPrefix(".") {
            let home = "/Users/\(name)"
            guard let owner = (try? files.attributesOfItem(atPath: home))?[.ownerAccountID] as? NSNumber,
                owner.intValue >= 501, files.fileExists(atPath: "\(home)/Library")
            else { continue }
            // In the user's session, so the Dock it restarts is theirs; a user who is not logged in
            // has none, so their files are removed without it.
            let asUser = [
                "/usr/bin/sudo", "-u", "#\(owner.intValue)", "-H", "/bin/sh", "-c", UninstallCleanup.afterAppDeleted,
            ]
            if run("/bin/launchctl", ["asuser", String(owner.intValue)] + asUser) != 0 {
                run(asUser[0], Array(asUser.dropFirst()))
            }
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
