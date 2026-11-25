import Foundation

/// An estimate of calendar ageing: the wear a lithium-ion battery takes from sitting at a high
/// charge, faster when it is warm. Relative only, 1 at 50% and 25 °C. Published ageing studies put
/// storage at 100% at roughly two to three times the wear of storage at 50%, and ageing roughly
/// doubles every 10 °C; this model uses 2.5 and 10 °C. It is not a measurement of this battery.
nonisolated enum BatteryWear {
    /// Wear at 100% relative to 50%.
    static let fullChargeFactor = 2.5
    /// °C for the wear to double.
    static let doublingDegrees = 10.0

    /// Wear per minute at a charge level and temperature, 1 at 50% and 25 °C.
    static func rate(percent: Int, temperature: Double?) -> Double {
        let charge = Double(min(max(percent, 0), 100))
        let celsius = min(max(temperature ?? 25, 0), 60)
        return pow(fullChargeFactor, (charge - 50) / 50) * pow(2, (celsius - 25) / doublingDegrees)
    }

    nonisolated struct Totals: Equatable, Sendable {
        /// Wear the battery took.
        var actual: Double
        /// Wear under macOS's default: charged to 100% whenever plugged in, and off the charger the
        /// same drain from there.
        var baseline: Double
    }

    /// Wear from the minute samples in [start, end). Samples before start only set where the
    /// baseline stood when the charger was last unplugged. Nil when no sample falls in the range.
    static func totals(samples: [HistorySample], from start: Date, to end: Date) -> Totals? {
        var totals = Totals(actual: 0, baseline: 0)
        var counted = 0
        // Points the baseline battery is above this one since the charger was unplugged.
        var offset = 0
        var lastPluggedPercent: Int?
        var wasPlugged = false
        for sample in samples.sorted(by: { $0.date < $1.date }) where sample.date < end {
            let plugged = sample.pluggedIn ?? ((sample.wallPower ?? 0) > 0.5)
            if plugged {
                lastPluggedPercent = sample.percent
            } else if wasPlugged {
                offset = max(0, 100 - (lastPluggedPercent ?? sample.percent))
            }
            wasPlugged = plugged
            guard sample.date >= start else { continue }
            let baseline = plugged ? 100 : min(100, sample.percent + offset)
            totals.actual += rate(percent: sample.percent, temperature: sample.temperature)
            totals.baseline += rate(percent: baseline, temperature: sample.temperature)
            counted += 1
        }
        return counted > 0 ? totals : nil
    }

    nonisolated struct Savings: Equatable, Sendable {
        /// Days with an estimate.
        var days: Int
        /// Fraction less wear than the baseline, 0–1.
        var lessWear: Double
        /// Days of the baseline's ageing avoided.
        var daysAvoided: Double
    }

    /// The days' wear against the baseline. Nil before any day has an estimate.
    static func savings(_ days: [DailySample]) -> Savings? {
        let rated = days.filter { ($0.wearBaseline ?? 0) > 0 && $0.wearActual != nil && $0.minutesRecorded > 0 }
        guard !rated.isEmpty else { return nil }
        let actual = rated.compactMap(\.wearActual).reduce(0, +)
        let baseline = rated.compactMap(\.wearBaseline).reduce(0, +)
        let less = min(max(1 - actual / baseline, 0), 1)
        let minutes = Double(rated.map(\.minutesRecorded).reduce(0, +))
        return Savings(days: rated.count, lessWear: less, daysAvoided: minutes * less / (24 * 60))
    }
}
