import AppIntents
import SwiftUI
import WidgetKit

/// The widgets in the gallery, each answering one question.
enum ChargectlWidgetKind: String, CaseIterable {
    case charge
    case power
    case health
    case today
    case fullBy
    case controls
    case ring
    case timeLeft

    var kind: String { "com.tyldra.chargectl.\(rawValue)" }

    var title: String {
        switch self {
        case .charge: "Charge"
        case .power: "Power"
        case .health: "Health"
        case .today: "Today"
        case .fullBy: "Full By"
        case .controls: "Controls"
        case .ring: "Ring"
        case .timeLeft: "Time Left"
        }
    }

    var summary: String {
        switch self {
        case .charge: "How full the battery is and what Chargectl is doing."
        case .power: "Where the watts go: into or out of the battery, the charger and the Mac."
        case .health: "Battery health and cycles, and how they changed over three months."
        case .today: "How the battery spent today: at high charge, on the charger, the lowest charge."
        case .fullBy: "The next full charge by a set time, and when charging starts."
        case .controls: "Change the limit, Top Up or Discharge without opening Chargectl."
        case .ring: "Just the charge and the limit."
        case .timeLeft: "How long until the charge reaches the limit, full or empty."
        }
    }

    var families: [WidgetFamily] {
        switch self {
        case .charge, .fullBy:
            [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .systemExtraLargePortrait]
        case .ring: [.systemSmall]
        default: [.systemSmall, .systemMedium]
        }
    }

    /// The dashboard page a tap opens.
    var url: URL {
        let page =
            switch self {
            case .health, .today: "history"
            case .fullBy, .controls: "control"
            default: "overview"
            }
        return URL(string: "chargectl://dashboard/\(page)")!
    }
}

/// One widget's content for a size, without the container background, so the app can draw it too.
struct ChargectlWidgetContent: View {
    let kind: ChargectlWidgetKind
    let family: WidgetFamily
    let entry: BatteryEntry

    var body: some View {
        let facts = WidgetFacts(entry: entry)
        Group {
            switch kind {
            case .charge: ChargeKind(facts: facts, family: family)
            case .power: PowerKind(facts: facts, family: family)
            case .health: HealthKind(facts: facts, family: family)
            case .today: TodayKind(facts: facts, family: family)
            case .fullBy: FullByKind(facts: facts, family: family)
            case .controls: ControlsKind(facts: facts, family: family)
            case .ring: RingKind(facts: facts)
            case .timeLeft: TimeLeftKind(facts: facts, family: family)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fontDesign(.default)
        .monospacedDigit()
    }
}

// MARK: - Shared pieces

private struct Divided<Left: View, Right: View>: View {
    var leftWidth: CGFloat = 132
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            left.frame(width: leftWidth, alignment: .leading).frame(maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(WidgetPalette(scheme: scheme).line).frame(width: 1)
            right.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ColumnHeader: View {
    let title: String
    var note: String?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let note { Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
        }
        .lineLimit(1)
    }
}

/// What a widget shows when it needs the helper, with the way to install it.
private struct NeedsHelper: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetLabel(symbol: symbol, title: title)
            Spacer(minLength: 0)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
            InstallHelperLink()
        }
    }
}

private struct InstallHelperLink: View {
    var body: some View {
        Link(destination: URL(string: "chargectl://dashboard/overview")!) {
            Label("Install Helper", systemImage: "arrow.down.to.line")
        }
        .buttonStyle(WidgetPillStyle(filled: true))
    }
}

/// Top Up and Discharge, or Stop while a job runs.
private struct JobButtons: View {
    let facts: WidgetFacts
    /// Text only, for narrow columns.
    var compact = false

    var body: some View {
        if !facts.hasHelper {
            InstallHelperLink()
        } else if facts.status?.mode != .automatic, let mode = facts.status?.mode {
            HStack(spacing: 6) {
                Button(intent: StopJobIntent()) {
                    Label(
                        facts.deadline.map { "Full by \(WidgetFacts.time($0))" } ?? mode.title.capitalized,
                        systemImage: "stop.fill")
                }
                .buttonStyle(WidgetPillStyle(filled: true))
            }
        } else {
            let limit = facts.limit ?? 80
            HStack(spacing: 6) {
                if compact {
                    Button(intent: TopUpIntent()) { Text("Top Up") }
                        .buttonStyle(WidgetPillStyle(expands: true))
                    Button(intent: DischargeIntent()) { Text("Discharge") }
                        .buttonStyle(WidgetPillStyle(dimmed: facts.percent <= limit, expands: true))
                        .disabled(facts.percent <= limit)
                } else {
                    Button(intent: TopUpIntent()) { Label("Top Up", systemImage: "arrow.up.to.line") }
                        .buttonStyle(WidgetPillStyle())
                    Button(intent: DischargeIntent()) { Label("Discharge", systemImage: "arrow.down.to.line") }
                        .buttonStyle(WidgetPillStyle(dimmed: facts.percent <= limit))
                        .disabled(facts.percent <= limit)
                }
            }
        }
    }
}

private func chargeFigures(_ facts: WidgetFacts, details: Bool, count: Int = 3) -> FigureRow {
    let wall = facts.wallWatts
    let all = [
        WidgetFigure(
            title: "Charger", value: wall.map { WidgetFacts.watts($0) } ?? "\u{2014}", unit: wall == nil ? "" : "W",
            detail: details ? (facts.battery?.adapterWatts.map { "\($0) W adapter" } ?? "Not connected") : nil,
            size: details ? 17 : 15),
        WidgetFigure(
            title: "Mac", value: WidgetFacts.watts(facts.macWatts), unit: "W",
            detail: details
                ? (wall.map { "\(Int((facts.macWatts / max($0, 0.1) * 100).rounded()))% of power in" }
                    ?? "From the battery") : nil,
            size: details ? 17 : 15),
        WidgetFigure(
            title: "Battery", value: WidgetFacts.watts(facts.batteryWatts, signed: true), unit: "W",
            detail: details ? facts.batteryFlow : nil, size: details ? 17 : 15),
        WidgetFigure(
            title: "Temp.", value: facts.battery?.temperature.map { String(format: "%.1f", $0) } ?? "\u{2014}",
            unit: "°C",
            detail: details ? ((facts.battery?.temperature ?? 0) >= 35 ? "Warm" : "Normal") : nil,
            size: details ? 17 : 15),
    ]
    return FigureRow(figures: Array(all.prefix(count)))
}

private func percentValue(_ facts: WidgetFacts, size: CGFloat) -> BigValue {
    BigValue(parts: [("\(facts.percent)", "%")], size: size)
}

private func limitNote(_ facts: WidgetFacts) -> String? {
    if let deadline = facts.deadline { return "Full by \(WidgetFacts.time(deadline))" }
    return facts.limit.map { "Limit \($0)%" }
}

// MARK: - Charge

private struct ChargeKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemMedium:
            Divided(leftWidth: 142) {
                small
            } right: {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnHeader(title: "Last 6 hours", note: limitNote(facts))
                    ChargeArea(samples: facts.entry.history, now: facts.entry.date, limit: facts.limit).frame(
                        height: 66)
                    Spacer(minLength: 0)
                    chargeFigures(facts, details: false)
                }
            }
        case .systemLarge: large
        case .systemExtraLarge: extraLarge
        case .systemExtraLargePortrait: portrait
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WidgetRing(facts: facts).frame(width: 30, height: 30)
                Spacer()
                if let note = limitNote(facts) { Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
            percentValue(facts, size: 46)
            StatusLine(facts: facts).padding(.top, 8)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                percentValue(facts, size: 60)
                Spacer()
                WidgetRing(facts: facts, lineWidth: 4).frame(width: 38, height: 38)
            }
            StatusLine(facts: facts, size: 13).padding(.top, 10)
            WidgetMeter(
                percent: facts.percent, limit: facts.trackEnd, lowerBound: facts.target == nil ? facts.lowerBound : nil,
                label: limitNote(facts), showsScale: true
            )
            .padding(.top, 18)
            ChargeArea(samples: facts.entry.history, now: facts.entry.date, limit: facts.limit)
                .frame(height: 70)
                .padding(.top, 12)
            chargeFigures(facts, details: true).padding(.top, 10)
            Spacer(minLength: 8)
            JobButtons(facts: facts)
        }
    }

    private var rules: [(String, String)] {
        guard let settings = facts.settings else {
            return [("macOS limit", "On"), ("Health", healthText), ("Cycles", cyclesText)]
        }
        return [
            ("Sails", settings.sailing == 0 ? "Off" : "\(settings.lowerBound)–\(settings.limit)%"),
            ("Above the limit", settings.autoDischarge ? "Discharge" : "Hold"),
            ("Health", healthText), ("Cycles", cyclesText),
        ]
    }

    private var healthText: String { facts.health.map { String(format: "%.1f%%", $0 * 100) } ?? "\u{2014}" }
    private var cyclesText: String { facts.battery.map { "\($0.cycleCount)" } ?? "\u{2014}" }

    private var extraLarge: some View {
        Divided(leftWidth: 300) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    percentValue(facts, size: 72)
                    Spacer()
                    WidgetRing(facts: facts, lineWidth: 4.2).frame(width: 40, height: 40)
                }
                StatusLine(facts: facts, size: 13.5).padding(.top, 12)
                WidgetMeter(
                    percent: facts.percent, limit: facts.trackEnd,
                    lowerBound: facts.target == nil ? facts.lowerBound : nil, label: limitNote(facts), showsScale: true
                )
                .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        WidgetRow(title: rule.0, value: rule.1, first: index == 0)
                    }
                }
                .padding(.top, 14)
                Spacer(minLength: 8)
                JobButtons(facts: facts)
            }
        } right: {
            VStack(alignment: .leading, spacing: 6) {
                ColumnHeader(title: "Charge, last 24 hours", note: facts.limit.map { "Limit \($0)%" })
                ChargeArea(
                    samples: facts.entry.history, now: facts.entry.date, hours: 24, limit: facts.limit, showsGrid: true
                )
                .frame(height: 120)
                chargeFigures(facts, details: true, count: 4).padding(.top, 8)
                ColumnHeader(title: "Recent").padding(.top, 10)
                RecentRows(events: Array(facts.entry.events.prefix(3)))
            }
        }
    }

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Chargectl", systemImage: "battery.75percent")
                    .labelStyle(TightWidgetLabelStyle())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Health \(healthText) · \(cyclesText) cycles").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            WidgetRing(facts: facts, lineWidth: 7, showsGlyph: false) {
                VStack(spacing: 2) {
                    percentValue(facts, size: 42)
                    Text(limitNote(facts) ?? "macOS limit").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 136, height: 136)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            StatusLine(facts: facts, size: 14).frame(maxWidth: .infinity).padding(.top, 14)
            WidgetMeter(
                percent: facts.percent, limit: facts.trackEnd, lowerBound: facts.target == nil ? facts.lowerBound : nil,
                label: limitNote(facts), showsScale: true
            )
            .padding(.top, 22)
            ColumnHeader(title: "Charge, last 24 hours", note: facts.limit.map { "Limit \($0)%" }).padding(.top, 16)
            ChargeArea(
                samples: facts.entry.history, now: facts.entry.date, hours: 24, limit: facts.limit, showsGrid: true
            )
            .frame(height: 96)
            .padding(.top, 6)
            chargeFigures(facts, details: false, count: 2).padding(.top, 12)
            FigureRow(figures: Array(chargeFiguresAll.suffix(2))).padding(.top, 8)
            ColumnHeader(title: "Recent").padding(.top, 14)
            RecentRows(events: Array(facts.entry.events.prefix(3)))
            Spacer(minLength: 8)
            JobButtons(facts: facts)
        }
    }

    private var chargeFiguresAll: [WidgetFigure] { chargeFigures(facts, details: false, count: 4).figures }
}

private struct RecentRows: View {
    let events: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                HStack(spacing: 10) {
                    Text(event.date, format: .dateTime.hour().minute())
                        .foregroundStyle(.tertiary)
                        .frame(width: 58, alignment: .leading)
                    Text(WidgetFacts.sentence(event.message) + (event.percent.map { ", \($0)%" } ?? ""))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11.5))
                .lineLimit(1)
                .padding(.vertical, 5)
            }
        }
    }
}

// MARK: - Power

private struct PowerKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if family == .systemMedium {
            Divided {
                headline
            } right: {
                split
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headline
                VStack(spacing: 0) {
                    WidgetRow(
                        title: "Charger", value: facts.wallWatts.map { "\(WidgetFacts.watts($0)) W" } ?? "\u{2014}",
                        first: true)
                    WidgetRow(title: "Mac", value: "\(WidgetFacts.watts(facts.macWatts)) W")
                }
                .padding(.top, 8)
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(symbol: "bolt", title: "Power")
            Spacer(minLength: 0)
            BigValue(
                parts: [(WidgetFacts.watts(facts.batteryWatts, signed: true), "W")], size: 34,
                color: facts.batteryWatts > 0.05 ? WidgetPalette(scheme: scheme).accent : nil)
            Text(facts.batteryFlow).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    private var split: some View {
        let palette = WidgetPalette(scheme: scheme)
        let wall = facts.wallWatts
        let charging = facts.batteryWatts > 0.05
        let total = max(facts.macWatts + max(facts.batteryWatts, 0), 0.1)
        return VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            ColumnHeader(
                title: wall == nil ? "From the battery" : "From the charger",
                note: wall.map { "\(WidgetFacts.watts($0)) W" })
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.secondary)
                        .frame(width: wall == nil ? geometry.size.width : geometry.size.width * facts.macWatts / total)
                    if wall != nil, charging { Rectangle().fill(palette.accent).widgetAccentable() }
                }
                .background(palette.track)
                .clipShape(Capsule())
            }
            .frame(height: 8)
            VStack(spacing: 0) {
                WidgetRow(
                    title: "Mac",
                    value: "\(WidgetFacts.watts(facts.macWatts)) W"
                        + (wall != nil ? " · \(Int((facts.macWatts / total * 100).rounded()))%" : ""), first: true)
                WidgetRow(
                    title: "Battery",
                    value: "\(WidgetFacts.watts(facts.batteryWatts, signed: true)) W"
                        + (wall != nil && charging ? " · \(Int((facts.batteryWatts / total * 100).rounded()))%" : ""))
            }
        }
    }
}

// MARK: - Health

private struct HealthKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily

    var body: some View {
        if family == .systemMedium {
            Divided {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetLabel(symbol: "heart.text.square", title: "Health")
                    Spacer(minLength: 0)
                    value(size: 40)
                    Text(capacity).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 5)
                }
            } right: {
                VStack(alignment: .leading, spacing: 6) {
                    if facts.healthTrend.count > 1 {
                        ColumnHeader(title: "Last 3 months", note: change)
                        TrendLine(values: facts.healthTrend, filled: true).frame(height: 58)
                    } else {
                        Text("The trend appears as the helper records one summary a day.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    FigureRow(figures: [
                        WidgetFigure(
                            title: "Cycles", value: facts.battery.map { "\($0.cycleCount)" } ?? "\u{2014}",
                            unit: facts.cyclesPerMonth.map { String(format: "%.0f a month", $0) } ?? "", size: 15),
                        WidgetFigure(
                            title: "At 90%+",
                            value: facts.highChargeHours.map { String(format: "%.1f", $0) } ?? "\u{2014}",
                            unit: facts.highChargeHours == nil ? "" : "h a day", size: 15),
                    ])
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(
                    symbol: "heart.text.square", title: "Health", note: facts.healthTrend.count > 1 ? "3 months" : nil)
                Spacer(minLength: 0)
                value(size: 38)
                if facts.healthTrend.count > 1 {
                    TrendLine(values: facts.healthTrend).frame(height: 24).padding(.top, 8)
                }
                Text(
                    [facts.battery.map { "\($0.cycleCount) cycles" }, change.map { "\($0) in 3 mo" }].compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 6)
            }
        }
    }

    private func value(size: CGFloat) -> BigValue {
        BigValue(parts: [(facts.health.map { String(format: "%.1f", $0 * 100) } ?? "\u{2014}", "%")], size: size)
    }

    private var capacity: String {
        guard let battery = facts.battery else { return "" }
        return "\(battery.fullChargeCapacity.formatted()) of \(battery.designCapacity.formatted()) mAh"
    }

    private var change: String? {
        facts.healthChange.map {
            abs($0) < 0.05 ? "unchanged" : String(format: "%@%.1f", $0 > 0 ? "+" : "\u{2212}", abs($0))
        }
    }
}

// MARK: - Today

private struct TodayKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily

    var body: some View {
        if !facts.hasHelper {
            NeedsHelper(symbol: "sun.max", title: "Today", text: "Recording the day needs the helper.")
        } else if family == .systemMedium {
            Divided {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetLabel(symbol: "sun.max", title: "Today")
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        WidgetRow(title: "At 90%+", value: highCharge, first: true)
                        WidgetRow(title: "On charger", value: plugged)
                        WidgetRow(title: "Lowest", value: facts.todayLowest.map { "\($0)%" } ?? "\u{2014}")
                        WidgetRow(
                            title: "Warmest",
                            value: facts.today?.maxTemperature.map { String(format: "%.0f °C", $0) } ?? "\u{2014}")
                    }
                }
            } right: {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnHeader(title: "Charge today", note: facts.limit.map { "Limit \($0)%" })
                    ChargeArea(
                        samples: facts.entry.history, now: facts.entry.date, hours: hoursToday, limit: facts.limit
                    )
                    .frame(height: 62)
                    DayStrip(samples: facts.entry.history, now: facts.entry.date).frame(height: 6).padding(.top, 4)
                    HStack {
                        Text("12 AM")
                        Spacer()
                        Text("now")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(symbol: "sun.max", title: "Today")
                Spacer(minLength: 0)
                BigValue(parts: hoursParts, size: 40)
                Text("at 90% or more").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                VStack(spacing: 0) {
                    WidgetRow(title: "On charger", value: plugged, first: true)
                    WidgetRow(title: "Lowest", value: facts.todayLowest.map { "\($0)%" } ?? "\u{2014}")
                }
                .padding(.top, 8)
            }
        }
    }

    private var hoursToday: Double {
        max(facts.entry.date.timeIntervalSince(Calendar.current.startOfDay(for: facts.entry.date)) / 3600, 1)
    }

    private var highCharge: String { WidgetFacts.shortDuration(facts.today?.minutesHighCharge ?? 0) }
    private var plugged: String { WidgetFacts.shortDuration(facts.today?.minutesPlugged ?? 0) }

    private var hoursParts: [(String, String)] {
        let minutes = facts.today?.minutesHighCharge ?? 0
        if minutes < 60 { return [("\(minutes)", "min")] }
        return [("\(minutes / 60)", "h"), ("\(minutes % 60)", "min")]
    }
}

// MARK: - Full by

private struct FullByKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily

    private var schedule: FullBySchedule? { facts.settings?.fullBy }

    var body: some View {
        if !facts.hasHelper {
            NeedsHelper(symbol: "clock", title: "Full by", text: "Full by needs the helper.")
        } else {
            switch family {
            case .systemMedium: medium
            case .systemLarge: large
            case .systemExtraLarge: extraLarge
            case .systemExtraLargePortrait: portrait
            default: small
            }
        }
    }

    // MARK: Sizes

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(
                symbol: "clock", title: "Full by", note: schedule.map { $0.isRepeating ? repeatTitle($0) : "Once" })
            Spacer(minLength: 0)
            headline(size: 36)
        }
    }

    private var medium: some View {
        Divided {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(symbol: "clock", title: "Full by")
                Spacer(minLength: 0)
                headline(size: 36)
            }
        } right: {
            VStack(alignment: .leading, spacing: 8) {
                if let schedule {
                    ColumnHeader(title: schedule.isRepeating ? "This week" : "Once", note: time(schedule))
                    WeekStrip(schedule: schedule, next: facts.nextFullBy, skipped: facts.skippedFullBy)
                    Spacer(minLength: 0)
                    actions
                } else {
                    Spacer(minLength: 0)
                    Text("Charge to 100% by a set time, then back to your limit.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    setUpButton
                }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(symbol: "clock", title: "Full by", note: scheduleNote)
            if let schedule {
                headline(size: 52, showsStart: false).padding(.top, 12)
                chargeLine.padding(.top, 12)
                ColumnHeader(title: trackTitle).padding(.top, 14)
                FullByTrack(facts: facts).frame(height: 44).padding(.top, 6)
                ColumnHeader(title: schedule.isRepeating ? "This week" : "Once").padding(.top, 10)
                WeekStrip(schedule: schedule, next: facts.nextFullBy, skipped: facts.skippedFullBy).padding(.top, 6)
                Spacer(minLength: 8)
                actions
            } else {
                off(size: 52)
            }
        }
    }

    private var extraLarge: some View {
        Divided(leftWidth: 300) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetLabel(symbol: "clock", title: "Full by", note: scheduleNote)
                if schedule != nil {
                    headline(size: 60, showsStart: false).padding(.top, 16)
                    chargeLine.padding(.top, 16)
                    planRows.padding(.top, 14)
                    Spacer(minLength: 8)
                    actions
                } else {
                    off(size: 56)
                }
            }
        } right: {
            VStack(alignment: .leading, spacing: 6) {
                if let schedule {
                    ColumnHeader(title: trackTitle, note: facts.limit.map { "Limit \($0)%" })
                    FullByTrack(facts: facts).frame(height: 44)
                    ColumnHeader(title: schedule.isRepeating ? "This week" : "Once", note: time(schedule))
                        .padding(.top, 10)
                    WeekStrip(schedule: schedule, next: facts.nextFullBy, skipped: facts.skippedFullBy)
                    ColumnHeader(title: "Coming up").padding(.top, 10)
                    UpcomingRows(rows: upcoming(4))
                } else {
                    howItWorks
                }
            }
        }
    }

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(symbol: "clock", title: "Full by", note: scheduleNote)
            if let schedule {
                headline(size: 64, showsStart: false).padding(.top, 18)
                chargeLine.padding(.top, 16)
                planRows.padding(.top, 14)
                ColumnHeader(title: trackTitle).padding(.top, 18)
                FullByTrack(facts: facts).frame(height: 44).padding(.top, 6)
                ColumnHeader(title: schedule.isRepeating ? "This week" : "Once", note: time(schedule))
                    .padding(.top, 16)
                WeekStrip(schedule: schedule, next: facts.nextFullBy, skipped: facts.skippedFullBy).padding(.top, 6)
                ColumnHeader(title: "Coming up").padding(.top, 16)
                UpcomingRows(rows: upcoming(5)).padding(.top, 2)
                Spacer(minLength: 8)
                actions
            } else {
                off(size: 60)
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder private func headline(size: CGFloat, showsStart: Bool = true) -> some View {
        let caption: CGFloat = size >= 50 ? 12.5 : 11
        if let deadline = facts.deadline {
            let minutes = facts.estimate?.minutes
            BigValue(parts: minutes.map { durationParts($0) } ?? [("Full", "")], size: size)
            Text("to 100% by \(WidgetFacts.time(deadline))").font(.system(size: caption)).foregroundStyle(.secondary)
                .padding(.top, 4)
            if size < 50 { WidgetMeter(percent: facts.percent, limit: 100).padding(.top, 10) }
        } else if let next = facts.nextFullBy {
            BigValue(parts: timeParts(next), size: size)
            Text(Self.relativeDay(next, now: facts.entry.date, wide: true)).font(.system(size: caption))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if showsStart, let start = facts.fullByStart {
                Text("Starts about \(WidgetFacts.time(start))").font(.system(size: caption)).foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        } else {
            BigValue(parts: [("Off", "")], size: size - 2)
            Text("Set a time in Chargectl").font(.system(size: caption)).foregroundStyle(.secondary).padding(.top, 4)
        }
    }

    /// The charge on its way to 100%, with what happens next.
    private var chargeLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetMeter(percent: facts.percent, limit: 100)
            Text(chargeText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var chargeText: String {
        if facts.deadline != nil {
            return "\(facts.percent)% now" + (facts.finish.map { " · full about \(WidgetFacts.time($0))" } ?? "")
        }
        if let start = facts.fullByStart {
            return "\(facts.percent)% now · charging starts about \(WidgetFacts.time(start))"
        }
        return "\(facts.percent)% now"
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if facts.deadline != nil {
                Button(intent: StopJobIntent()) { Text("Stop") }
                    .buttonStyle(WidgetPillStyle(expands: true))
            } else if let skipped = facts.skippedFullBy {
                // One skip at a time: the next one is skipped already.
                Button(intent: SkipNextFullByIntent()) { Text("\(Self.weekday(skipped)) skipped") }
                    .buttonStyle(WidgetPillStyle(dimmed: true, expands: true))
                    .disabled(true)
            } else {
                Button(intent: SkipNextFullByIntent()) { Text(skipTitle) }
                    .buttonStyle(WidgetPillStyle(expands: true))
            }
            Link(destination: ChargectlWidgetKind.fullBy.url) { Text("Change") }
                .buttonStyle(WidgetPillStyle(expands: true))
        }
    }

    private var setUpButton: some View {
        Link(destination: ChargectlWidgetKind.fullBy.url) { Label("Set Up", systemImage: "clock") }
            .buttonStyle(WidgetPillStyle(filled: true))
    }

    @ViewBuilder private func off(size: CGFloat) -> some View {
        BigValue(parts: [("Off", "")], size: size).padding(.top, 14)
        Text("Charge to 100% by a set time, on the days you pick, then back to your limit.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        // The extra large widget explains it in its right column.
        if family != .systemExtraLarge { howItWorks.padding(.top, 18) }
        Spacer(minLength: 8)
        setUpButton
    }

    /// When charging starts, how long it takes and what comes after.
    private var planRows: some View {
        let back = facts.limit.map { "Back to \($0)%" } ?? "Back to your limit"
        let rows: [(String, String)]
        if let deadline = facts.deadline {
            rows = [
                ("Full", facts.finish.map { "about \(WidgetFacts.time(min($0, deadline)))" } ?? "\u{2014}"),
                ("Then", "At 100% until \(WidgetFacts.time(deadline))"), ("Afterwards", back),
            ]
        } else {
            let minutes = Int((FullBySchedule.leadTime(from: facts.percent) - FullBySchedule.margin) / 60)
            rows = [
                ("Charging starts", facts.fullByStart.map { "about \(WidgetFacts.time($0))" } ?? "\u{2014}"),
                ("Charging takes", "about \(WidgetFacts.duration(max(minutes, 1)))"), ("Afterwards", back),
            ]
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                WidgetRow(title: row.0, value: row.1, first: index == 0)
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 0) {
            ColumnHeader(title: "How it works")
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                WidgetRow(title: step.0, value: step.1, first: index == 0)
            }
        }
    }

    private static let steps = [
        ("Until then", "Held at your limit"), ("Just before", "Charges to 100%"), ("At the time", "Full"),
        ("After", "Back to your limit"),
    ]

    private var scheduleNote: String? {
        guard let schedule else { return nil }
        if let once = schedule.once { return "Once · \(Self.weekday(once)) \(WidgetFacts.time(once))" }
        return "\(repeatTitle(schedule)) · \(time(schedule))"
    }

    private var trackTitle: String {
        guard let next = facts.nextFullBy else { return "Next full charge" }
        let day = Self.relativeDay(next, now: facts.entry.date, wide: false)
        let calendar = Calendar.current
        let near = calendar.isDate(next, inSameDayAs: facts.entry.date) || calendar.isDateInTomorrow(next)
        return near ? "Until \(day.lowercased()) \(WidgetFacts.time(next))" : "Until \(day), \(WidgetFacts.time(next))"
    }

    /// The next full charges, the skipped one first.
    private func upcoming(_ count: Int) -> [UpcomingRows.Row] {
        guard let schedule else { return [] }
        let now = facts.entry.date
        var rows: [UpcomingRows.Row] = []
        if let skipped = facts.skippedFullBy {
            rows.append(.init(title: Self.relativeDay(skipped, now: now, wide: false), value: "Skipped", dimmed: true))
        }
        var next = facts.nextFullBy
        while let date = next, rows.count < count {
            let start =
                date == facts.nextFullBy && facts.deadline == nil
                ? facts.fullByStart
                : date.addingTimeInterval(-FullBySchedule.leadTime(from: facts.limit ?? facts.percent))
            let value =
                date == facts.deadline
                ? "\(WidgetFacts.time(date)) · charging"
                : "\(WidgetFacts.time(date)) · from \(start.map { WidgetFacts.time($0) } ?? "\u{2014}")"
            rows.append(.init(title: Self.relativeDay(date, now: now, wide: false), value: value, dimmed: false))
            next = schedule.nextDeadline(after: date)
        }
        return rows
    }

    private var skipTitle: String {
        facts.nextFullBy.map { "Skip \(Self.weekday($0))" } ?? "Skip"
    }

    private func time(_ schedule: FullBySchedule) -> String {
        let date =
            Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now) ?? .now
        return WidgetFacts.time(date)
    }

    private func repeatTitle(_ schedule: FullBySchedule) -> String {
        if schedule.weekdays == FullBySchedule.weekdaysOnly { return "Weekdays" }
        if schedule.weekdays == FullBySchedule.everyDay { return "Every day" }
        return "Some days"
    }

    private static func weekday(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated)) }

    /// "Today", "Tomorrow", or the day: "Monday" when wide, "Mon 10" otherwise.
    static func relativeDay(_ date: Date, now: Date, wide: Bool) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return "Tomorrow"
        }
        return wide
            ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func timeParts(_ date: Date) -> [(String, String)] {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let uses12 = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
        if uses12 {
            return [
                (String(format: "%d:%02d", hour % 12 == 0 ? 12 : hour % 12, parts.minute ?? 0), hour < 12 ? "AM" : "PM")
            ]
        }
        return [(String(format: "%d:%02d", hour, parts.minute ?? 0), "")]
    }

    private func durationParts(_ minutes: Int) -> [(String, String)] {
        minutes < 60 ? [("\(minutes)", "min")] : [("\(minutes / 60)", "h"), ("\(minutes % 60)", "min")]
    }
}

/// The time until the next full charge on one line: held at the limit, charging, then full at the
/// time, with now on the left.
private struct FullByTrack: View {
    let facts: WidgetFacts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        GeometryReader { geometry in
            if let deadline = facts.nextFullBy {
                let width = geometry.size.width
                let now = facts.entry.date
                let charging = facts.deadline != nil
                let start = charging ? now : max(facts.fullByStart ?? deadline, now)
                let full = charging ? min(facts.finish ?? deadline, deadline) : deadline
                // Some room after the time, so its mark is not on the edge.
                let span = max(deadline.timeIntervalSince(now) * 1.14, 30 * 60)
                let x = { (date: Date) -> CGFloat in
                    width * CGFloat(min(max(date.timeIntervalSince(now) / span, 0), 1))
                }
                let labels = trackLabels(
                    now: now, start: start, deadline: deadline, charging: charging, x: x, width: width)
                ZStack(alignment: .topLeading) {
                    Capsule().fill(palette.track).frame(height: 6).offset(y: 9)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.5), palette.accent], startPoint: .leading,
                                endPoint: .trailing)
                        )
                        .frame(width: max(x(full) - x(start), 6), height: 6)
                        .offset(x: x(start), y: 9)
                        .widgetAccentable()
                    if full < deadline {
                        Capsule().fill(palette.accent.opacity(0.28))
                            .frame(width: max(x(deadline) - x(full), 0), height: 6)
                            .offset(x: x(full), y: 9)
                            .widgetAccentable()
                    }
                    Circle().fill(Color.primary).frame(width: 9, height: 9).offset(y: 7.5)
                    Capsule().fill(Color.primary).frame(width: 2, height: 18).offset(x: x(deadline) - 1, y: 3)
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        Text(label.text)
                            .font(.system(size: 10.5, weight: label.strong ? .medium : .regular))
                            .foregroundStyle(label.strong ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .fixedSize()
                            .position(x: label.x, y: 34)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private struct TrackLabel {
        let text: String
        let x: CGFloat
        var strong = false
    }

    /// Now on the left, when charging starts, and the time; a label that would crowd another is
    /// left out.
    private func trackLabels(
        now: Date, start: Date, deadline: Date, charging: Bool, x: (Date) -> CGFloat, width: CGFloat
    ) -> [TrackLabel] {
        let half: CGFloat = 30
        let clamp = { (value: CGFloat) in min(max(value, half), width - half) }
        let end = TrackLabel(text: WidgetFacts.time(deadline), x: clamp(x(deadline)), strong: true)
        var labels = [end]
        let middle =
            charging
            ? facts.finish.flatMap {
                $0 < deadline ? TrackLabel(text: "Full \(WidgetFacts.time($0))", x: clamp(x($0))) : nil
            }
            : (start > now ? TrackLabel(text: "Starts \(WidgetFacts.time(start))", x: clamp(x(start))) : nil)
        if let middle, end.x - middle.x > 2 * half + 6 { labels.append(middle) }
        let first = TrackLabel(text: charging ? "Charging" : "Now", x: half)
        if labels.allSatisfy({ $0.x - first.x > 2 * half + 6 }) { labels.append(first) }
        // The time held at the limit, named in its middle when there is room.
        if !charging, start > now, let limit = facts.limit {
            let hold = TrackLabel(text: "Held at \(limit)%", x: (x(now) + x(start)) / 2)
            if labels.allSatisfy({ abs($0.x - hold.x) > 2 * half + 14 }) { labels.append(hold) }
        }
        return labels
    }

    private var accessibilityText: String {
        guard let deadline = facts.nextFullBy else { return "No full charge set" }
        if facts.deadline != nil { return "Charging to 100% by \(WidgetFacts.time(deadline))" }
        let start = facts.fullByStart.map { ", charging starts about \(WidgetFacts.time($0))" } ?? ""
        return "Full by \(WidgetFacts.time(deadline))\(start)"
    }
}

/// The next full charges, a row each.
private struct UpcomingRows: View {
    struct Row {
        let title: String
        let value: String
        let dimmed: Bool
    }

    let rows: [Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                WidgetRow(title: row.title, value: row.value, first: index == 0)
                    .opacity(row.dimmed ? 0.55 : 1)
            }
        }
    }
}

/// The week's days, filled where Full by is set, the next one outlined, a skipped one dashed.
private struct WeekStrip: View {
    let schedule: FullBySchedule
    let next: Date?
    var skipped: Date?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let nextDay = next.map { calendar.startOfDay(for: $0) }
        let skippedDay = skipped.map { calendar.startOfDay(for: $0) }
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
                let weekday = calendar.component(.weekday, from: day)
                let on =
                    schedule.once.map { calendar.isDate($0, inSameDayAs: day) } ?? schedule.weekdays.contains(weekday)
                let isSkipped = on && skippedDay == day
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(on && !isSkipped ? palette.accent.opacity(0.22) : palette.chip)
                        .overlay {
                            if on && !isSkipped {
                                Circle().fill(palette.accent).frame(width: 4, height: 4).widgetAccentable()
                            }
                        }
                        .overlay {
                            if isSkipped {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(
                                    palette.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                            } else if nextDay == day {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(
                                    palette.accent, lineWidth: 1.5
                                )
                                .widgetAccentable()
                            }
                        }
                        .frame(height: 28)
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1]).font(.system(size: 9)).foregroundStyle(
                        .tertiary)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = schedule.summary.prefix(1).uppercased() + schedule.summary.dropFirst()
        if let skipped { text += ", \(skipped.formatted(.dateTime.weekday(.wide))) skipped" }
        return text
    }
}

// MARK: - Controls

private struct ControlsKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily

    var body: some View {
        if !facts.hasHelper {
            NeedsHelper(symbol: "slider.horizontal.3", title: "Controls", text: "Charge control needs the helper.")
        } else if family == .systemMedium {
            Divided(leftWidth: 132) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetRing(facts: facts).frame(width: 30, height: 30)
                    Spacer(minLength: 0)
                    percentValue(facts, size: 44)
                    StatusLine(facts: facts, size: 11.5, showsDetail: false).padding(.top, 6)
                }
            } right: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Charge control").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        Toggle(
                            isOn: facts.settings?.isEnabled ?? false,
                            intent: SetChargeControlIntent(isOn: !(facts.settings?.isEnabled ?? false))
                        ) {
                            Text("Charge control")
                        }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                    LimitStepper(facts: facts)
                    Spacer(minLength: 0)
                    JobButtons(facts: facts, compact: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    WidgetRing(facts: facts, lineWidth: 3).frame(width: 26, height: 26)
                    BigValue(parts: [("\(facts.percent)", "%")], size: 20)
                }
                Spacer(minLength: 0)
                LimitStepper(facts: facts)
                HStack(spacing: 6) {
                    Button(intent: TopUpIntent()) { Text("Top Up") }
                        .buttonStyle(WidgetPillStyle(dimmed: facts.status?.mode != .automatic, expands: true))
                    Button(intent: DischargeIntent()) { Text("Discharge") }
                        .buttonStyle(WidgetPillStyle(dimmed: facts.percent <= (facts.limit ?? 100), expands: true))
                }
                .padding(.top, 8)
            }
        }
    }
}

/// − limit + : 5% steps.
private struct LimitStepper: View {
    let facts: WidgetFacts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        let limit = facts.settings?.limit ?? 80
        HStack(spacing: 0) {
            Button(intent: SetChargeLimitIntent(limit: max(limit - 5, ChargeSettings.limitRange.lowerBound))) {
                Image(systemName: "minus").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(limit)").font(.system(size: 18, weight: .light)).contentTransition(.numericText())
                Text("%").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button(intent: SetChargeLimitIntent(limit: min(limit + 5, ChargeSettings.limitRange.upperBound))) {
                Image(systemName: "plus").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 3)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.chip))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Charge limit \(limit) percent")
    }
}

// MARK: - Ring

private struct RingKind: View {
    let facts: WidgetFacts
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetRing(facts: facts, lineWidth: 8, showsGlyph: false) {
            VStack(spacing: 2) {
                BigValue(parts: [("\(facts.percent)", "%")], size: 34)
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        facts.hasHelper ? AnyShapeStyle(.tertiary) : AnyShapeStyle(WidgetPalette(scheme: scheme).warn))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: String {
        if !facts.hasHelper { return "No helper" }
        if let deadline = facts.deadline { return "Full by \(WidgetFacts.time(deadline))" }
        return facts.limit.map { "Limit \($0)%" } ?? "Control off"
    }
}

// MARK: - Time left

private struct TimeLeftKind: View {
    let facts: WidgetFacts
    let family: WidgetFamily

    var body: some View {
        if family == .systemMedium {
            Divided {
                headline
            } right: {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnHeader(title: "Now", note: finishText)
                    HStack(alignment: .firstTextBaseline) {
                        BigValue(parts: [("\(facts.percent)", "%")], size: 22)
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        BigValue(parts: [(goal.map { "\($0)" } ?? "\u{2014}", goal == nil ? "" : "%")], size: 22)
                    }
                    WidgetMeter(percent: facts.percent, limit: goal == 0 ? nil : goal).padding(.top, 6)
                    Spacer(minLength: 0)
                    WidgetRow(
                        title: "Rate", value: "\(WidgetFacts.watts(facts.batteryWatts, signed: true)) W", first: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headline
                if let finish = finishText {
                    Text(finish).font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 8)
                }
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusLine(facts: facts, size: 11.5, showsDetail: false)
            Spacer(minLength: 0)
            if let minutes = facts.estimate?.minutes {
                BigValue(
                    parts: minutes < 60
                        ? [("\(minutes)", "min")] : [("\(minutes / 60)", "h"), ("\(minutes % 60)", "min")], size: 38)
            } else {
                BigValue(parts: [(facts.estimate?.headline ?? "\u{2014}", "")], size: 30)
            }
            Text(facts.estimate.map { $0.minutes == nil ? $0.caption : $0.caption } ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
    }

    /// Where the charge is heading.
    private var goal: Int? {
        if let target = facts.target { return target }
        if !facts.isPluggedIn { return 0 }
        return facts.limit ?? 100
    }

    private var finishText: String? {
        guard let finish = facts.finish else {
            // Holding on the charger has no end time; on battery without an estimate there is nothing to say.
            return facts.isPluggedIn && facts.estimate?.minutes == nil ? "Until you unplug" : nil
        }
        return (facts.isPluggedIn ? "Done " : "Empty ") + WidgetFacts.time(finish)
    }
}
