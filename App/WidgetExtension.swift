import Darwin
import Foundation
import WidgetKit

/// The widgets' extension process, which macOS starts and keeps running on its own.
enum WidgetExtension {
    /// Stops widget processes started from another copy of Chargectl, so macOS starts this one.
    ///
    /// macOS keeps an extension running after its app is replaced or moved to the Trash. The old
    /// process then draws the widget gallery and the widgets from a bundle that is gone, and they
    /// come out empty until the Mac restarts. Stopping it is safe: macOS starts the extension again
    /// the next time a widget needs it.
    ///
    /// A process is stale when it runs from somewhere other than this app's bundle (the Trash, an
    /// old build), or, on the first launch of a new version, when it started before this launch:
    /// an update in place keeps the path but replaces the files under the running process.
    static func replaceStale() {
        #if DEBUG
            // A development build would take the widgets over from the installed app.
            return
        #else
            let defaults = UserDefaults.standard
            let version = DaemonIdentity.version
            let updated = defaults.string(forKey: PreferenceKey.lastLaunchedVersion) != version
            defaults.set(version, forKey: PreferenceKey.lastLaunchedVersion)
            let ours = Bundle.main.builtInPlugInsURL?
                .appendingPathComponent("ChargectlWidgets.appex/Contents/MacOS/ChargectlWidgets")
                .resolvingSymlinksInPath().path
            let launched = startDate(of: getpid()) ?? Date()
            let stale = processes().filter { process in
                process.path != ours || (updated && process.started.map { $0 < launched } ?? true)
            }
            guard !stale.isEmpty else { return }
            for process in stale { kill(process.pid, SIGTERM) }
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadAllControls()
        #endif
    }

    private struct Process {
        let pid: pid_t
        /// nil once the executable is deleted, as an update in place does.
        let path: String?
        let started: Date?
    }

    /// Every running widget extension of this user, wherever its bundle is.
    private static func processes() -> [Process] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        var name = [CChar](repeating: 0, count: 64)
        let uid = getuid()
        return pids.prefix(Int(max(found, 0))).compactMap { pid in
            guard pid > 0, owner(of: pid) == uid else { return nil }
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                let path = String(cString: buffer)
                guard path.hasSuffix("/ChargectlWidgets.appex/Contents/MacOS/ChargectlWidgets") else { return nil }
                return Process(pid: pid, path: path, started: startDate(of: pid))
            }
            // No path: the executable was deleted under the running process.
            guard proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "ChargectlWidgets" else {
                return nil
            }
            return Process(pid: pid, path: nil, started: startDate(of: pid))
        }
    }

    private static func bsdInfo(of pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private static func owner(of pid: pid_t) -> uid_t? { bsdInfo(of: pid)?.pbi_uid }

    private static func startDate(of pid: pid_t) -> Date? {
        bsdInfo(of: pid).map {
            Date(timeIntervalSince1970: Double($0.pbi_start_tvsec) + Double($0.pbi_start_tvusec) / 1_000_000)
        }
    }
}
