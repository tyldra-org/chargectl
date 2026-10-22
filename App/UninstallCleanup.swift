/// What Uninstall removes after Chargectl has quit, as one shell script: Chargectl's tile in the
/// Dock (kept in Recent Applications, or pinned) and what Homebrew keeps of the cask. It runs
/// after the app quits because the Dock re-adds a quitting app to its recents, and the cask's
/// uninstall step stops the app.
enum UninstallCleanup {
    static let bundleIdentifier = "com.tyldra.chargectl"
    static let tap = "tyldra-org/tools"

    /// Removes Chargectl from the Dock's pinned and recent apps through cfprefsd, then restarts
    /// the Dock if anything changed.
    static let dock = """
        plist=$(/usr/bin/mktemp -t chargectl-dock); changed=0
        /usr/bin/defaults export com.apple.dock "$plist"
        for section in persistent-apps recent-apps; do
          count=$(/usr/bin/plutil -extract "$section" raw -o - "$plist" 2>/dev/null) || continue
          index=$((count - 1))
          while [ "$index" -ge 0 ]; do
            id=$(/usr/bin/plutil -extract "$section.$index.tile-data.bundle-identifier" raw -o - "$plist" 2>/dev/null)
            if [ "$id" = \(bundleIdentifier) ]; then
              /usr/bin/plutil -remove "$section.$index" "$plist" && changed=1
            fi
            index=$((index - 1))
          done
        done
        if [ "$changed" = 1 ]; then /usr/bin/defaults import com.apple.dock "$plist"; /usr/bin/killall Dock; fi
        /bin/rm -f "$plist"
        """

    /// Removes Homebrew's record of the cask, its cached downloads, and the tap when nothing else
    /// from it is installed. `$1` is brew. `--force` succeeds although the app is already
    /// deleted; everything the cask's zap lists is already removed by then.
    static let homebrew = """
        if [ -n "$1" ]; then
          export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
          "$1" uninstall --cask --force \(tap)/chargectl
          "$1" cleanup --prune=all \(tap)/chargectl
          "$1" list --full-name 2>/dev/null | /usr/bin/grep -q '^\(tap)/' || "$1" untap \(tap)
        fi
        """

    static let script = "sleep 2\n\(dock)\n\(homebrew)\ntrue\n"
}
