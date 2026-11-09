import Foundation

/// Notices when cutting wall power has no effect: Chargectl has the charger's power switched off,
/// yet the battery keeps charging. A macOS or firmware update can change the SMC key that does it.
nonisolated struct ControlCheck: Sendable {
    /// Consecutive readings (5 s apart) before the problem is reported.
    static let readings = 6
    static let message =
        "Cutting wall power has no effect: the battery keeps charging. A macOS or firmware update may have changed how charging is controlled."

    private var mismatches = 0
    private(set) var problem: String?

    /// - Parameter wallPowerCut: what the switch reads back, not what was asked for.
    mutating func observe(wallPowerCut: Bool, pluggedIn: Bool, current: Double) {
        guard pluggedIn, wallPowerCut else {
            mismatches = 0
            return
        }
        if current > ObservedPower.flowThreshold {
            mismatches += 1
            if mismatches >= Self.readings { problem = Self.message }
        } else {
            mismatches = 0
            // Seen working: the battery runs the Mac while the switch is off.
            if current < -ObservedPower.flowThreshold { problem = nil }
        }
    }
}

/// Notices a charger too weak to run the Mac: plugged in, power not cut on purpose, and yet the
/// battery runs down for a minute or more.
nonisolated struct ChargerCheck: Sendable {
    static let duration: TimeInterval = 60
    /// A; less than this does not count as running down.
    static let drain = 0.1

    private var since: Date?
    private(set) var isWeak = false

    /// - Parameter drainsOnPurpose: Chargectl or macOS is running the Mac on battery on purpose.
    mutating func observe(_ battery: BatterySnapshot, wallPowerCut: Bool, drainsOnPurpose: Bool, now: Date) {
        guard battery.isPluggedIn, !wallPowerCut, !drainsOnPurpose, battery.current < -Self.drain else {
            since = nil
            isWeak = false
            return
        }
        let start = since ?? now
        since = start
        isWeak = now.timeIntervalSince(start) >= Self.duration
    }
}
