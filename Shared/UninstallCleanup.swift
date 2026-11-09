/// What Chargectl leaves outside the app and its helper, and the shell scripts that remove it.
///
/// - Uninstall removes it in the app, then runs `script` after the app quits, because a quitting
///   app writes its preferences and caches once more, and the Dock re-adds it to its recents.
/// - scripts/uninstall.sh runs the same sections, read out of this file.
/// - The helper runs `afterAppDeleted` as each user when Chargectl.app is deleted without
///   Uninstall, for example by dragging it to the Trash.
/// - The cask's zap in scripts/cask.sh lists the same Library items.
nonisolated enum UninstallCleanup {
    static let bundleIdentifier = "com.tyldra.chargectl"
    static let widgetsIdentifier = "com.tyldra.chargectl.widgets"
    static let tap = "tyldra-org/tools"
    /// The widget extension's process, which WidgetKit keeps running between timeline updates.
    static let widgetsProcess = "ChargectlWidgets"

    /// Everything in a user's Library, relative to it. The widget extension is sandboxed, so macOS
    /// gives it a container and an Application Scripts folder of its own.
    static let libraryItems = [
        "Preferences/\(bundleIdentifier).plist",
        "Caches/\(bundleIdentifier)",
        "HTTPStorages/\(bundleIdentifier)",
        "HTTPStorages/\(bundleIdentifier).binarycookies",
        "Saved Application State/\(bundleIdentifier).savedState",
        "Application Support/\(bundleIdentifier)",
        "WebKit/\(bundleIdentifier)",
        "Containers/\(widgetsIdentifier)",
        "Application Scripts/\(widgetsIdentifier)",
    ]

    /// Crash reports in Logs/DiagnosticReports: the app, its widgets and the helper (Chargectl
    /// Service, and chargectld before 0.1.5).
    static let crashReportPrefixes = ["Chargectl", "chargectld"]

    /// Waits until the app has quit (`$2` is its process ID), then a moment longer.
    static let waitForApp = """
        i=0
        while [ -n "$2" ] && /bin/kill -0 "$2" 2>/dev/null && [ "$i" -lt 100 ]; do /bin/sleep 0.1; i=$((i + 1)); done
        /bin/sleep 1
        """

    /// Removes everything in libraryItems for the user it runs as: stops the widget extension,
    /// deletes the preferences through cfprefsd so its cached copy cannot write the file back,
    /// then the files, crash reports, and the cache and temporary folders macOS keeps for the app
    /// under /private/var/folders.
    static let files = """
        id=\(bundleIdentifier); widgets=\(widgetsIdentifier); lib="$HOME/Library"
        /usr/bin/pkill -U "$(/usr/bin/id -u)" -x \(widgetsProcess) 2>/dev/null
        /usr/bin/defaults delete "$id" 2>/dev/null
        /bin/rm -rf "$lib/Preferences/$id.plist" "$lib/Caches/$id" "$lib/HTTPStorages/$id"
        /bin/rm -rf "$lib/HTTPStorages/$id.binarycookies" "$lib/Saved Application State/$id.savedState"
        /bin/rm -rf "$lib/Application Support/$id" "$lib/WebKit/$id"
        /bin/rm -rf "$lib/Containers/$widgets" "$lib/Application Scripts/$widgets"
        /bin/rm -f "$lib"/Logs/DiagnosticReports/Chargectl* "$lib"/Logs/DiagnosticReports/chargectld*
        for d in "$(/usr/bin/getconf DARWIN_USER_CACHE_DIR)" "$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"; do
          /bin/rm -rf "$d"$id*
        done
        """

    /// Copies of the app left in the Trash. Only for Uninstall: after a drag to the Trash, the
    /// copy there is the user's to put back.
    static let trash = """
        /bin/rm -rf "$HOME"/.Trash/Chargectl*.app
        """

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

    /// Uninstall's last step, run after the app quits. `$1` is brew or empty, `$2` the app's
    /// process ID.
    static let script = [waitForApp, files, trash, dock, homebrew, "true"].joined(separator: "\n") + "\n"

    /// Run by the helper, as each user, when Chargectl.app was deleted without Uninstall.
    static let afterAppDeleted = [files, dock, "true"].joined(separator: "\n") + "\n"
}
