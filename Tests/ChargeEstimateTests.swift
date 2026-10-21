import Foundation
import Testing

@Suite struct ChargeEstimateTests {
    /// 5000 mAh full, so 1% is 50 mAh.
    func battery(
        _ percent: Int, pluggedIn: Bool = true, current: Double, toFull: Int? = nil, toEmpty: Int? = nil
    ) -> BatterySnapshot {
        BatterySnapshot(
            date: Date(timeIntervalSince1970: 0), percent: percent, isPluggedIn: pluggedIn, isCharging: current > 0,
            cycleCount: 100, designCycleCount: 1000, designCapacity: 5760, fullChargeCapacity: 5000, voltage: 12,
            current: current, temperature: 30, adapterWatts: 35, adapterName: nil, wallPower: nil, systemPower: nil,
            chargerVoltage: nil, chargerCurrent: nil, adapterVoltage: nil, minutesToFull: toFull,
            minutesToEmpty: toEmpty)
    }

    /// 65% to 70% is 250 mAh; at 2 A that is 7.5 minutes, not macOS's time to 100%.
    @Test func chargingToTheLimitCountsToTheLimit() {
        let estimate = ChargeEstimate.make(
            battery: battery(65, current: 2, toFull: 143), activity: .charging(to: 70), current: 2)
        #expect(estimate.minutes == 8)
        #expect(estimate.caption == "until 70%")
    }

    @Test func chargingTimeNeverExceedsMacOSTimeToFull() {
        let estimate = ChargeEstimate.make(
            battery: battery(20, current: 0.5, toFull: 90), activity: .charging(to: 95), current: 0.5)
        #expect(estimate.minutes == 90)
        #expect(estimate.caption == "until 95%")
    }

    @Test func toppingUpUsesMacOSTimeToFull() {
        let estimate = ChargeEstimate.make(
            battery: battery(90, current: 1, toFull: 40), activity: .toppingUp, current: 1)
        #expect(estimate.minutes == 40)
        #expect(estimate.caption == "until full")
    }

    /// Wall power cut above the limit: 78% to 70% is 400 mAh; at 0.5 A that is 48 minutes.
    @Test func dischargingAboveTheLimitCountsDownToTheLimit() {
        let estimate = ChargeEstimate.make(
            battery: battery(78, current: -0.5, toEmpty: 400), activity: .aboveLimit(70), current: -0.5)
        #expect(estimate.minutes == 48)
        #expect(estimate.caption == "until 70%")
    }

    @Test func sailingCountsDownToTheLowerBound() {
        let estimate = ChargeEstimate.make(
            battery: battery(69, current: -1), activity: .sailing(limit: 70, lowerBound: 65), current: -1)
        #expect(estimate.minutes == 12)
        #expect(estimate.caption == "until 65%")
    }

    @Test func onBatteryShowsTimeUntilEmpty() {
        let estimate = ChargeEstimate.make(
            battery: battery(60, pluggedIn: false, current: -0.6, toEmpty: 300), activity: .onBattery, current: -0.6)
        #expect(estimate.minutes == 300)
        #expect(estimate.caption == "until empty at this rate")
    }

    @Test func holdingHasNoTime() {
        let estimate = ChargeEstimate.make(battery: battery(70, current: 0), activity: .holding(70), current: 0)
        #expect(estimate.minutes == nil)
        #expect(estimate.headline == "Holding")
        #expect(estimate.caption == "at 70% on the charger")
    }

    /// macOS has not started charging yet: no time rather than a wrong one.
    @Test func chargingWithoutCurrentWaits() {
        let estimate = ChargeEstimate.make(battery: battery(60, current: 0), activity: .charging(to: 70), current: 0)
        #expect(estimate.minutes == nil)
        #expect(estimate.headline == "Charging")
        #expect(estimate.caption == "to 70%")
    }

    @Test func withoutTheHelperFallsBackToMacOS() {
        let estimate = ChargeEstimate.make(battery: battery(50, current: 1.5, toFull: 120), activity: nil, current: 1.5)
        #expect(estimate.minutes == 120)
        #expect(estimate.caption == "until full")
    }
}
