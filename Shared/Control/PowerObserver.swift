import Foundation

/// What the hardware is actually doing, read each tick, independent of what Chargectl intends.
nonisolated struct ObservedPower: Equatable, Sendable {
    nonisolated enum Flow: Equatable, Sendable {
        case charging
        case discharging
        case idle
    }

    var percent: Int
    var chargerAttached: Bool
    /// Whether the charger's power reaches the Mac (CHIE); nil when this Mac has no such switch.
    var wallPowerConnected: Bool?
    /// A; positive while charging.
    var current: Double
    /// macOS's own charge limit, nil when it is off or unknown.
    var macOSLimit: Int?

    static let flowThreshold = 0.1

    var flow: Flow {
        if current > Self.flowThreshold { return .charging }
        if current < -Self.flowThreshold { return .discharging }
        return .idle
    }
}

/// Turns successive readings into log lines about real changes. A battery flow change is only
/// reported once it has lasted two readings, so one-second blips are not logged.
nonisolated struct PowerObserver: Sendable {
    private var reported: ObservedPower?
    private var pendingFlow: ObservedPower.Flow?

    mutating func changes(_ now: ObservedPower) -> [String] {
        guard let last = reported else {
            reported = now
            return [describeCharger(now), describeLimit(now), describeFlow(now)].compactMap { $0 }
        }
        var lines: [String] = []
        if now.chargerAttached != last.chargerAttached {
            lines.append(now.chargerAttached ? "charger plugged in" : "charger unplugged")
        }
        if let connected = now.wallPowerConnected, connected != last.wallPowerConnected {
            lines.append(connected ? "wall power reconnected" : "wall power cut; the battery runs the Mac")
        }
        if now.macOSLimit != last.macOSLimit, let line = describeLimit(now) { lines.append(line) }
        var flow = last.flow
        if now.flow != last.flow {
            if pendingFlow == now.flow {
                flow = now.flow
                pendingFlow = nil
                if let line = describeFlow(now) { lines.append(line) }
            } else {
                pendingFlow = now.flow
            }
        } else {
            pendingFlow = nil
        }
        var updated = now
        // Keep the last reported flow until a new one is confirmed.
        if flow != now.flow { updated.current = last.current }
        reported = updated
        return lines
    }

    private func describeCharger(_ power: ObservedPower) -> String? {
        power.chargerAttached ? "charger plugged in" : "on battery, no charger"
    }

    private func describeLimit(_ power: ObservedPower) -> String? {
        power.macOSLimit.map { "macOS charge limit is \($0)%" } ?? "macOS charge limit is off"
    }

    private func describeFlow(_ power: ObservedPower) -> String? {
        let amps = String(format: "%.2f A", abs(power.current))
        switch power.flow {
        case .charging: return "battery charging at \(amps)"
        case .discharging:
            return power.chargerAttached
                ? "battery discharging at \(amps) with the charger plugged in" : "battery discharging at \(amps)"
        case .idle: return power.chargerAttached ? "battery idle; the charger runs the Mac" : "battery idle"
        }
    }
}

extension ChargeSettings {
    /// Each setting that differs from old, as "name old → new".
    func changes(from old: ChargeSettings) -> [String] {
        func onOff(_ value: Bool) -> String { value ? "on" : "off" }
        var lines: [String] = []
        if isEnabled != old.isEnabled { lines.append("charge control \(onOff(old.isEnabled)) → \(onOff(isEnabled))") }
        if limit != old.limit { lines.append("limit \(old.limit)% → \(limit)%") }
        if sailing != old.sailing { lines.append("sailing \(old.sailing)% → \(sailing)%") }
        if autoDischarge != old.autoDischarge {
            lines.append("automatic discharge \(onOff(old.autoDischarge)) → \(onOff(autoDischarge))")
        }
        if heatProtection != old.heatProtection {
            lines.append("heat protection \(onOff(old.heatProtection)) → \(onOff(heatProtection))")
        }
        if heatThreshold != old.heatThreshold {
            lines.append("heat threshold \(Int(old.heatThreshold)) °C → \(Int(heatThreshold)) °C")
        }
        if clamshell != old.clamshell { lines.append("clamshell \(onOff(old.clamshell)) → \(onOff(clamshell))") }
        if holdAsleep != old.holdAsleep { lines.append("hold asleep \(onOff(old.holdAsleep)) → \(onOff(holdAsleep))") }
        if magSafeLED != old.magSafeLED { lines.append("MagSafe LED \(old.magSafeLED.title) → \(magSafeLED.title)") }
        return lines
    }
}
