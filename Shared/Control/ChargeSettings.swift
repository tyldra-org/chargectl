import Foundation

nonisolated enum MagSafeLEDMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case off

    var id: Self { self }
    var title: String {
        switch self {
        case .system: "system"
        case .off: "off"
        }
    }
}

/// What the user asked the daemon to enforce. Missing keys decode to defaults so
/// older files keep working.
nonisolated struct ChargeSettings: Codable, Equatable, Sendable {
    static let limitRange = 20...100
    static let sailingRange = 0...20
    /// °C
    static let heatThresholdRange = 25.0...45.0

    var isEnabled = true
    var limit = 80
    var sailing = 5
    /// Plugged in above the limit: run on battery down to the limit. Off holds the charge where it was.
    var autoDischarge = false
    var heatProtection = false
    /// °C
    var heatThreshold = 35.0
    var clamshell = false
    var holdAsleep = false
    var magSafeLED = MagSafeLEDMode.system

    /// Charging resumes at or below this percentage.
    var lowerBound: Int { max(limit - sailing, Self.limitRange.lowerBound) }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ChargeSettings()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? defaults.limit
        sailing = try container.decodeIfPresent(Int.self, forKey: .sailing) ?? defaults.sailing
        autoDischarge =
            try container.decodeIfPresent(Bool.self, forKey: .autoDischarge) ?? defaults.autoDischarge
        heatProtection =
            try container.decodeIfPresent(Bool.self, forKey: .heatProtection) ?? defaults.heatProtection
        heatThreshold =
            try container.decodeIfPresent(Double.self, forKey: .heatThreshold) ?? defaults.heatThreshold
        clamshell = try container.decodeIfPresent(Bool.self, forKey: .clamshell) ?? defaults.clamshell
        holdAsleep = try container.decodeIfPresent(Bool.self, forKey: .holdAsleep) ?? defaults.holdAsleep
        magSafeLED =
            try container.decodeIfPresent(MagSafeLEDMode.self, forKey: .magSafeLED) ?? defaults.magSafeLED
        self = normalized()
    }

    /// The same settings with every value inside its allowed range.
    func normalized() -> ChargeSettings {
        var copy = self
        copy.limit = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        copy.sailing = min(max(sailing, Self.sailingRange.lowerBound), Self.sailingRange.upperBound)
        copy.heatThreshold = min(
            max(heatThreshold, Self.heatThresholdRange.lowerBound), Self.heatThresholdRange.upperBound)
        return copy
    }

    /// One line for the log.
    var summary: String {
        [
            "control \(isEnabled ? "on" : "off")",
            "limit \(limit)%",
            "sailing \(sailing)%",
            "auto discharge \(autoDischarge ? "on" : "off")",
            "heat \(heatProtection ? "\(Int(heatThreshold)) °C" : "off")",
            "clamshell \(clamshell ? "on" : "off")",
            "hold asleep \(holdAsleep ? "on" : "off")",
            "LED \(magSafeLED.title)",
        ].joined(separator: " · ")
    }
}
