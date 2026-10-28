/// A sudoers rule that lets an administrator start the helper's launchd job without a password.
///
/// A macOS update moves third-party files aside and back after launchd has loaded the system's
/// daemons, so the helper's job is missing until the next restart. The app then runs exactly
/// these two commands with `sudo -n`. They can only load the root-owned plist the helper was
/// installed with; the rule allows nothing else. The helper writes the rule, as root, while its
/// plist is installed, and removes it with the plist.
nonisolated enum HelperStartRule {
    /// sudo skips files in sudoers.d whose names contain a dot.
    static let path = "/private/etc/sudoers.d/chargectl"
    static let plistPath = "/Library/LaunchDaemons/\(DaemonIdentity.machService).plist"
    static let enable = ["/bin/launchctl", "enable", "system/\(DaemonIdentity.machService)"]
    static let bootstrap = ["/bin/launchctl", "bootstrap", "system", plistPath]

    static var contents: String {
        """
        # Written by Chargectl Service; removed with it. Lets an administrator start the helper's
        # launchd job again without a password, for example after a macOS update.
        %admin ALL=(root) NOPASSWD: \(enable.joined(separator: " ")), \(bootstrap.joined(separator: " "))

        """
    }
}
