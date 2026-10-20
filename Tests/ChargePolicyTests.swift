import Foundation
import Testing

@Suite struct ChargePolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func decide(
        _ percent: Int, pluggedIn: Bool = true, temperature: Double? = 30,
        settings: ChargeSettings = .limit(55, sailing: 5), state: ControlState = ControlState()
    ) -> ChargeDecision {
        ChargePolicy.decide(
            PolicyInput(percent: percent, isPluggedIn: pluggedIn, temperature: temperature),
            settings: settings, state: state, now: now)
    }

    @Test func disabledControlReconnectsWallPowerAndClearsJobs() {
        var settings = ChargeSettings.limit(55, sailing: 5)
        settings.isEnabled = false
        let state = ControlState(mode: .topUp, adapterEnabled: false, heatPaused: true)
        let decision = decide(80, settings: settings, state: state)
        #expect(decision.state == ControlState())
        #expect(decision.activity == .off)
    }

    @Test func unpluggedAlwaysReconnects() {
        let decision = decide(80, pluggedIn: false, state: ControlState(adapterEnabled: false))
        #expect(decision.state.adapterEnabled)
        #expect(decision.activity == .onBattery)
    }

    @Test func aboveLimitCutsWallPower() {
        let decision = decide(80)
        #expect(!decision.state.adapterEnabled)
        #expect(decision.activity == .aboveLimit(55))
        #expect(decision.activity.summary == "above the limit, discharging")
    }

    @Test func autoDischargeOffRunsOnTheCharger() {
        var settings = ChargeSettings.limit(55, sailing: 5)
        settings.autoDischarge = false
        let plugged = decide(80, settings: settings)
        #expect(plugged.state.holdLevel == 80)
        #expect(plugged.state.adapterEnabled)
        #expect(plugged.activity == .holdingAbove(80))
        #expect(plugged.activity.summary == "above the limit, running on the charger")
        #expect(!plugged.activity.isDraining)
        let unplugged = decide(78, pluggedIn: false, settings: settings, state: plugged.state)
        #expect(unplugged.state.holdLevel == nil)
    }

    /// Without macOS's limit the charger would keep charging; cut power only above the plug-in level.
    @Test func autoDischargeOffStopsChargingPastThePlugInLevel() {
        var settings = ChargeSettings.limit(55, sailing: 5)
        settings.autoDischarge = false
        let plugged = decide(70, settings: settings)
        let charged = decide(71, settings: settings, state: plugged.state)
        #expect(!charged.state.adapterEnabled)
        #expect(charged.state.holdLevel == 70)
        let back = decide(70, settings: settings, state: charged.state)
        #expect(back.state.adapterEnabled)
    }

    @Test func autoDischargeOffNeverRaisesTheHoldLevel() {
        var settings = ChargeSettings.limit(55, sailing: 5)
        settings.autoDischarge = false
        let plugged = decide(80, settings: settings)
        let lower = decide(76, settings: settings, state: plugged.state)
        #expect(lower.state.holdLevel == 76)
        #expect(decide(55, settings: settings, state: lower.state).state.holdLevel == nil)
    }

    @Test func turningAutoDischargeOnDrainsToLimit() {
        var settings = ChargeSettings.limit(55, sailing: 5)
        settings.autoDischarge = false
        let held = decide(80, settings: settings)
        settings.autoDischarge = true
        let draining = decide(80, settings: settings, state: held.state)
        #expect(draining.state.holdLevel == nil)
        #expect(draining.activity == .aboveLimit(55))
    }

    @Test func reachingLimitStartsSailing() {
        let decision = decide(55)
        #expect(!decision.state.adapterEnabled)
        #expect(decision.activity == .sailing(limit: 55, lowerBound: 50))
    }

    @Test func insideBandKeepsDirection() {
        #expect(decide(52, state: ControlState(adapterEnabled: true)).state.adapterEnabled)
        #expect(!decide(52, state: ControlState(adapterEnabled: false)).state.adapterEnabled)
    }

    @Test func lowerBoundReconnects() {
        let decision = decide(50, state: ControlState(adapterEnabled: false))
        #expect(decision.state.adapterEnabled)
        #expect(decision.activity == .charging(to: 55))
    }

    @Test func noSailingHoldsAtLimit() {
        let settings = ChargeSettings.limit(80, sailing: 0)
        #expect(decide(80, settings: settings).activity.summary == "holding at 80%")
        #expect(decide(79, settings: settings, state: ControlState(adapterEnabled: false)).state.adapterEnabled)
    }

    @Test func fullLimitNeverCutsWallPower() {
        let settings = ChargeSettings.limit(100, sailing: 5)
        #expect(decide(100, settings: settings).state.adapterEnabled)
        #expect(decide(100, settings: settings).activity == .full)
    }

    @Test func heatPausesUntilCooledBelowHysteresis() {
        var settings = ChargeSettings.limit(80, sailing: 5)
        settings.heatProtection = true
        settings.heatThreshold = 35
        let hot = decide(60, temperature: 35, settings: settings)
        #expect(hot.activity == .heatPaused)
        #expect(!hot.state.adapterEnabled)
        let cooling = decide(60, temperature: 33.5, settings: settings, state: hot.state)
        #expect(cooling.activity == .heatPaused)
        let cool = decide(60, temperature: 32.9, settings: settings, state: cooling.state)
        #expect(cool.state.adapterEnabled)
        #expect(cool.activity == .charging(to: 80))
    }

    @Test func topUpIgnoresLimitThenFinishes() {
        let topping = decide(80, state: ControlState(mode: .topUp))
        #expect(topping.state.adapterEnabled)
        #expect(topping.activity == .toppingUp)
        let done = decide(100, state: topping.state)
        #expect(done.state.mode == .automatic)
        #expect(done.event == "top up finished at 100%")
        #expect(!done.state.adapterEnabled)
    }

    @Test func dischargeRunsOnBatteryToTarget() {
        let draining = decide(70, state: ControlState(mode: .discharge(to: 55)))
        #expect(!draining.state.adapterEnabled)
        #expect(draining.activity == .discharging(to: 55))
        let done = decide(55, state: draining.state)
        #expect(done.state.mode == .automatic)
    }

    @Test func calibrationWalksThroughPhases() {
        let start = ControlState(mode: .calibrate(.draining, since: now))
        let draining = decide(40, state: start)
        #expect(!draining.state.adapterEnabled)
        let charging = decide(15, state: draining.state)
        #expect(charging.state.mode == .calibrate(.charging, since: now))
        #expect(charging.state.adapterEnabled)
        let holding = decide(100, state: charging.state)
        #expect(holding.state.mode == .calibrate(.holding, since: now))
        #expect(holding.state.adapterEnabled)
        let finished = ChargePolicy.decide(
            PolicyInput(percent: 100, isPluggedIn: true, temperature: 30), settings: .limit(55, sailing: 5),
            state: holding.state, now: now.addingTimeInterval(ChargePolicy.calibrationHold))
        #expect(finished.state.mode == .automatic)
        #expect(finished.activity == .aboveLimit(55))
    }

    func native(_ percent: Int, settings: ChargeSettings, state: ControlState = ControlState()) -> ChargeDecision {
        ChargePolicy.decide(
            PolicyInput(percent: percent, isPluggedIn: true, temperature: 30, canSetMacOSLimit: true),
            settings: settings, state: state, now: now)
    }

    /// The reported case: limit 72%, at 90%, automatic discharge off.
    @Test func autoDischargeOffHoldsOnTheChargerThroughMacOS() {
        var settings = ChargeSettings.limit(72, sailing: 5)
        settings.autoDischarge = false
        let first = native(90, settings: settings)
        #expect(first.state.adapterEnabled)
        #expect(first.macOSLimit == 90)
        #expect(first.activity == .holdingAbove(90))
        let drifted = native(88, settings: settings, state: first.state)
        #expect(drifted.macOSLimit == 88)
        #expect(drifted.state.adapterEnabled)
        let below80 = native(79, settings: settings, state: drifted.state)
        #expect(below80.macOSLimit == 80)
        #expect(below80.state.adapterEnabled)
        let charged = native(80, settings: settings, state: below80.state)
        #expect(charged.state.adapterEnabled)
        #expect(charged.macOSLimit == 80)
    }

    @Test func limitAt80OrMoreIsEnforcedByMacOS() {
        let settings = ChargeSettings.limit(85, sailing: 5)
        let below = native(60, settings: settings)
        #expect(below.state.adapterEnabled)
        #expect(below.macOSLimit == 85)
        #expect(below.activity == .charging(to: 85))
        let at = native(85, settings: settings)
        #expect(at.state.adapterEnabled)
        #expect(at.activity == .holding(85))
        #expect(!at.activity.isDraining)
        let above = native(90, settings: settings)
        #expect(above.state.adapterEnabled)
        #expect(above.activity == .aboveLimit(85))
    }

    @Test func limitBelow80CutsWallPowerWithMacOSAsBackstop() {
        let settings = ChargeSettings.limit(60, sailing: 5)
        let above = native(70, settings: settings)
        #expect(!above.state.adapterEnabled)
        #expect(above.macOSLimit == 80)
    }

    @Test func topUpLiftsTheMacOSLimit() {
        let decision = native(70, settings: .limit(85, sailing: 5), state: ControlState(mode: .topUp))
        #expect(decision.macOSLimit == 100)
        #expect(decision.state.adapterEnabled)
    }

    func below80(_ percent: Int, settings: ChargeSettings, state: ControlState = ControlState()) -> ChargeDecision {
        ChargePolicy.decide(
            PolicyInput(
                percent: percent, isPluggedIn: true, temperature: 30, canSetMacOSLimit: true, macOSLimitFloor: 20),
            settings: settings, state: state, now: now)
    }

    /// Limit 75%: discharge from 90% with wall power cut, then hold at 75% on the charger
    /// through a macOS limit of 75%.
    @Test func limitBelow80IsHeldByMacOSOnTheCharger() {
        let settings = ChargeSettings.limit(75, sailing: 5)
        let draining = below80(90, settings: settings)
        #expect(!draining.state.adapterEnabled)
        #expect(draining.macOSLimit == nil)
        #expect(draining.activity == .aboveLimit(75))
        let arrived = below80(75, settings: settings, state: draining.state)
        #expect(arrived.state.adapterEnabled)
        #expect(arrived.macOSLimit == 75)
        #expect(arrived.activity == .holding(75))
        #expect(!arrived.activity.isDraining)
    }

    @Test func sailingHoldsTheDriftedChargeUntilTheLowerBound() {
        let settings = ChargeSettings.limit(75, sailing: 5)
        let atLimit = below80(75, settings: settings)
        #expect(atLimit.state.isSailing)
        let drifted = below80(73, settings: settings, state: atLimit.state)
        #expect(drifted.state.adapterEnabled)
        #expect(drifted.macOSLimit == 73)
        #expect(drifted.activity == .sailingHold(73, resumeAt: 70))
        let resume = below80(70, settings: settings, state: drifted.state)
        #expect(!resume.state.isSailing)
        #expect(resume.macOSLimit == 75)
        #expect(resume.activity == .charging(to: 75))
    }

    @Test func autoDischargeOffBelow80HoldsTheCurrentCharge() {
        var settings = ChargeSettings.limit(60, sailing: 5)
        settings.autoDischarge = false
        let decision = below80(75, settings: settings)
        #expect(decision.state.adapterEnabled)
        #expect(decision.macOSLimit == 75)
        #expect(decision.activity == .holdingAbove(75))
    }

    @Test func refusedBelow80FallsBackToWallPower() {
        let settings = ChargeSettings.limit(60, sailing: 5)
        let decision = native(60, settings: settings)
        #expect(!decision.state.adapterEnabled)
        #expect(decision.macOSLimit == 80)
    }

    @Test func macOSLimitFollowsTheSettingOnBattery() {
        let decision = ChargePolicy.decide(
            PolicyInput(percent: 78, isPluggedIn: false, temperature: 30, canSetMacOSLimit: true, macOSLimitFloor: 20),
            settings: .limit(85, sailing: 5), state: ControlState(), now: now)
        #expect(decision.activity == .onBattery)
        #expect(decision.macOSLimit == 85)
        #expect(decision.state.adapterEnabled)
    }

    func plugged(_ percent: Int, charging: Bool, settings: ChargeSettings, state: ControlState) -> ChargeDecision {
        ChargePolicy.decide(
            PolicyInput(
                percent: percent, isPluggedIn: true, temperature: 30, canSetMacOSLimit: true, isCharging: charging,
                macOSLimitFloor: 20),
            settings: settings, state: state, now: now)
    }

    /// macOS's occasional charge to 100%: the battery keeps charging past the limit.
    @Test func chargingPastTheLimitCutsWallPowerUntilBackAtIt() {
        var settings = ChargeSettings.limit(80, sailing: 5)
        settings.autoDischarge = false
        let atLimit = plugged(80, charging: false, settings: settings, state: ControlState())
        #expect(atLimit.state.adapterEnabled)
        let overshoot = plugged(81, charging: true, settings: settings, state: atLimit.state)
        #expect(overshoot.state.holdLevel == nil)
        #expect(!overshoot.state.adapterEnabled)
        #expect(overshoot.activity == .stoppedOvercharge(80))
        let draining = plugged(81, charging: false, settings: settings, state: overshoot.state)
        #expect(!draining.state.adapterEnabled)
        let back = plugged(80, charging: false, settings: settings, state: draining.state)
        #expect(back.state.adapterEnabled)
        #expect(!back.state.overchargeCut)
    }

    @Test func plugInAboveTheLimitStillHolds() {
        var settings = ChargeSettings.limit(80, sailing: 5)
        settings.autoDischarge = false
        let unplugged = ChargePolicy.decide(
            PolicyInput(percent: 90, isPluggedIn: false, temperature: 30, canSetMacOSLimit: true, macOSLimitFloor: 20),
            settings: settings, state: ControlState(), now: now)
        let pluggedIn = plugged(90, charging: false, settings: settings, state: unplugged.state)
        #expect(pluggedIn.state.holdLevel == 90)
        #expect(pluggedIn.state.adapterEnabled)
        #expect(pluggedIn.macOSLimit == 90)
    }

    @Test func autoDischargeIsOffByDefault() {
        #expect(!ChargeSettings().autoDischarge)
    }
}

extension ChargeSettings {
    /// Automatic discharge on, so tests above the limit exercise draining unless they turn it off.
    static func limit(_ limit: Int, sailing: Int) -> ChargeSettings {
        var settings = ChargeSettings()
        settings.limit = limit
        settings.sailing = sailing
        settings.autoDischarge = true
        return settings
    }
}
