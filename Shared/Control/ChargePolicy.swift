import Foundation

nonisolated struct PolicyInput: Equatable, Sendable {
    var percent: Int
    var isPluggedIn: Bool
    /// °C
    var temperature: Double?
    /// Whether the daemon can set macOS's own charge limit through PowerUIAgent.
    var canSetMacOSLimit = false
    /// Whether the battery is taking charge right now.
    var isCharging = false
    /// The lowest macOS limit that can be set: 80 through Apple's API, lower through PowerUIAgent's
    /// own preferences.
    var macOSLimitFloor = ChargePolicy.macOSLimitAPIFloor
    /// The next Full by time, unless the user stopped that one.
    var fullBy: Date? = nil
}

nonisolated struct ChargeDecision: Equatable, Sendable {
    var state: ControlState
    var activity: ChargeActivity
    /// Set when a job starts a new phase or finishes.
    var event: String?
    /// The macOS charge limit to apply, or nil to leave it as it is.
    var macOSLimit: Int? = nil
}

/// Decides whether wall power should be connected and which limit macOS should enforce.
/// Pure: the daemon feeds it readings and applies the result.
///
/// Charging cannot be paused directly on current firmware. Two tools remain:
/// - macOS's own charge limit, which stops charging while the Mac keeps running on the charger
///   (holding), and discharges to the limit when the battery is above it. 80–100% through
///   Apple's API, lower values through PowerUIAgent's preferences.
/// - Cutting wall power (CHIE), which makes the Mac run on battery: discharging below 80%,
///   heat protection, calibration, and a fallback when macOS's limit cannot be set.
nonisolated enum ChargePolicy {
    static let calibrationFloor = 15
    static let calibrationHold: TimeInterval = 60 * 60
    /// °C below the threshold before charging resumes after a heat pause.
    static let heatHysteresis = 2.0
    /// Limits PowerUIAgent's API accepts for macOS's own charge limit.
    static let macOSLimitRange = 80...100
    static let macOSLimitAPIFloor = 80
    /// How long the battery must be idle before a hold or sailing level follows a rising reading.
    static let settledAfter: TimeInterval = 2 * 60

    static func decide(
        _ input: PolicyInput, settings: ChargeSettings, state: ControlState, now: Date
    ) -> ChargeDecision {
        var state = state
        guard settings.isEnabled else {
            state = ControlState()
            return ChargeDecision(state: state, activity: .off)
        }
        let native = input.canSetMacOSLimit

        state.heatPaused = heatPaused(input.temperature, settings: settings, wasPaused: state.heatPaused)
        let event = advance(&state.mode, percent: input.percent, fullBy: input.fullBy, now: now)
        let settingsChanged = state.lastLimit != settings.limit || state.lastAutoDischarge != settings.autoDischarge
        state.lastLimit = settings.limit
        state.lastAutoDischarge = settings.autoDischarge

        guard input.isPluggedIn else {
            state.adapterEnabled = true
            state.phase = .charging
            state.overchargeCut = false
            state.wasPluggedIn = false
            state.sailingLevel = nil
            // Set macOS's limit even on battery, so System Settings shows it and charging
            // stops at the right point the moment the charger is connected.
            let limit = unpluggedMacOSLimit(settings: settings, mode: state.mode, input: input)
            if case .calibrate(let phase, _) = state.mode {
                return ChargeDecision(state: state, activity: .calibrating(phase), event: event, macOSLimit: limit)
            }
            return ChargeDecision(state: state, activity: .onBattery, event: event, macOSLimit: limit)
        }

        let justPluggedIn = !state.wasPluggedIn
        // Refreshed at most every 30 seconds, so a charge does not rewrite the state each tick.
        if input.isCharging, state.lastChargingAt.map({ now.timeIntervalSince($0) >= 30 }) ?? true {
            state.lastChargingAt = now
        }
        let settled =
            !input.isCharging && !state.overchargeCut
            && (state.lastChargingAt.map { now.timeIntervalSince($0) >= Self.settledAfter } ?? true)
        var hold: Int?
        var holdPending = false
        if state.mode == .automatic, !settings.autoDischarge, input.percent > settings.limit, settings.limit < 100 {
            if let level = state.holdLevel {
                // The hold drops when the battery runs down on its own. With macOS's limit holding
                // it, the hold also rises when the reading creeps up without charging, as it does
                // after a restart: a macOS limit below the reading would discharge the battery.
                // Charging past the hold is an overshoot, handled below.
                let follows = input.canSetMacOSLimit && settled
                hold = follows ? input.percent : min(level, input.percent)
            } else if !state.wasPluggedIn || settingsChanged || settled {
                // Above the limit with automatic discharge off, the charge is held where it is:
                // after plugging in, after a settings change, after the helper starts, or when
                // macOS stopped a little past the limit and the battery has settled. A charge
                // still climbing past the limit is an overshoot and is brought back to it.
                hold = input.percent
            } else {
                // Past the limit, but the battery was charging moments ago: hold only once it
                // settles. Until then it stays on the charger, and charging cuts wall power.
                holdPending = true
            }
        }
        state.wasPluggedIn = true
        // Sailing: after reaching the limit, hold where the charge drifts to until it falls to the
        // lower bound, instead of topping it back up. Plugging in inside the band is the same case:
        // the charger takes over where the battery is, with no short top-up to the limit.
        var sailing = state.isSailing
        if state.mode == .automatic {
            if input.percent >= settings.limit {
                sailing = true
            } else if input.percent <= settings.lowerBound {
                sailing = false
            } else if justPluggedIn {
                sailing = true
                // Without macOS's limit, sailing means running on battery down to the lower bound.
                state.adapterEnabled = false
            }
        } else {
            sailing = false
        }
        state.phase = hold.map(HoldPhase.holdingAbove) ?? (sailing ? .sailing : .charging)
        if state.phase == .sailing {
            // macOS keeps charging a session it started even when its limit is lowered to the
            // charge, so the level must not follow a rising charge: that would raise the limit
            // ahead of the battery all the way to the limit. It follows the charge down, and up
            // only when nothing is charging, as when the reading creeps up after a restart.
            if let level = state.sailingLevel {
                let follows = input.canSetMacOSLimit && settled
                state.sailingLevel = follows ? input.percent : min(level, input.percent)
            } else {
                state.sailingLevel = input.percent
            }
        } else {
            state.sailingLevel = nil
        }
        var result = target(
            input.percent, settings: settings, state: state, native: native, floor: input.macOSLimitFloor,
            holdPending: holdPending)
        guardAgainstOvercharge(&result, input: input, settings: settings, state: &state)
        state.adapterEnabled = result.adapterEnabled
        return ChargeDecision(state: state, activity: result.activity, event: event, macOSLimit: result.macOSLimit)
    }

    /// macOS occasionally charges to 100% despite its limit (Apple: "to maintain accurate battery
    /// state-of-charge estimates"), and "Charge to Full Now" lifts it. When the battery keeps
    /// charging past the level Chargectl is holding, wall power is cut until it is back there.
    private static func guardAgainstOvercharge(
        _ result: inout Target, input: PolicyInput, settings: ChargeSettings, state: inout ControlState
    ) {
        var sailingCeiling: Int?
        if case .sailingHold = result.activity { sailingCeiling = state.sailingLevel }
        guard state.mode == .automatic, !state.heatPaused, settings.limit < 100,
            let ceiling = state.holdLevel ?? sailingCeiling
                ?? (result.adapterEnabled ? result.macOSLimit.map { max($0, settings.limit) } : nil)
        else {
            state.overchargeCut = false
            return
        }
        if input.percent <= ceiling {
            state.overchargeCut = false
            return
        }
        if input.isCharging { state.overchargeCut = true }
        guard state.overchargeCut else { return }
        result.adapterEnabled = false
        result.activity = .stoppedOvercharge(ceiling)
    }

    private static func unpluggedMacOSLimit(settings: ChargeSettings, mode: ChargeMode, input: PolicyInput) -> Int? {
        guard input.canSetMacOSLimit else { return nil }
        let floor = min(max(input.macOSLimitFloor, ChargeSettings.limitRange.lowerBound), macOSLimitAPIFloor)
        let target: Int
        switch mode {
        case .topUp, .calibrate, .fullBy: target = 100
        case .discharge: return nil
        case .automatic:
            // Inside the sailing band, a limit at the charge itself: plugged in below its limit,
            // macOS starts a charge at once and lowering the limit afterwards does not stop it.
            let insideBand = input.percent > settings.lowerBound && input.percent < settings.limit
            target = insideBand ? input.percent : settings.limit
        }
        return min(max(target, floor), macOSLimitRange.upperBound)
    }

    private static func heatPaused(_ temperature: Double?, settings: ChargeSettings, wasPaused: Bool) -> Bool {
        guard settings.heatProtection, let temperature else { return false }
        if temperature >= settings.heatThreshold { return true }
        return wasPaused && temperature > settings.heatThreshold - heatHysteresis
    }

    /// Moves a job to its next phase. Returns a log line when something changed.
    private static func advance(_ mode: inout ChargeMode, percent: Int, fullBy: Date?, now: Date) -> String? {
        switch mode {
        case .automatic:
            // Starts a Full by charge just long enough before its time.
            guard let deadline = fullBy, now < deadline,
                now >= deadline.addingTimeInterval(-FullBySchedule.leadTime(from: percent))
            else { return nil }
            mode = .fullBy(deadline)
            return "charging to 100% by \(deadline.formatted(date: .omitted, time: .shortened))"
        case .fullBy(let deadline):
            guard now >= deadline else { return nil }
            mode = .automatic
            return "full charge time reached at \(percent)%"
        case .topUp:
            guard percent >= 100 else { return nil }
            mode = .automatic
            return "top up finished at 100%"
        case .discharge(let target):
            guard percent <= target else { return nil }
            mode = .automatic
            return "discharge finished at \(percent)%"
        case .calibrate(.draining, _):
            guard percent <= calibrationFloor else { return nil }
            mode = .calibrate(.charging, since: now)
            return "calibration: reached \(percent)%, charging to 100%"
        case .calibrate(.charging, _):
            guard percent >= 100 else { return nil }
            mode = .calibrate(.holding, since: now)
            return "calibration: reached 100%, resting for an hour"
        case .calibrate(.holding, let since):
            guard now.timeIntervalSince(since) >= calibrationHold else { return nil }
            mode = .automatic
            return "calibration finished"
        }
    }

    private struct Target {
        var adapterEnabled: Bool
        var activity: ChargeActivity
        var macOSLimit: Int?
    }

    private static func target(
        _ percent: Int, settings: ChargeSettings, state: ControlState, native: Bool, floor: Int,
        holdPending: Bool = false
    ) -> Target {
        let floor = min(max(floor, ChargeSettings.limitRange.lowerBound), macOSLimitAPIFloor)
        /// A macOS limit clamped to what can be set, or nil when it cannot be set at all.
        func macOS(_ value: Int) -> Int? {
            native ? min(max(value, floor), macOSLimitRange.upperBound) : nil
        }
        let canHold = { (level: Int) in native && level >= floor }

        switch state.mode {
        case .discharge(let target):
            // From 80% macOS drains to its limit by itself; below that, wall power is cut.
            if native, target >= macOSLimitAPIFloor {
                return Target(adapterEnabled: true, activity: .discharging(to: target), macOSLimit: macOS(target))
            }
            return Target(adapterEnabled: false, activity: .discharging(to: target), macOSLimit: nil)
        case .calibrate(.draining, _):
            return Target(adapterEnabled: false, activity: .calibrating(.draining), macOSLimit: nil)
        case .calibrate(let phase, _):
            if state.heatPaused { return Target(adapterEnabled: false, activity: .heatPaused, macOSLimit: nil) }
            return Target(adapterEnabled: true, activity: .calibrating(phase), macOSLimit: macOS(100))
        case .topUp:
            if state.heatPaused { return Target(adapterEnabled: false, activity: .heatPaused, macOSLimit: nil) }
            return Target(adapterEnabled: true, activity: .toppingUp, macOSLimit: macOS(100))
        case .fullBy(let deadline):
            if state.heatPaused { return Target(adapterEnabled: false, activity: .heatPaused, macOSLimit: nil) }
            let activity: ChargeActivity = percent >= 100 ? .full : .chargingFull(by: deadline)
            return Target(adapterEnabled: true, activity: activity, macOSLimit: macOS(100))
        case .automatic:
            break
        }

        if state.heatPaused { return Target(adapterEnabled: false, activity: .heatPaused, macOSLimit: nil) }
        let limit = settings.limit
        if limit >= 100 {
            return Target(
                adapterEnabled: true, activity: percent >= 100 ? .full : .charging(to: 100), macOSLimit: macOS(100))
        }
        if let hold = state.holdLevel {
            // Automatic discharge is off: stay on the charger and leave the battery where it is.
            if canHold(hold) {
                return Target(adapterEnabled: true, activity: .holdingAbove(hold), macOSLimit: macOS(hold))
            }
            if native {
                // macOS stops charging at its floor; the charge rises at most that far.
                return Target(adapterEnabled: true, activity: .holdingAbove(hold), macOSLimit: macOS(hold))
            }
            return Target(adapterEnabled: percent <= hold, activity: .holdingAbove(hold), macOSLimit: nil)
        }
        if canHold(limit) {
            if percent > limit {
                if holdPending {
                    return Target(adapterEnabled: true, activity: .holdingAbove(percent), macOSLimit: macOS(limit))
                }
                // At 80% or more macOS discharges to its limit itself. Below that, wall power is cut
                // and the limit is set only on arrival.
                if limit >= macOSLimitAPIFloor {
                    return Target(adapterEnabled: true, activity: .aboveLimit(limit), macOSLimit: macOS(limit))
                }
                return Target(adapterEnabled: false, activity: .aboveLimit(limit), macOSLimit: nil)
            }
            if percent == limit {
                return Target(adapterEnabled: true, activity: .holding(limit), macOSLimit: macOS(limit))
            }
            let level = state.sailingLevel ?? percent
            if state.isSailing, percent > settings.lowerBound, canHold(level) {
                return Target(
                    adapterEnabled: true, activity: .sailingHold(percent, resumeAt: settings.lowerBound),
                    macOSLimit: macOS(level))
            }
            return Target(adapterEnabled: true, activity: .charging(to: limit), macOSLimit: macOS(limit))
        }

        // macOS's limit cannot go this low: hold by cutting wall power between the bounds.
        let backstop = macOS(limit)
        let sailing = ChargeActivity.sailing(limit: limit, lowerBound: settings.lowerBound)
        if percent > limit { return Target(adapterEnabled: false, activity: .aboveLimit(limit), macOSLimit: backstop) }
        if percent == limit { return Target(adapterEnabled: false, activity: sailing, macOSLimit: backstop) }
        if percent <= settings.lowerBound {
            return Target(adapterEnabled: true, activity: .charging(to: limit), macOSLimit: backstop)
        }
        // Inside the band: keep going the way we were going.
        return state.adapterEnabled
            ? Target(adapterEnabled: true, activity: .charging(to: limit), macOSLimit: backstop)
            : Target(adapterEnabled: false, activity: sailing, macOSLimit: backstop)
    }
}
