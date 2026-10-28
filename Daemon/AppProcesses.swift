import Darwin
import Foundation

/// The Chargectl app's processes, seen from the root service.
enum AppProcesses {
    /// PIDs of every running copy of the app, wherever its bundle is now: an installer may have
    /// moved the old bundle aside while it still runs.
    /// - Parameter date: only processes started before it, when given.
    static func running(startedBefore date: Date? = nil) -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var name = [CChar](repeating: 0, count: 64)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        return pids.prefix(Int(max(found, 0))).filter { pid in
            guard pid > 0, proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name) == "Chargectl",
                proc_pidpath(pid, &path, UInt32(path.count)) > 0
            else { return false }
            guard String(cString: path).hasSuffix(".app/Contents/MacOS/Chargectl") else { return false }
            guard let date else { return true }
            return startDate(of: pid).map { $0 < date } ?? true
        }
    }

    private static func startDate(of pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    /// Opens the app in the background for whoever is signed in at the screen. Returns false at
    /// the login window or when it could not be started.
    @discardableResult
    static func openForConsoleUser(_ appPath: String) -> Bool {
        var console = stat()
        guard stat("/dev/console", &console) == 0, console.st_uid != 0 else { return false }
        let uid = String(console.st_uid)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["asuser", uid, "/usr/bin/sudo", "-u", "#\(uid)", "/usr/bin/open", "-g", appPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
