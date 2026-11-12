import AppIntents
import SwiftUI
import WidgetKit

// Chargectl's widgets and Control Center controls. The extension is sandboxed; it reads the
// battery itself and asks the helper over XPC (see ChargectlWidgets.entitlements).

@main
struct ChargectlWidgets: WidgetBundle {
    var body: some Widget {
        ChargeWidget()
        PowerWidget()
        HealthWidget()
        TodayWidget()
        FullByWidget()
        ControlsWidget()
        RingWidget()
        TimeLeftWidget()
        ChargeControlToggle()
        TopUpControl()
        DischargeControl()
        FullByControl()
    }
}

// MARK: - Timeline

/// Reads everything a widget shows: the battery from IOKit, the rest from the helper.
enum WidgetLoader {
    static func load(now: Date = .now) async -> BatteryEntry {
        let battery = try? BatteryReader(smc: try? SMC()).read(now: now)
        let client = DaemonClient()
        guard let status = try? await client.status() else {
            // The helper did not answer. While it restarts for an update or after a macOS update,
            // show what it last said instead of asking to install it; only a silence longer than
            // HelperSnapshot.lifetime means it is gone.
            var entry = BatteryEntry(date: now, battery: battery)
            if let last = HelperSnapshot.load(now: now) {
                entry.status = last.status
                entry.history = last.history
                entry.daily = last.daily
                entry.events = last.events
                entry.isStale = true
            }
            return entry
        }
        var entry = BatteryEntry(date: now, battery: battery, status: status)
        entry.history = (try? await client.history()) ?? []
        if DaemonIdentity.hasDailyHistory(status.version) { entry.daily = (try? await client.daily()) ?? [] }
        entry.events = Array(
            ((try? await client.logs()) ?? []).filter { $0.source == .chargectl || $0.level == .warning }.suffix(3)
                .reversed())
        HelperSnapshot(
            date: now, status: status, history: entry.history, daily: entry.daily, events: entry.events
        ).save()
        return entry
    }
}

/// What the helper last said, kept in the widgets' own container so a short gap, such as the
/// helper restarting into an update, does not show "needs the helper". Uninstalling deletes the
/// container.
nonisolated struct HelperSnapshot: Codable, Sendable {
    /// How long the last answer stands in for a helper that does not answer.
    static let lifetime: TimeInterval = 15 * 60

    var date: Date
    var status: DaemonStatus
    var history: [HistorySample]
    var daily: [DailySample]
    var events: [LogEntry]

    private static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("helper-snapshot.json")
    }

    func save() {
        guard let url = Self.url else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Coding.encode(self).write(to: url, options: .atomic)
    }

    static func load(now: Date) -> HelperSnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
            let snapshot = try? Coding.decode(HelperSnapshot.self, from: data),
            now.timeIntervalSince(snapshot.date) < lifetime
        else { return nil }
        return snapshot
    }
}

nonisolated struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (BatteryEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(await WidgetLoader.load()) }
    }

    /// One entry, read again in five minutes, or in one while the helper is not answering; the
    /// app asks for a reload whenever something changes.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<BatteryEntry>) -> Void) {
        Task {
            let entry = await WidgetLoader.load()
            let wait: TimeInterval = entry.status == nil || entry.isStale ? 60 : 5 * 60
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(wait))))
        }
    }
}

/// A kind's content with Chargectl's card behind it, which macOS removes in the tinted and
/// one-colour modes.
struct KindView: View {
    let kind: ChargectlWidgetKind
    let entry: BatteryEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ChargectlWidgetContent(kind: kind, family: family, entry: entry)
            .containerBackground(for: .widget) { WidgetPalette(scheme: scheme).background }
            .widgetURL(kind.url)
    }
}

private func configuration(_ kind: ChargectlWidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.kind, provider: BatteryProvider()) { entry in
        KindView(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.title)
    .description(kind.summary)
    .supportedFamilies(kind.families)
}

struct ChargeWidget: Widget {
    var body: some WidgetConfiguration { configuration(.charge) }
}

struct PowerWidget: Widget {
    var body: some WidgetConfiguration { configuration(.power) }
}

struct HealthWidget: Widget {
    var body: some WidgetConfiguration { configuration(.health) }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration { configuration(.today) }
}

struct FullByWidget: Widget {
    var body: some WidgetConfiguration { configuration(.fullBy) }
}

struct ControlsWidget: Widget {
    var body: some WidgetConfiguration { configuration(.controls) }
}

struct RingWidget: Widget {
    var body: some WidgetConfiguration { configuration(.ring) }
}

struct TimeLeftWidget: Widget {
    var body: some WidgetConfiguration { configuration(.timeLeft) }
}

// MARK: - Controls

nonisolated struct ChargeControlState: Sendable {
    var isOn: Bool
    var limit: Int
}

nonisolated struct ChargeControlProvider: ControlValueProvider {
    var previewValue: ChargeControlState { ChargeControlState(isOn: true, limit: 80) }

    func currentValue() async throws -> ChargeControlState {
        let settings = try await IntentHelper.status().settings
        return ChargeControlState(isOn: settings.isEnabled, limit: settings.limit)
    }
}

struct ChargeControlToggle: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tyldra.chargectl.control.charge", provider: ChargeControlProvider()) {
            state in
            ControlWidgetToggle(isOn: state.isOn, action: SetChargeControlValueIntent()) {
                Label("Charge Limit", systemImage: "battery.75percent")
            } valueLabel: { isOn in
                Label(isOn ? "\(state.limit)%" : "Off", systemImage: isOn ? "battery.75percent" : "battery.100percent")
            }
        }
        .displayName("Charge Limit")
        .description("Turns charge control on or off.")
    }
}

struct TopUpControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tyldra.chargectl.control.topup") {
            ControlWidgetButton(action: TopUpIntent()) {
                Label("Top Up", systemImage: "battery.100percent.bolt")
            }
        }
        .displayName("Top Up")
        .description("Charges to 100% once, then back to the limit.")
    }
}

struct DischargeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tyldra.chargectl.control.discharge") {
            ControlWidgetButton(action: DischargeIntent()) {
                Label("Discharge", systemImage: "battery.25percent")
            }
        }
        .displayName("Discharge")
        .description("Runs on the battery down to the limit.")
    }
}

nonisolated struct FullByState: Sendable {
    var isOn: Bool
    var next: Date?
}

nonisolated struct FullByProvider: ControlValueProvider {
    var previewValue: FullByState { FullByState(isOn: true, next: nil) }

    func currentValue() async throws -> FullByState {
        let status = try await IntentHelper.status()
        let schedule = status.settings.fullBy
        return FullByState(
            isOn: schedule != nil, next: schedule?.nextDeadline(after: .now, skipping: status.skippedFullBy))
    }
}

struct FullByControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tyldra.chargectl.control.fullby", provider: FullByProvider()) { state in
            ControlWidgetToggle(isOn: state.isOn, action: SetFullByValueIntent()) {
                Label("Full By", systemImage: "clock")
            } valueLabel: { isOn in
                Label(
                    isOn
                        ? (state.next.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) } ?? "On")
                        : "Off",
                    systemImage: "clock")
            }
        }
        .displayName("Full By")
        .description("Charges to 100% by a set time; on sets weekdays at 8:00 unless a time is set.")
    }
}
