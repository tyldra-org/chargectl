import Foundation
import Testing

@Suite struct BatteryWearTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ count: Int, percent: Int, plugged: Bool, from offset: Int = 0) -> [HistorySample] {
        (0..<count).map {
            HistorySample(
                date: start.addingTimeInterval(Double(offset + $0) * 60), percent: percent, temperature: 25,
                pluggedIn: plugged)
        }
    }

    @Test func rateIsOneAtHalfChargeAndRisesWithChargeAndHeat() {
        #expect(abs(BatteryWear.rate(percent: 50, temperature: 25) - 1) < 1e-9)
        #expect(abs(BatteryWear.rate(percent: 100, temperature: 25) - 2.5) < 1e-9)
        #expect(abs(BatteryWear.rate(percent: 50, temperature: 35) - 2) < 1e-9)
        #expect(BatteryWear.rate(percent: 70, temperature: 25) < BatteryWear.rate(percent: 80, temperature: 25))
    }

    @Test func holdingAtTheLimitWearsLessThanHoldingFull() {
        let samples = minutes(60, percent: 70, plugged: true)
        let totals = BatteryWear.totals(samples: samples, from: start, to: start.addingTimeInterval(3600))
        #expect(abs((totals?.actual ?? 0) - 60 * BatteryWear.rate(percent: 70, temperature: 25)) < 1e-6)
        #expect(abs((totals?.baseline ?? 0) - 60 * 2.5) < 1e-6)
    }

    /// Off the charger the baseline battery starts full and drains the same points.
    @Test func baselineDrainsFromFullOffTheCharger() {
        let samples = minutes(1, percent: 70, plugged: true) + minutes(1, percent: 60, plugged: false, from: 1)
        let totals = BatteryWear.totals(
            samples: samples, from: start.addingTimeInterval(60), to: start.addingTimeInterval(120))
        #expect(abs((totals?.baseline ?? 0) - BatteryWear.rate(percent: 90, temperature: 25)) < 1e-9)
        #expect(abs((totals?.actual ?? 0) - BatteryWear.rate(percent: 60, temperature: 25)) < 1e-9)
    }

    @Test func wallPowerCutStillCountsAsPluggedIn() {
        let sample = HistorySample(
            date: start, percent: 70, temperature: 25, wallPower: 0, batteryPower: -5, pluggedIn: true)
        let totals = BatteryWear.totals(samples: [sample], from: start, to: start.addingTimeInterval(60))
        #expect(abs((totals?.baseline ?? 0) - 2.5) < 1e-9)
    }

    @Test func nothingInRangeHasNoTotals() {
        let samples = minutes(5, percent: 50, plugged: true)
        #expect(BatteryWear.totals(samples: samples, from: start.addingTimeInterval(-600), to: start) == nil)
    }

    @Test func savingsAddUpTheDaysWithAnEstimate() {
        func day(_ actual: Double?, _ baseline: Double?) -> DailySample {
            DailySample(
                day: start, fullChargeCapacity: 5000, designCapacity: 5760, cycleCount: 200, minutesRecorded: 1440,
                minutesPlugged: 1000, minutesHighCharge: 0, averageTemperature: 25, maxTemperature: 26,
                wearActual: actual, wearBaseline: baseline)
        }
        #expect(BatteryWear.savings([day(nil, nil)]) == nil)
        let savings = BatteryWear.savings([day(1, 2), day(1, 2), day(nil, nil)])
        #expect(savings?.days == 2)
        #expect(abs((savings?.lessWear ?? 0) - 0.5) < 1e-9)
        #expect(abs((savings?.daysAvoided ?? 0) - 1) < 1e-9)
    }

    @Test func cellsWarnOnlyWhenFarApartAtRest() {
        #expect(CellBalance.spread([4286, 4284, 4283]) == 3)
        #expect(CellBalance.spread([4286]) == nil)
        let wide = [4000, 3930, 3990]
        #expect(CellBalance.wideReadings(after: 5, cells: wide, current: 0.05) == 6)
        #expect(CellBalance.wideReadings(after: 5, cells: wide, current: -1.5) == 5)
        #expect(CellBalance.wideReadings(after: 5, cells: [4000, 3995], current: 0) == 0)
        #expect(CellBalance.wideReadings(after: 5, cells: nil, current: 0) == 5)
    }
}
