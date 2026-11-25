import Foundation

/// A stretch off the charger: when it was unplugged and plugged in again, and the charge at each.
nonisolated struct UnplugSession: Codable, Equatable, Sendable {
    var start: Date
    var startPercent: Int
    var end: Date
    var endPercent: Int

    /// Points of charge used.
    var used: Int { max(0, startPercent - endPercent) }
}

/// The smart limit: instead of one number for every day, hold what the user usually needs off the
/// charger, from their own unplugged stretches, with a reserve on top. Never above the limit they
/// set, which stays the maximum.
nonisolated enum SmartLimit {
    /// The lowest it holds.
    static let lowest = 50
    /// Points kept on top of the usual use, for a longer day than usual.
    static let reserve = 20
    /// Stretches needed before it suggests anything.
    static let minimumSessions = 5
    /// Shorter stretches off the charger are not counted.
    static let shortestSession: TimeInterval = 10 * 60
    /// How far back stretches count.
    static let lookback: TimeInterval = 42 * 24 * 60 * 60
    /// Stretches kept on disk.
    static let keptSessions = 400

    nonisolated struct Status: Codable, Equatable, Sendable {
        /// The level to hold today; nil until enough stretches are recorded.
        var target: Int?
        /// Points used off the charger on nine days in ten, of the stretches counted.
        var usual: Int?
        /// Stretches counted so far.
        var sessions: Int
        /// A calendar trip is coming, so it holds the full limit.
        var boosted = false
    }

    /// The level to hold now. Weekdays and weekends are counted apart once each has enough
    /// stretches. With a trip ahead it holds the maximum.
    static func status(
        sessions: [UnplugSession], now: Date, maximum: Int, tripUntil: Date?, calendar: Calendar = .current
    ) -> Status {
        let recent = sessions.filter {
            $0.end > now.addingTimeInterval(-lookback) && $0.end.timeIntervalSince($0.start) >= shortestSession
        }
        let weekend = calendar.isDateInWeekend(now)
        let same = recent.filter { calendar.isDateInWeekend($0.start) == weekend }
        let pool = same.count >= minimumSessions ? same : recent
        guard pool.count >= minimumSessions else { return Status(target: nil, usual: nil, sessions: recent.count) }
        let usual = percentile(pool.map(\.used), 0.9)
        if let tripUntil, tripUntil > now {
            return Status(target: maximum, usual: usual, sessions: recent.count, boosted: true)
        }
        let rounded = Int((Double(usual + reserve) / 5).rounded(.up)) * 5
        let target = maximum <= lowest ? maximum : min(max(rounded, lowest), maximum)
        return Status(target: target, usual: usual, sessions: recent.count)
    }

    /// Nearest-rank percentile.
    static func percentile(_ values: [Int], _ fraction: Double) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }
}

/// Words in a calendar event that suggest the Mac will be away from a charger.
nonisolated enum TripWords {
    static let pattern =
        #"(?i)(\b(flight|flights|fly|flying|trip|travel|travelling|traveling|airport|train|offsite|off-site|conference|vacation)\b|✈)"#

    static func matches(title: String?, location: String?) -> Bool {
        [title, location].compactMap { $0 }.contains { $0.range(of: pattern, options: .regularExpression) != nil }
    }
}
