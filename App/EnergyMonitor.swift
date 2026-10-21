import AppKit
import Darwin
import Observation

/// Which apps use the most energy, like the "Using Significant Energy" list in macOS's battery
/// menu. Samples each app's energy counter every few seconds (a browser's helpers count for the
/// browser, a command for its terminal) and averages over the last minute.
@Observable
final class EnergyMonitor {
    struct App: Identifiable, Equatable {
        /// The app bundle's path.
        let id: String
        let name: String
        /// Average W over the window.
        let watts: Double
    }

    static let interval = Duration.seconds(5)
    /// Seconds averaged.
    static let window: TimeInterval = 60
    /// Apps below this many watts are not listed.
    static let significant = 0.25
    static let maxApps = 5

    private(set) var apps: [App] = []
    /// False until two samples exist.
    private(set) var isMeasuring = true

    @ObservationIgnored private var previous: [UInt64: EnergySampler.Reading] = [:]
    @ObservationIgnored private var previousDate: Date?
    @ObservationIgnored private var intervals: [(end: Date, seconds: TimeInterval, joules: [String: Double])] = []
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    /// Samples until the calling task is cancelled.
    func run() async {
        while !Task.isCancelled {
            let readings = await Task.detached(priority: .utility) { EnergySampler.read() }.value
            record(readings, at: .now)
            try? await Task.sleep(for: Self.interval)
        }
    }

    func icon(for app: App) -> NSImage {
        if let icon = icons[app.id] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.id)
        icons[app.id] = icon
        return icon
    }

    private func record(_ readings: [UInt64: EnergySampler.Reading], at date: Date) {
        defer {
            previous = readings
            previousDate = date
        }
        // After a long pause (the page was hidden) the old counters are only a new baseline.
        guard let start = previousDate, date.timeIntervalSince(start) < Self.window else { return }
        var joules: [String: Double] = [:]
        for (coalition, reading) in readings {
            guard let before = previous[coalition], before.app == reading.app, reading.nanojoules >= before.nanojoules
            else { continue }
            joules[reading.app, default: 0] += Double(reading.nanojoules - before.nanojoules) / 1e9
        }
        intervals.append((date, date.timeIntervalSince(start), joules))
        intervals.removeAll { date.timeIntervalSince($0.end) > Self.window }
        let seconds = intervals.reduce(0) { $0 + $1.seconds }
        guard seconds > 0 else { return }
        var total: [String: Double] = [:]
        for interval in intervals { total.merge(interval.joules, uniquingKeysWith: +) }
        apps = total.map { App(id: $0.key, name: Self.name(of: $0.key), watts: $0.value / seconds) }
            .filter { $0.watts >= Self.significant }
            .sorted { $0.watts > $1.watts }
            .prefix(Self.maxApps)
            .map { $0 }
        isMeasuring = false
    }

    private static func name(of path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Reads energy per resource coalition: the group launchd makes for each app, which also holds
/// its helpers and the commands it starts and keeps counting after they exit, so short-lived
/// processes are not missed. Each coalition is credited to the app responsible for its processes.
nonisolated enum EnergySampler {
    struct Reading: Sendable {
        /// Path of the responsible app bundle.
        let app: String
        /// Energy the coalition has used since it was created, nJ.
        let nanojoules: UInt64
    }

    /// libproc's PROC_PIDCOALITIONINFO; not in the public headers.
    private static let pidCoalitionInfo: Int32 = 20
    /// Index of energy, nJ, in xnu's struct coalition_resource_usage, whose leading fields are stable.
    private static let energyField = 11

    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t
    private typealias ResourceUsage = @convention(c) (UInt64, UnsafeMutableRawPointer, Int) -> Int32

    /// libsystem functions Activity Monitor uses, looked up at run time because they are not in
    /// the public headers: the process responsible for another one, and a coalition's usage.
    private static let responsiblePID: ResponsiblePID? = symbol("responsibility_get_pid_responsible_for_pid")
    private static let resourceUsage: ResourceUsage? = symbol("coalition_info_resource_usage")

    private static func symbol<T>(_ name: String) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }

    static func read() -> [UInt64: Reading] {
        guard let resourceUsage else { return [:] }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var apps: [UInt64: String] = [:]
        for pid in pids.prefix(Int(max(found, 0))) where pid > 0 {
            guard let coalition = coalition(of: pid), apps[coalition] == nil else { continue }
            let owner = responsiblePID?(pid) ?? pid
            if let app = appBundle(of: owner > 0 ? owner : pid) ?? appBundle(of: pid) { apps[coalition] = app }
        }
        var readings: [UInt64: Reading] = [:]
        var usage = [UInt64](repeating: 0, count: 128)
        for (coalition, app) in apps {
            let result = usage.withUnsafeMutableBytes { resourceUsage(coalition, $0.baseAddress!, $0.count) }
            guard result == 0 else { continue }
            readings[coalition] = Reading(app: app, nanojoules: usage[energyField])
        }
        return readings
    }

    private static func coalition(of pid: pid_t) -> UInt64? {
        // struct proc_pidcoalitioninfo: coalition IDs by type (resource first), then three reserved.
        var info = [UInt64](repeating: 0, count: 5)
        let size = Int32(info.count * MemoryLayout<UInt64>.size)
        guard proc_pidinfo(pid, pidCoalitionInfo, 0, &info, size) == size, info[0] != 0 else { return nil }
        return info[0]
    }

    /// The outermost .app around the process's executable, leaving out macOS's own.
    private static func appBundle(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard !path.hasPrefix("/System/"), let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
