import Charts
import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case quarterHour = "15m"
    case hour = "1h"
    case sixHours = "6h"
    case day = "24h"

    var id: Self { self }
    var duration: TimeInterval {
        switch self {
        case .quarterHour: 15 * 60
        case .hour: 60 * 60
        case .sixHours: 6 * 60 * 60
        case .day: 24 * 60 * 60
        }
    }
}

struct HistoryPage: View {
    let model: AppModel
    let range: HistoryRange
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    /// Shared by all charts, so hovering one shows the same moment in each.
    @State private var hovered: Date?
    @State private var hiddenPower: Set<String> = []

    var body: some View {
        Group {
            if model.service != .running {
                HelperEmptyState(
                    model: model, symbols: ["thermometer.medium", "bolt", "chart.xyaxis.line"],
                    title: "Install the helper to record history",
                    message:
                        "The helper records charge, temperature and power once a minute, even while Chargectl is closed. macOS asks for your password once."
                )
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .settleIn(0)
            } else {
                let now = Date.now
                let start = now.addingTimeInterval(-range.duration)
                let samples = model.history.filter { $0.date >= start }
                if samples.count < 2 {
                    CollectingHistory(first: model.history.last).padding(.horizontal, 24).padding(.top, 4).settleIn(0)
                } else {
                    ScrollView {
                        content(samples, domain: start...now)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            var round = 0
            while !Task.isCancelled {
                await model.loadHistory()
                // The daily record changes once a day.
                if round % 20 == 0 { await model.loadDaily() }
                round += 1
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func content(_ samples: [HistorySample], domain: ClosedRange<Date>) -> some View {
        let shown = hovered.flatMap { date in
            samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        let reading = shown ?? samples.last
        let since = model.history.first.map(\.date).flatMap { $0 > domain.lowerBound ? $0 : nil }
        return VStack(spacing: 14) {
            SpanRow(spans: [1, 1, 1, 1]) {
                summaryTiles(samples)
            }
            .settleIn(0)
            Panel(padding: 22, spotlight: true) {
                VStack(alignment: .leading, spacing: 14) {
                    PanelHeader(title: "Charge", symbol: "chart.xyaxis.line") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let since, shown == nil {
                                Label(
                                    "Recorded since \(since.formatted(.dateTime.hour().minute()))",
                                    systemImage: "circle.fill"
                                )
                                .labelStyle(DotLabelStyle())
                                .padding(.trailing, 6)
                            }
                            Text(shown.map { $0.date.formatted(.dateTime.hour().minute()) } ?? "Now")
                            Text(
                                "\(Text("\(reading?.percent ?? 0)").font(.system(size: 24, weight: .semibold)))\(Text("%").font(.system(size: 13, weight: .medium)))"
                            )
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .rollingNumber(reading?.percent)
                        }
                    }
                    ChargeChart(
                        samples: samples, domain: domain, limit: model.settings?.limit,
                        lowerBound: model.settings?.lowerBound, height: 196, hovered: $hovered)
                    EventPins(samples: samples, domain: domain, limit: model.settings?.limit)
                        .frame(height: 12)
                        .padding(.trailing, 34)
                        .padding(.top, -18)
                    HStack(spacing: 18) {
                        legend(Theme.accent, "Charging")
                        legend(Theme.accent.opacity(0.36), "On the charger, resting")
                        legend(Theme.track, "On battery")
                        if let settings = model.settings {
                            if settings.sailing > 0 {
                                legend(Theme.accentSoft, "Sailing range \(settings.lowerBound)–\(settings.limit)%")
                            }
                            HStack(spacing: 7) {
                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: 1))
                                    path.addLine(to: CGPoint(x: 12, y: 1))
                                }
                                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                                .frame(width: 12, height: 2)
                                Text("Limit \(settings.limit)%")
                            }
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                }
            }
            .settleIn(1)
            SpanRow(spans: [5, 7]) {
                temperatureCard(samples, domain: domain, shown: shown, reading: reading).settleIn(2)
                powerCard(samples, domain: domain, shown: shown, reading: reading).settleIn(3)
            }
            LongTermHealth(model: model).settleIn(4)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Capsule().fill(color).frame(width: 12, height: 4)
            Text(text)
        }
    }

    // MARK: Summary

    @ViewBuilder private func summaryTiles(_ samples: [HistorySample]) -> some View {
        let lowest = samples.min { $0.percent < $1.percent }
        let highest = samples.max { $0.percent < $1.percent }
        let charging = samples.filter { ($0.wallPower ?? 0) > 0.5 && ($0.batteryPower ?? 0) > 0.5 }.count
        let resting = samples.filter { ($0.wallPower ?? 0) > 0.5 && ($0.batteryPower ?? 0) <= 0.5 }.count
        let onBattery = samples.count - charging - resting
        let used = zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            (pair.1.wallPower ?? 0) <= 0.5 && pair.0.percent > pair.1.percent
                ? total + pair.0.percent - pair.1.percent : total
        }
        let peak = samples.filter { $0.temperature != nil }.max { ($0.temperature ?? 0) < ($1.temperature ?? 0) }
        SummaryTile(
            title: "Charge", symbol: "battery.75percent",
            value: lowest?.percent == highest?.percent
                ? Text("\(lowest?.percent ?? 0)\(unitText("%"))")
                : Text("\(lowest?.percent ?? 0)–\(highest?.percent ?? 0)\(unitText("%"))"),
            detail: lowest?.percent == highest?.percent
                ? "Steady" : "Lowest at \(lowest.map { time($0.date) } ?? "–")")
        SummaryTile(
            title: "On the charger", symbol: "powerplug", value: duration(charging + resting),
            detail: resting > 0 ? "\(TimeText.minutes(resting)) of it resting" : "All of it charging"
        ) {
            GeometryReader { geometry in
                let total = CGFloat(max(samples.count, 1))
                HStack(spacing: 2) {
                    Capsule().fill(Theme.accent).frame(width: geometry.size.width * CGFloat(charging) / total)
                    Capsule().fill(Theme.accent.opacity(0.36)).frame(
                        width: geometry.size.width * CGFloat(resting) / total)
                }
            }
            .frame(height: 4)
            .background(Theme.track, in: Capsule())
            .padding(.top, 6)
        }
        SummaryTile(
            title: "On battery", symbol: "bolt", value: duration(onBattery),
            detail: onBattery == 0
                ? "On the charger the whole time"
                : onBattery >= 30
                    ? "Used \(used)% · about \(Int((Double(used) / (Double(onBattery) / 60)).rounded()))% an hour"
                    : "Used \(used)%")
        SummaryTile(
            title: "Peak temperature", symbol: "thermometer.medium",
            value: Text(
                "\(peak?.temperature.map { String(format: "%.1f", unit.value($0)) } ?? "–")\(unitText(" \(unit.symbol)"))"
            ),
            detail: peak.map {
                "\(time($0.date)) · \(($0.batteryPower ?? 0) > 0.5 ? "charging" : ($0.wallPower ?? 0) > 0.5 ? "resting" : "on battery")"
            }
                ?? "–")
    }

    private func unitText(_ text: String) -> Text {
        Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.tertiary)
    }

    private func duration(_ minutes: Int) -> Text {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return Text("\(rest)\(unitText(" min"))") }
        if rest == 0 { return Text("\(hours)\(unitText(" h"))") }
        return Text("\(hours)\(unitText(" h "))\(rest)\(unitText(" min"))")
    }

    private func time(_ date: Date) -> String {
        (Calendar.current.isDateInToday(date) ? "" : "yesterday ") + date.formatted(.dateTime.hour().minute())
    }

    // MARK: Temperature and power

    private func temperatureCard(
        _ samples: [HistorySample], domain: ClosedRange<Date>, shown: HistorySample?, reading: HistorySample?
    ) -> some View {
        let points = samples.compactMap { s in s.temperature.map { (s.date, unit.value($0)) } }
        let values = points.map(\.1)
        let low = (values.min() ?? 0) - max(((values.max() ?? 0) - (values.min() ?? 0)) * 0.2, 0.6)
        let high = (values.max() ?? 1) + max(((values.max() ?? 0) - (values.min() ?? 0)) * 0.2, 0.6)
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Temperature", symbol: "thermometer.medium") {
                    readout(shown, unit.format(reading?.temperature))
                }
                Chart {
                    ForEach(points, id: \.0) { date, value in
                        AreaMark(
                            x: .value("Time", date), yStart: .value("Base", low), yEnd: .value("Temperature", value)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.warn.opacity(0.2), Theme.warn.opacity(0)], startPoint: .top,
                                endPoint: .bottom))
                        LineMark(x: .value("Time", date), y: .value("Temperature", value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.warn)
                            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    }
                    if let threshold = model.settings.flatMap({ $0.heatProtection ? $0.heatThreshold : nil }),
                        unit.value(threshold) < high + 5
                    {
                        RuleMark(y: .value("Heat guard", unit.value(threshold)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                            .foregroundStyle(Theme.warn.opacity(0.7))
                    }
                    crosshair(shown)
                    if let shown, let value = shown.temperature {
                        PointMark(x: .value("Time", shown.date), y: .value("Temperature", unit.value(value)))
                            .foregroundStyle(Theme.warn).symbolSize(40)
                    }
                }
                .modifier(SharedChartStyle(domain: domain, hovered: $hovered, format: { String(format: "%.0f°", $0) }))
                .chartYScale(domain: low...high)
                .frame(height: 128)
                Text(
                    model.settings?.heatProtection == true
                        ? "Heat guard pauses charging above \(unit.format(model.settings?.heatThreshold, decimals: 0))."
                        : "Heat guard is off, so charging never pauses for heat."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func powerCard(
        _ samples: [HistorySample], domain: ClosedRange<Date>, shown: HistorySample?, reading: HistorySample?
    ) -> some View {
        let series: [(key: String, title: String, tint: Color, value: (HistorySample) -> Double?)] = [
            ("mac", "Mac", Theme.mac, { $0.systemPower }),
            ("wall", "Charger", Theme.accent, { $0.wallPower }),
            ("battery", "Battery", Theme.warn, { $0.batteryPower }),
        ]
        let all = samples.flatMap { s in series.compactMap { $0.value(s) } }
        let step: Double = ((all.max() ?? 0) - min(all.min() ?? 0, 0)) > 40 ? 20 : 10
        let low = min(all.min() ?? 0, 0) < 0 ? ((min(all.min() ?? 0, 0) - 2) / step).rounded(.down) * step : 0
        let high = (((all.max() ?? 1) + 3) / step).rounded(.up) * step
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Power", symbol: "bolt") {
                    Text(shown.map { $0.date.formatted(.dateTime.hour().minute()) } ?? "Now")
                }
                Chart {
                    RuleMark(y: .value("Zero", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .foregroundStyle(Theme.lineStrong)
                    ForEach(series.filter { !hiddenPower.contains($0.key) }, id: \.key) { item in
                        ForEach(samples, id: \.date) { sample in
                            if let value = item.value(sample) {
                                LineMark(
                                    x: .value("Time", sample.date), y: .value(item.title, value),
                                    series: .value("Series", item.title)
                                )
                                .interpolationMethod(.monotone)
                                .foregroundStyle(item.tint)
                                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                            }
                        }
                    }
                    crosshair(shown)
                }
                .modifier(SharedChartStyle(domain: domain, hovered: $hovered, format: { "\(Int($0)) W" }))
                .chartYScale(domain: low...high)
                .frame(height: 128)
                HStack(spacing: 6) {
                    ForEach(series, id: \.key) { item in
                        let hidden = hiddenPower.contains(item.key)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if hidden { hiddenPower.remove(item.key) } else { hiddenPower.insert(item.key) }
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(item.tint).frame(width: 7, height: 7).opacity(hidden ? 0.25 : 1)
                                Text(item.title).foregroundStyle(hidden ? .tertiary : .secondary)
                                Text(powerText(item.key, reading.flatMap(item.value)))
                                    .fontWeight(hidden ? .regular : .semibold)
                                    .foregroundStyle(hidden ? .tertiary : .primary)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(hidden ? "Show" : "Hide") \(item.title)")
                    }
                }
                .padding(.leading, -9)
            }
        }
    }

    private func powerText(_ key: String, _ value: Double?) -> String {
        guard let value else { return "–" }
        if key == "battery" { return abs(value) < 0.05 ? "0 W" : Format.signedWatts(value) }
        return Format.watts(value)
    }

    private func readout(_ shown: HistorySample?, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(shown.map { $0.date.formatted(.dateTime.hour().minute()) } ?? "Now")
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
        }
    }

    @ChartContentBuilder private func crosshair(_ shown: HistorySample?) -> some ChartContent {
        if let shown {
            RuleMark(x: .value("Time", shown.date))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.secondary)
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6).shadow(color: Theme.glow, radius: 3)
            configuration.title
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(Theme.lineStrong))
    }
}

private struct SharedChartStyle: ViewModifier {
    let domain: ClosedRange<Date>
    @Binding var hovered: Date?
    let format: (Double) -> String

    func body(content: Content) -> some View {
        content
            .chartXScale(domain: domain)
            .chartPlotStyle { $0.clipped() }
            .chartXSelection(value: $hovered)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { Text(format(value.as(Double.self) ?? 0)) }
                }
            }
    }
}

private struct SummaryTile<Footer: View>: View {
    let title: String
    let symbol: String
    let value: Text
    let detail: String
    @ViewBuilder var footer: Footer

    var body: some View {
        Panel(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                value
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 9)
                    .padding(.bottom, 4)
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                footer
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension SummaryTile where Footer == EmptyView {
    init(title: String, symbol: String, value: Text, detail: String) {
        self.init(title: title, symbol: symbol, value: value, detail: detail) { EmptyView() }
    }
}

/// Plugged in, unplugged and limit reached, pinned where they happened. Hover a pin for the time.
private struct EventPins: View {
    let samples: [HistorySample]
    let domain: ClosedRange<Date>
    let limit: Int?

    private struct Event: Identifiable {
        let id: Date
        let title: String
        let percent: Int
        let isAccent: Bool
    }

    private var events: [Event] {
        func state(_ s: HistorySample) -> Int {
            (s.wallPower ?? 0) <= 0.5 ? 0 : (s.batteryPower ?? 0) > 0.5 ? 2 : 1
        }
        return zip(samples, samples.dropFirst()).compactMap { previous, sample in
            let before = state(previous)
            let after = state(sample)
            guard before != after else { return nil }
            let title =
                after == 0
                ? "Unplugged"
                : before == 0
                    ? "Plugged in"
                    : after == 1
                        ? (limit.map { sample.percent >= $0 - 1 ? "Reached \($0)%" : "Resting" } ?? "Resting")
                        : "Charging again"
            return Event(id: sample.date, title: title, percent: sample.percent, isAccent: title.hasPrefix("Reached"))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
            ForEach(events) { event in
                Circle()
                    .fill(event.isAccent ? Theme.accent : Theme.window)
                    .overlay(Circle().strokeBorder(event.isAccent ? Theme.accent : Color.secondary, lineWidth: 1.5))
                    .shadow(color: event.isAccent ? Theme.glow : .clear, radius: 4)
                    .frame(width: 9, height: 9)
                    .position(x: geometry.size.width * event.id.timeIntervalSince(domain.lowerBound) / span, y: 6)
                    .help("\(event.title) · \(event.id.formatted(.dateTime.hour().minute())) · \(event.percent)%")
                    .accessibilityLabel("\(event.title) at \(event.id.formatted(.dateTime.hour().minute()))")
            }
        }
    }
}

/// Before the second point exists: the first point on a dashed rail and a countdown to the next.
private struct CollectingHistory: View {
    let first: HistorySample?

    var body: some View {
        Panel(padding: 0) {
            ZStack {
                DotField().padding(1)
                VStack(spacing: 0) {
                    ZStack {
                        Rectangle().fill(Theme.line).frame(height: 1).offset(y: -21)
                        Rectangle().fill(Theme.line).frame(height: 1).offset(y: 21)
                        Line()
                            .stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [2, 5]))
                            .frame(height: 1)
                        HStack(spacing: 0) {
                            Spacer()
                            VStack(spacing: 6) {
                                Text(
                                    first.map { "\($0.date.formatted(.dateTime.hour().minute())) · \($0.percent)%" }
                                        ?? "Waiting"
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                PulseDot()
                            }
                            .offset(y: -9)
                            Line()
                                .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                                .frame(width: 60, height: 1)
                        }
                    }
                    .frame(width: 300, height: 84)
                    .padding(.bottom, 18)
                    Text("Collecting history").font(.system(size: 18, weight: .semibold)).padding(.bottom, 8)
                    Text(
                        "The helper records a point every minute. The charts appear with the second point, so this page fills in on its own."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                    .padding(.bottom, 18)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let next = first.map { 60 - Int(context.date.timeIntervalSince($0.date)) % 60 } ?? 60
                        Label {
                            Text(
                                "Next point in \(Text("0:\(String(format: "%02d", max(next, 0)))").fontWeight(.semibold).foregroundStyle(.primary))"
                            )
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Theme.lineStrong))
                    }
                }
                .padding(.vertical, 60)
            }
            .frame(maxWidth: .infinity, minHeight: 440)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

nonisolated private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
