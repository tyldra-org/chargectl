/// SMC keys this app reads or writes on Apple silicon.
nonisolated enum SMCKey {
    /// Battery temperature in °C (flt).
    static let batteryTemperature = "TB0T"
    /// Whole-system power draw in W (flt).
    static let systemPower = "PSTR"
    /// Power entering from the charger in W (flt).
    static let wallPower = "PDTR"
    /// Charger input voltage in V (flt), live.
    static let chargerVoltage = "VD0R"
    /// Charger input current in A (flt), live.
    static let chargerCurrent = "ID0R"
    /// Battery current in mA (si16), live; positive while charging.
    static let batteryCurrent = "B0AC"
    /// Battery voltage in mV (ui16), live.
    static let batteryVoltage = "B0AV"
    /// Minutes to full (ui16); 65535 when not charging.
    static let timeToFull = "B0TF"
    /// Minutes to empty (ui16); 65535 when not discharging.
    static let timeToEmpty = "B0TE"
    /// Charger attached (si8, above 0 when plugged in). Unlike the registry's ExternalConnected,
    /// it stays set while wall power is cut through the adapter key.
    static let chargerAttached = "AC-W"
    /// MagSafe LED state (ui8): 0 lets macOS decide, 1 turns it off.
    static let magSafeLED = "ACLC"
}

/// The keys that connect or disconnect wall power, newest firmware first, with the
/// byte that disconnects it. Writing 0 reconnects. Charge-inhibit keys (CH0B, CH0C,
/// CHTE, bfF0) are gated behind a private entitlement on current firmware.
nonisolated enum AdapterKey {
    static let candidates: [(key: String, disconnected: UInt8)] = [
        ("CHIE", 0x08),
        ("CH0I", 0x01),
        ("CH0J", 0x01),
    ]
}
