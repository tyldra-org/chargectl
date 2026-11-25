import Foundation
import Testing

@Suite struct SmartLimitTests {
    /// A Wednesday at noon, UTC.
    private let now = Date(timeIntervalSince1970: 1_796_212_800)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func session(daysAgo: Double, used: Int, hours: Double = 3) -> UnplugSession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return UnplugSession(
            start: start, startPercent: 80, end: start.addingTimeInterval(hours * 3600), endPercent: 80 - used)
    }

    private func status(_ sessions: [UnplugSession], maximum: Int = 80, trip: Date? = nil) -> SmartLimit.Status {
        SmartLimit.status(sessions: sessions, now: now, maximum: maximum, tripUntil: trip, calendar: calendar)
    }

    @Test func waitsForEnoughStretches() {
        let result = status((1...4).map { session(daysAgo: Double($0) * 7, used: 20) })
        #expect(result.target == nil)
        #expect(result.sessions == 4)
    }

    @Test func todayIsAWednesday() {
        #expect(calendar.component(.weekday, from: now) == 4)
    }

    @Test func holdsTheUsualUseWithAReserve() {
        // Six Wednesdays using 20 to 40 points: nine in ten use up to 40, plus 20 in reserve.
        let used = [20, 25, 30, 35, 35, 40]
        let result = status(used.enumerated().map { session(daysAgo: Double($0.offset) * 7 + 0.1, used: $0.element) })
        #expect(result.usual == 40)
        #expect(result.target == 60)
        #expect(result.sessions == 6)
    }

    @Test func neverAboveTheLimitNorBelowTheFloor() {
        let heavy = status((1...6).map { session(daysAgo: Double($0), used: 70) }, maximum: 80)
        #expect(heavy.target == 80)
        let light = status((1...6).map { session(daysAgo: Double($0), used: 2) }, maximum: 80)
        #expect(light.target == SmartLimit.lowest)
        let lowLimit = status((1...6).map { session(daysAgo: Double($0), used: 2) }, maximum: 40)
        #expect(lowLimit.target == 40)
    }

    @Test func aTripHoldsTheFullLimit() {
        let sessions = (1...6).map { session(daysAgo: Double($0), used: 10) }
        let trip = status(sessions, trip: now.addingTimeInterval(3600))
        #expect(trip.target == 80)
        #expect(trip.boosted)
        let past = status(sessions, trip: now.addingTimeInterval(-3600))
        #expect(!past.boosted)
        #expect(past.target == 50)
    }

    @Test func ignoresShortAndOldStretches() {
        let short = (1...6).map { session(daysAgo: Double($0), used: 40, hours: 0.1) }
        let old = (1...6).map { session(daysAgo: 60 + Double($0), used: 40) }
        #expect(status(short + old).target == nil)
    }

    @Test func weekendsCountApartOnceTheyHaveEnough() {
        // Today is a Wednesday: weekday stretches use 10, weekend ones 60.
        var sessions: [UnplugSession] = []
        for week in 0..<6 {
            sessions.append(session(daysAgo: Double(week * 7) + 1, used: 10))  // Tuesday
            sessions.append(session(daysAgo: Double(week * 7) + 3, used: 60))  // Sunday
        }
        #expect(status(sessions).target == 50)
    }

    @Test func percentileIsNearestRank() {
        #expect(SmartLimit.percentile([5, 1, 3], 0.9) == 5)
        #expect(SmartLimit.percentile(Array(1...10), 0.9) == 9)
        #expect(SmartLimit.percentile([], 0.9) == 0)
    }

    @Test func tripWordsMatchTravelOnly() {
        #expect(TripWords.matches(title: "Flight to SFO", location: nil))
        #expect(TripWords.matches(title: "Dinner", location: "San Francisco International Airport"))
        #expect(TripWords.matches(title: "✈ LHR", location: nil))
        #expect(!TripWords.matches(title: "Team sync", location: "Room 4"))
        #expect(!TripWords.matches(title: "Trippy design review", location: nil))
    }
}
