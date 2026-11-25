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
    /// Months between automatic calibrations.
    static let calibrationMonthsRange = 2...3
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
    /// While wall power is cut on purpose, keep it cut through sleep instead of reconnecting.
    var holdAsleep = false
    var magSafeLED = MagSafeLEDMode.system
    /// A full charge by a set time, or nil.
    var fullBy: FullBySchedule?
    /// Run Calibrate every this many months, or nil for never: the first time the Mac is on the
    /// charger after that long since the last calibration, or since this was turned on.
    var calibrateEveryMonths: Int?
    /// Hold what the user usually needs off the charger, up to limit (SmartLimit).
    var smartLimit = false
    /// A calendar trip starts then: the smart limit holds the full limit until it does. Set by the
    /// app from the user's calendar.
    var tripUntil: Date?

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
        holdAsleep = try container.decodeIfPresent(Bool.self, forKey: .holdAsleep) ?? defaults.holdAsleep
        magSafeLED =
            try container.decodeIfPresent(MagSafeLEDMode.self, forKey: .magSafeLED) ?? defaults.magSafeLED
        fullBy = try container.decodeIfPresent(FullBySchedule.self, forKey: .fullBy)
        calibrateEveryMonths = try container.decodeIfPresent(Int.self, forKey: .calibrateEveryMonths)
        smartLimit = try container.decodeIfPresent(Bool.self, forKey: .smartLimit) ?? defaults.smartLimit
        tripUntil = try container.decodeIfPresent(Date.self, forKey: .tripUntil)
        self = normalized()
    }

    /// The same settings with every value inside its allowed range.
    func normalized() -> ChargeSettings {
        var copy = self
        copy.limit = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        copy.sailing = min(max(sailing, Self.sailingRange.lowerBound), Self.sailingRange.upperBound)
        copy.heatThreshold = min(
            max(heatThreshold, Self.heatThresholdRange.lowerBound), Self.heatThresholdRange.upperBound)
        copy.calibrateEveryMonths = calibrateEveryMonths.map {
            min(max($0, Self.calibrationMonthsRange.lowerBound), Self.calibrationMonthsRange.upperBound)
        }
        if var schedule = fullBy {
            schedule.hour = min(max(schedule.hour, 0), 23)
            schedule.minute = min(max(schedule.minute, 0), 59)
            schedule.weekdays = schedule.weekdays.filter { (1...7).contains($0) }
            copy.fullBy = schedule.isRepeating || schedule.once != nil ? schedule : nil
        }
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
            "discharge asleep \(holdAsleep ? "on" : "off")",
            "LED \(magSafeLED.title)",
            "full by \(fullBy?.summary ?? "off")",
            "auto calibration \(calibrateEveryMonths.map { "every \($0) months" } ?? "off")",
            "smart limit \(smartLimit ? "on" : "off")",
        ].joined(separator: " · ")
    }
}
