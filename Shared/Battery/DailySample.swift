import Foundation

/// One day of the battery's long-term record: capacity and cycles, and how the day treated the
/// battery. Written once a day by the helper and kept for years, so the app can show whether
/// health is holding up.
nonisolated struct DailySample: Codable, Equatable, Sendable {
    /// Start of the day, local time.
    var day: Date
    /// mAh the battery holds when full, and when it was new.
    var fullChargeCapacity: Int
    var designCapacity: Int
    var cycleCount: Int
    /// Minutes of the day with a reading, on the charger, and at 90% or more.
    var minutesRecorded: Int
    var minutesPlugged: Int
    var minutesHighCharge: Int
    /// °C
    var averageTemperature: Double?
    var maxTemperature: Double?

    /// Health as a fraction of the design capacity.
    var health: Double? {
        designCapacity > 0 ? Double(fullChargeCapacity) / Double(designCapacity) : nil
    }

    static let highCharge = 90

    /// The day that starts at day, from the minute samples recorded in it, with capacity and cycles
    /// from battery. Nil when nothing was recorded that day.
    static func summarize(
        day: Date, samples: [HistorySample], battery: BatterySnapshot, calendar: Calendar = .current
    ) -> DailySample? {
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        let inDay = samples.filter { $0.date >= day && $0.date < end }
        guard !inDay.isEmpty else { return nil }
        let temperatures = inDay.compactMap(\.temperature)
        return DailySample(
            day: day, fullChargeCapacity: battery.fullChargeCapacity, designCapacity: battery.designCapacity,
            cycleCount: battery.cycleCount, minutesRecorded: inDay.count,
            minutesPlugged: inDay.filter { ($0.wallPower ?? 0) > 0.5 }.count,
            minutesHighCharge: inDay.filter { $0.percent >= highCharge }.count,
            averageTemperature: temperatures.isEmpty ? nil : temperatures.reduce(0, +) / Double(temperatures.count),
            maxTemperature: temperatures.max())
    }
}
