import EventKit
import Foundation

/// Finds trips in the user's calendar for the smart limit: an event in the next day whose title or
/// location reads like travel (TripWords). Reads only; asks for access when turned on.
@MainActor
final class CalendarTrips {
    static let shared = CalendarTrips()
    /// How far ahead a trip counts.
    static let lookahead: TimeInterval = 24 * 60 * 60

    private let store = EKEventStore()

    static var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks for calendar access; true when granted.
    func requestAccess() async -> Bool {
        if Self.isAuthorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// When the next trip starts, within lookahead; nil without one or without access.
    func nextTrip(now: Date = .now) -> Date? {
        guard Self.isAuthorized else { return nil }
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(Self.lookahead), calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.startDate > now && TripWords.matches(title: $0.title, location: $0.location) }
            .map(\.startDate)
            .min()
    }
}
