import Foundation

nonisolated enum CalibrationPhase: String, Codable, Sendable {
    /// Running on battery down to the calibration floor.
    case draining
    /// Charging to 100%.
    case charging
    /// Resting at 100% so the gauge can settle.
    case holding
}

/// A temporary job that overrides the limit until it finishes or is stopped.
nonisolated enum ChargeMode: Codable, Equatable, Sendable {
    case automatic
    case topUp
    case discharge(to: Int)
    case calibrate(CalibrationPhase, since: Date)
    /// Charging to 100% for a Full by time, held there until it passes.
    case fullBy(Date)

    var title: String {
        switch self {
        case .automatic: "automatic"
        case .topUp: "top up"
        case .discharge: "discharge"
        case .calibrate: "calibration"
        case .fullBy: "full charge"
        }
    }
}

/// Where an automatic charge stands while the charger is connected. One value instead of a hold
/// level and a sailing flag, so the two can never disagree.
nonisolated enum HoldPhase: Codable, Equatable, Sendable {
    /// Charging up to the limit, or holding at it.
    case charging
    /// Reached the limit: the charge is held wherever it drifts until it falls to the lower
    /// bound (limit − sailing), instead of being topped up in short bursts.
    case sailing
    /// Plugged in above the limit with automatic discharge off: the charge is held at this level
    /// until the charger is unplugged or the charge falls to the limit, then it sails.
    case holdingAbove(Int)

    /// The level held above the limit, if any.
    var holdLevel: Int? {
        if case .holdingAbove(let level) = self { return level }
        return nil
    }

    /// Whether the charge has reached the limit and is not being charged back up yet.
    var isSailing: Bool { self != .charging }
}

/// What the daemon remembers between ticks and restarts.
nonisolated struct ControlState: Codable, Equatable, Sendable {
    var mode = ChargeMode.automatic
    /// Whether wall power should be connected.
    var adapterEnabled = true
    /// Latched while the battery is too warm; clears 2 °C below the threshold.
    var heatPaused = false
    /// Where an automatic charge stands while plugged in; always .charging otherwise.
    var phase = HoldPhase.charging
    /// Plugged in on the previous decision; a hold level is only taken when plugging in.
    var wasPluggedIn = false
    /// Wall power was cut because macOS kept charging past the target (its occasional charge to
    /// 100%, or "Charge to Full Now"); stays cut until the charge is back at the target.
    var overchargeCut = false
    /// The limit and automatic discharge setting on the previous decision. Changing either while
    /// plugged in above the limit starts a hold, the same as plugging in; nil after an update.
    var lastLimit: Int?
    var lastAutoDischarge: Bool?
    /// A Full by time the user stopped; it does not start again.
    var skippedDeadline: Date?

    var holdLevel: Int? { phase.holdLevel }
    var isSailing: Bool { phase.isSailing }

    init(
        mode: ChargeMode = .automatic, adapterEnabled: Bool = true, heatPaused: Bool = false,
        phase: HoldPhase = .charging
    ) {
        self.mode = mode
        self.adapterEnabled = adapterEnabled
        self.heatPaused = heatPaused
        self.phase = phase
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ChargeMode.self, forKey: .mode) ?? .automatic
        adapterEnabled = try container.decodeIfPresent(Bool.self, forKey: .adapterEnabled) ?? true
        heatPaused = try container.decodeIfPresent(Bool.self, forKey: .heatPaused) ?? false
        if let phase = try container.decodeIfPresent(HoldPhase.self, forKey: .phase) {
            self.phase = phase
        } else {
            // Versions before 0.1.11 kept a hold level and a sailing flag.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            if let level = try legacy.decodeIfPresent(Int.self, forKey: .holdLevel) {
                phase = .holdingAbove(level)
            } else if try legacy.decodeIfPresent(Bool.self, forKey: .isSailing) == true {
                phase = .sailing
            }
        }
        wasPluggedIn = try container.decodeIfPresent(Bool.self, forKey: .wasPluggedIn) ?? false
        overchargeCut = try container.decodeIfPresent(Bool.self, forKey: .overchargeCut) ?? false
        lastLimit = try container.decodeIfPresent(Int.self, forKey: .lastLimit)
        lastAutoDischarge = try container.decodeIfPresent(Bool.self, forKey: .lastAutoDischarge)
        skippedDeadline = try container.decodeIfPresent(Date.self, forKey: .skippedDeadline)
    }

    private enum CodingKeys: String, CodingKey {
        case mode, adapterEnabled, heatPaused, phase, wasPluggedIn, overchargeCut, lastLimit, lastAutoDischarge
        case skippedDeadline
    }

    private enum LegacyKeys: String, CodingKey {
        case holdLevel, isSailing
    }
}

/// What the battery is doing and why, for status lines and logs.
nonisolated enum ChargeActivity: Codable, Equatable, Sendable {
    /// The helper is loading macOS's charge limit; nothing is decided yet.
    case starting
    case off
    case onBattery
    case charging(to: Int)
    case full
    /// Wall power is cut inside the sailing band; charge drifts down to the lower bound.
    case sailing(limit: Int, lowerBound: Int)
    /// Wall power is cut because the charge is above the limit.
    case aboveLimit(Int)
    /// Above the limit with automatic discharge off: the Mac runs on the charger and the
    /// battery is left at this level.
    case holdingAbove(Int)
    /// At the limit, running on the charger without charging.
    case holding(Int)
    /// Sailing below the limit: held on the charger at this level until it falls to resumeAt.
    case sailingHold(Int, resumeAt: Int)
    /// macOS charged past the target anyway; wall power is cut until the charge is back.
    case stoppedOvercharge(Int)
    case discharging(to: Int)
    case heatPaused
    case toppingUp
    case calibrating(CalibrationPhase)
    /// Charging to 100% for a Full by time.
    case chargingFull(by: Date)

    var summary: String {
        switch self {
        case .starting: "starting charge control"
        case .off: "charge control off"
        case .onBattery: "on battery"
        case .charging(let target): "charging to \(target)%"
        case .full: "fully charged"
        case .sailing(let limit, let lowerBound):
            limit == lowerBound ? "holding at \(limit)%" : "sailing down to \(lowerBound)%"
        case .aboveLimit: "above the limit, discharging"
        case .holdingAbove: "above the limit, running on the charger"
        case .holding(let level): "holding at \(level)%, running on the charger"
        case .sailingHold(_, let resumeAt): "sailing on the charger, charges again at \(resumeAt)%"
        case .stoppedOvercharge(let target): "macOS kept charging past \(target)%; running on battery back to it"
        case .discharging(let target): "discharging to \(target)%"
        case .heatPaused: "too warm, charging paused"
        case .toppingUp: "topping up to 100%"
        case .chargingFull(let deadline): "charging to 100% by \(deadline.formatted(date: .omitted, time: .shortened))"
        case .calibrating(.draining): "calibrating, draining to \(ChargePolicy.calibrationFloor)%"
        case .calibrating(.charging): "calibrating, charging to 100%"
        case .calibrating(.holding): "calibrating, resting at 100%"
        }
    }

    /// True while the battery, not the charger, powers the Mac on purpose.
    var isDraining: Bool {
        switch self {
        case .sailing, .aboveLimit, .discharging, .heatPaused, .calibrating(.draining), .stoppedOvercharge: true
        case .holdingAbove: false
        default: false
        }
    }
}
