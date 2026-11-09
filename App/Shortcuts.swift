import AppIntents

/// The actions Shortcuts and Siri offer without setting anything up. App only: the widget
/// extension shares the actions but not this list.
struct ChargectlShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBatteryStatusIntent(), phrases: ["Check the battery in \(.applicationName)"],
            shortTitle: "Battery Charge", systemImageName: "battery.75percent")
        AppShortcut(
            intent: TopUpIntent(),
            phrases: ["Top up with \(.applicationName)", "Charge to full with \(.applicationName)"],
            shortTitle: "Top Up", systemImageName: "battery.100percent.bolt")
        AppShortcut(
            intent: SetChargeLimitIntent(), phrases: ["Set the \(.applicationName) limit"], shortTitle: "Set Limit",
            systemImageName: "gauge.with.dots.needle.50percent")
        AppShortcut(
            intent: ChargeFullByIntent(), phrases: ["Charge to full by a time with \(.applicationName)"],
            shortTitle: "Full By", systemImageName: "clock")
    }
}
