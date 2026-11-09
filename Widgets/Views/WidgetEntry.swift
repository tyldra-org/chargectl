import Foundation
import WidgetKit

/// What every Chargectl widget shows, read once per timeline entry: the battery from IOKit, and
/// what the helper is doing, the last day and the daily record from the helper.
nonisolated struct BatteryEntry: TimelineEntry, Sendable {
    var date: Date
    var battery: BatterySnapshot?
    /// nil when the helper is not installed or not reachable.
    var status: DaemonStatus?
    /// The last 24 hours, a sample a minute.
    var history: [HistorySample] = []
    /// One sample a day.
    var daily: [DailySample] = []
    /// The latest few things Chargectl did, newest first.
    var events: [LogEntry] = []
}

/// The facts the widgets show, worked out once from an entry.
nonisolated struct WidgetFacts: Sendable {
    enum Tone: Sendable {
        case active
        case quiet
        case problem
    }

    enum Glyph: Sendable {
        case charging
        case holding
        case discharging
        case problem
    }

    let entry: BatteryEntry

    var battery: BatterySnapshot? { entry.battery }
    var status: DaemonStatus? { entry.status }
    var settings: ChargeSettings? { status?.settings }
    var percent: Int { battery?.percent ?? 0 }
    var hasHelper: Bool { status != nil }
    var isPluggedIn: Bool { battery?.isPluggedIn ?? false }

    /// The limit the ring's track ends at; nil without the helper or with charge control off.
    var limit: Int? { settings.flatMap { $0.isEnabled ? $0.limit : nil } }
    var lowerBound: Int? {
        guard let settings, settings.isEnabled, settings.sailing > 0 else { return nil }
        return settings.lowerBound
    }

    /// A Full by charge in progress.
    var deadline: Date? {
        if case .fullBy(let deadline)? = status?.mode { return deadline }
        return nil
    }

    /// Where the charge is going for a job: 100% for Top Up, Calibrate and Full by.
    var target: Int? {
        switch status?.mode {
        case .topUp?, .calibrate?, .fullBy?: 100
        default: nil
        }
    }

    /// Where the ring's track ends.
    var trackEnd: Int? { target ?? limit }

    var title: String {
        if let status { return Self.sentence(status.activity.summary) }
        guard let battery else { return "Reading the battery" }
        if !battery.isPluggedIn { return "On battery" }
        return battery.isCharging ? "Charging" : "On the charger"
    }

    var detail: String? {
        guard hasHelper else { return "macOS manages charging" }
        guard let estimate else { return nil }
        if let minutes = estimate.minutes { return "\(Self.duration(minutes)) \(estimate.caption)" }
        return Self.sentence(estimate.caption)
    }

    var tone: Tone {
        if !hasHelper || status?.controlProblem != nil { return .problem }
        if !isPluggedIn || status?.activity.isDraining == true { return .quiet }
        return .active
    }

    var glyph: Glyph? {
        guard let status else { return .problem }
        switch status.activity {
        case .charging, .toppingUp, .calibrating(.charging), .chargingFull: return .charging
        case .holding, .holdingAbove, .full, .sailingHold, .heatPaused, .calibrating(.holding): return .holding
        case .discharging, .aboveLimit, .stoppedOvercharge, .sailing, .calibrating(.draining): return .discharging
        case .onBattery, .off, .starting: return nil
        }
    }

    var estimate: ChargeEstimate? {
        battery.map { ChargeEstimate.make(battery: $0, activity: status?.activity, current: $0.current) }
    }

    /// When the charge gets where it is going, if there is a time to it.
    var finish: Date? { estimate?.minutes.map { entry.date.addingTimeInterval(Double($0) * 60) } }

    // MARK: Power

    var wallWatts: Double? { isPluggedIn && status?.adapterEnabled != false ? battery?.wallPower : nil }
    var macWatts: Double { battery?.systemPower ?? 0 }
    var batteryWatts: Double { battery?.batteryPower ?? 0 }

    var batteryFlow: String {
        if batteryWatts > 0.05 { return "into the battery" }
        if batteryWatts < -0.05 { return "from the battery" }
        return "battery resting"
    }

    // MARK: Health

    var health: Double? { battery?.health }

    /// Health a day for the last three months, today's from the live reading.
    var healthTrend: [Double] {
        let start = Calendar.current.date(byAdding: .day, value: -91, to: entry.date) ?? entry.date
        var values = entry.daily.filter { $0.day >= start }.compactMap(\.health)
        if let health { values.append(health) }
        return values.map { $0 * 100 }
    }

    /// Change in health over the trend, in points.
    var healthChange: Double? {
        let trend = healthTrend
        guard trend.count > 1, let first = trend.first, let last = trend.last else { return nil }
        return last - first
    }

    var cyclesPerMonth: Double? {
        guard let first = entry.daily.first, let battery else { return nil }
        let days = entry.date.timeIntervalSince(first.day) / 86400
        guard days >= 7 else { return nil }
        return Double(battery.cycleCount - first.cycleCount) / days * 30
    }

    /// Average hours a day at 90% or more, from the daily record.
    var highChargeHours: Double? {
        let recorded = entry.daily.suffix(91).filter { $0.minutesRecorded > 0 }
        guard !recorded.isEmpty else { return nil }
        return Double(recorded.map(\.minutesHighCharge).reduce(0, +)) / Double(recorded.count) / 60
    }

    // MARK: Today

    var today: DailySample? {
        guard let battery else { return nil }
        return DailySample.summarize(
            day: Calendar.current.startOfDay(for: entry.date), samples: entry.history, battery: battery)
    }

    var todayLowest: Int? {
        let start = Calendar.current.startOfDay(for: entry.date)
        return entry.history.filter { $0.date >= start }.map(\.percent).min()
    }

    // MARK: Full by

    /// The Full by time that was skipped or stopped, while it is still ahead.
    var skippedFullBy: Date? { status?.skippedFullBy.flatMap { $0 > entry.date ? $0 : nil } }

    var nextFullBy: Date? {
        deadline ?? settings?.fullBy?.nextDeadline(after: entry.date, skipping: skippedFullBy)
    }

    var fullByStart: Date? {
        guard deadline == nil, let next = nextFullBy else { return nil }
        return next.addingTimeInterval(-FullBySchedule.leadTime(from: percent))
    }

    // MARK: Text

    static func sentence(_ text: String) -> String {
        text.hasPrefix("macOS") ? text : text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "1 h 41 min", "12 min".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "6h 14m", "45m": for rows where space is short.
    static func shortDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func watts(_ value: Double, signed: Bool = false) -> String {
        if signed {
            if abs(value) < 0.05 { return "0.0" }
            return (value > 0 ? "+" : "\u{2212}") + String(format: "%.1f", abs(value))
        }
        return String(format: "%.1f", value)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
