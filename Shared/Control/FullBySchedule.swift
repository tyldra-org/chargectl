import Foundation

/// A full charge by a set time: Chargectl starts charging to 100% just long enough before it, so
/// the battery is full when you leave instead of waiting at 100% for hours.
nonisolated struct FullBySchedule: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int
    /// Calendar weekdays, 1 for Sunday to 7 for Saturday. Empty for a one-off on once.
    var weekdays: Set<Int> = []
    /// When a one-off is due; nil for a repeating schedule.
    var once: Date?

    static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]
    static let everyDay: Set<Int> = Set(1...7)
    /// Spare time on top of the estimate, so a slow charger still makes it.
    static let margin: TimeInterval = 15 * 60

    var isRepeating: Bool { !weekdays.isEmpty }

    /// The first time it is due after now, or nil once a one-off has passed.
    func nextDeadline(after now: Date, calendar: Calendar = .current) -> Date? {
        if let once { return once > now ? once : nil }
        guard isRepeating else { return nil }
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                weekdays.contains(calendar.component(.weekday, from: day)),
                let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), time > now
            else { continue }
            return time
        }
        return nil
    }

    /// The first time it is due after now that was not skipped: when the next one was skipped or
    /// stopped, the one after it.
    func nextDeadline(after now: Date, skipping skipped: Date?, calendar: Calendar = .current) -> Date? {
        guard let next = nextDeadline(after: now, calendar: calendar) else { return nil }
        guard let skipped, next == skipped else { return next }
        return nextDeadline(after: next, calendar: calendar)
    }

    /// How long before a deadline charging starts, from this charge: about 0.9 minutes per percent
    /// below 80% and 2.5 above, where charging slows, plus a margin.
    static func leadTime(from percent: Int) -> TimeInterval {
        let below = Double(max(0, 80 - percent)) * 0.9
        let above = Double(100 - min(max(percent, 80), 100)) * 2.5
        return (below + above) * 60 + margin
    }

    /// A one-off at the next hour:minute after now.
    static func once(hour: Int, minute: Int, after now: Date, calendar: Calendar = .current) -> FullBySchedule? {
        var schedule = FullBySchedule(hour: hour, minute: minute, weekdays: everyDay)
        guard let next = schedule.nextDeadline(after: now, calendar: calendar) else { return nil }
        schedule.weekdays = []
        schedule.once = next
        return schedule
    }

    /// "Weekdays at 8:00", "Every day at 7:30", "Mon, Wed at 9:00", "Once, Tue 8:00".
    var summary: String {
        let time = String(format: "%d:%02d", hour, minute)
        if let once {
            return "once, \(once.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
        }
        if weekdays == Self.everyDay { return "every day at \(time)" }
        if weekdays == Self.weekdaysOnly { return "weekdays at \(time)" }
        let names = Calendar(identifier: .gregorian).shortWeekdaySymbols
        // A day outside 1...7 can only come from a damaged settings file; it is left out, not trusted.
        let days = weekdays.filter { (1...7).contains($0) }.sorted().map { names[$0 - 1] }.joined(separator: ", ")
        return "\(days) at \(time)"
    }
}
