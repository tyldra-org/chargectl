import AppIntents
import Foundation

// Shortcuts actions. They run in the app and talk to the helper, like the dashboard does; the
// widget buttons and controls will use the same actions.

/// A failure Shortcuts shows as is.
struct ChargectlIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// The helper connection for actions.
enum IntentHelper {
    static let client = DaemonClient()

    static func status() async throws -> DaemonStatus {
        do {
            return try await client.status()
        } catch {
            throw ChargectlIntentError(message: "Chargectl’s helper isn’t running. Open Chargectl to install it.")
        }
    }

    /// Changes the helper's settings from what it has now.
    static func update(_ change: (inout ChargeSettings) -> Void) async throws -> ChargeSettings {
        var settings = try await status().settings
        change(&settings)
        settings = settings.normalized()
        do {
            try await client.update(settings)
        } catch {
            throw ChargectlIntentError(message: error.localizedDescription)
        }
        return settings
    }

    static func perform(_ command: DaemonCommand) async throws {
        _ = try await status()
        do {
            try await client.perform(command)
        } catch {
            throw ChargectlIntentError(message: error.localizedDescription)
        }
    }
}

struct SetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Charge Limit"
    static let description = IntentDescription("Sets the charge Chargectl stops charging at, from 20% to 100%.")

    @Parameter(title: "Limit", inclusiveRange: (20, 100))
    var limit: Int

    init() {}

    init(limit: Int) {
        self.limit = limit
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Set the charge limit to \(\.$limit)%")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = try await IntentHelper.update { $0.limit = limit }
        return .result(dialog: "Charge limit set to \(settings.limit)%.")
    }
}

struct SetChargeControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Charge Control On or Off"
    static let description = IntentDescription(
        "Off hands charging back to macOS until you turn charge control on again.")

    @Parameter(title: "Charge control", default: true)
    var isOn: Bool

    init() {}

    init(isOn: Bool) {
        self.isOn = isOn
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Turn charge control \(\.$isOn)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = try await IntentHelper.update { $0.isEnabled = isOn }
        return .result(
            dialog: settings.isEnabled ? "Charge control is on at \(settings.limit)%." : "Charge control is off.")
    }
}

struct TopUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Top Up"
    static let description = IntentDescription("Charges to 100% once, then goes back to the limit.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentHelper.perform(.topUp)
        return .result(dialog: "Topping up to 100%.")
    }
}

struct DischargeIntent: AppIntent {
    static let title: LocalizedStringResource = "Discharge to the Limit"
    static let description = IntentDescription("Runs the Mac on its battery until the charge is down to the limit.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let limit = try await IntentHelper.status().settings.limit
        try await IntentHelper.perform(.discharge)
        return .result(dialog: "Discharging to \(limit)%.")
    }
}

struct StopJobIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Top Up, Discharge or Full Charge"
    static let description = IntentDescription("Stops what Chargectl is doing and goes back to the limit.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentHelper.perform(.stop)
        return .result(dialog: "Back to the limit.")
    }
}

struct ChargeFullByIntent: AppIntent {
    static let title: LocalizedStringResource = "Charge to Full by a Time"
    static let description = IntentDescription(
        "Charges to 100% just in time for the time you choose, then goes back to the limit.")

    @Parameter(title: "Time", kind: .time)
    var time: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Charge to full by \(\.$time)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard let schedule = FullBySchedule.once(hour: parts.hour ?? 8, minute: parts.minute ?? 0, after: .now) else {
            throw ChargectlIntentError(message: "That time could not be scheduled.")
        }
        _ = try await IntentHelper.update { $0.fullBy = schedule }
        let when = schedule.once?.formatted(.dateTime.weekday(.wide).hour().minute()) ?? ""
        return .result(dialog: "Full by \(when).")
    }
}

struct TurnOffFullByIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off Full By"
    static let description = IntentDescription("Removes the Full by schedule.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await IntentHelper.update { $0.fullBy = nil }
        return .result(dialog: "Full by is off.")
    }
}

struct SkipNextFullByIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip the Next Full Charge"
    static let description = IntentDescription("Skips the next Full by time; the ones after it stay.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentHelper.perform(.skipFullBy)
        return .result(dialog: "Skipped the next full charge.")
    }
}

/// Control Center's charge control toggle.
struct SetChargeControlValueIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Charge Control"
    static let isDiscoverable = false

    @Parameter(title: "On")
    var value: Bool

    func perform() async throws -> some IntentResult {
        _ = try await IntentHelper.update { $0.isEnabled = value }
        return .result()
    }
}

/// Control Center's Full by toggle: on sets weekdays at 8:00 unless a time is already set.
struct SetFullByValueIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Full By"
    static let isDiscoverable = false

    @Parameter(title: "On")
    var value: Bool

    func perform() async throws -> some IntentResult {
        _ = try await IntentHelper.update { settings in
            if value {
                if settings.fullBy == nil {
                    settings.fullBy = FullBySchedule(hour: 8, minute: 0, weekdays: FullBySchedule.weekdaysOnly)
                }
            } else {
                settings.fullBy = nil
            }
        }
        return .result()
    }
}

struct GetBatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Charge"
    static let description = IntentDescription("The battery’s charge in percent, and what Chargectl is doing.")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let battery = await MainActor.run(body: { try? BatteryReader(smc: try? SMC()).read() }) else {
            throw ChargectlIntentError(message: "The battery could not be read.")
        }
        let activity = (try? await IntentHelper.client.status())?.activity.summary
        return .result(
            value: battery.percent,
            dialog: "\(battery.percent)%\(activity.map { ", \($0)" } ?? "").")
    }
}
