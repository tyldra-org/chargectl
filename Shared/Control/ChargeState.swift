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

    var title: String {
        switch self {
        case .automatic: "automatic"
        case .topUp: "top up"
        case .discharge: "discharge"
        case .calibrate: "calibration"
        }
    }
}

/// What the daemon remembers between ticks and restarts.
nonisolated struct ControlState: Codable, Equatable, Sendable {
    var mode = ChargeMode.automatic
    /// Whether wall power should be connected.
    var adapterEnabled = true
    /// Latched while the battery is too warm; clears 2 °C below the threshold.
    var heatPaused = false
    /// With automatic discharge off: the charge when the Mac was plugged in above the limit,
    /// held until it is unplugged or drops to the limit.
    var holdLevel: Int?
    /// Reached the limit and has not yet fallen to the lower bound (limit − sailing).
    var isSailing = false

    init(mode: ChargeMode = .automatic, adapterEnabled: Bool = true, heatPaused: Bool = false, holdLevel: Int? = nil) {
        self.mode = mode
        self.adapterEnabled = adapterEnabled
        self.heatPaused = heatPaused
        self.holdLevel = holdLevel
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(ChargeMode.self, forKey: .mode) ?? .automatic
        adapterEnabled = try container.decodeIfPresent(Bool.self, forKey: .adapterEnabled) ?? true
        heatPaused = try container.decodeIfPresent(Bool.self, forKey: .heatPaused) ?? false
        holdLevel = try container.decodeIfPresent(Int.self, forKey: .holdLevel)
        isSailing = try container.decodeIfPresent(Bool.self, forKey: .isSailing) ?? false
    }
}

/// What the battery is doing and why, for status lines and logs.
nonisolated enum ChargeActivity: Codable, Equatable, Sendable {
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
    case discharging(to: Int)
    case heatPaused
    case toppingUp
    case calibrating(CalibrationPhase)

    var summary: String {
        switch self {
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
        case .discharging(let target): "discharging to \(target)%"
        case .heatPaused: "too warm, charging paused"
        case .toppingUp: "topping up to 100%"
        case .calibrating(.draining): "calibrating, draining to \(ChargePolicy.calibrationFloor)%"
        case .calibrating(.charging): "calibrating, charging to 100%"
        case .calibrating(.holding): "calibrating, resting at 100%"
        }
    }

    /// True while the battery, not the charger, powers the Mac on purpose.
    var isDraining: Bool {
        switch self {
        case .sailing, .aboveLimit, .discharging, .heatPaused, .calibrating(.draining): true
        case .holdingAbove: false
        default: false
        }
    }
}
