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
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @State private var range = HistoryRange.sixHours
    /// Shared by all charts, so hovering one shows the same moment in each.
    @State private var hovered: Date?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            Group {
                if model.service != .running {
                    ServiceRequired(
                        model: model, description: "History is recorded by the control service, once a minute.")
                } else {
                    let now = Date.now
                    let start = now.addingTimeInterval(-range.duration)
                    let samples = model.history.filter { $0.date >= start }
                    if samples.count < 2 {
                        ContentUnavailableView(
                            "Collecting History", systemImage: "chart.xyaxis.line",
                            description: Text("A point is recorded every minute. Check back shortly."))
                    } else {
                        ScrollView {
                            charts(samples, domain: start...now)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            while !Task.isCancelled {
                await model.loadHistory()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func charts(_ samples: [HistorySample], domain: ClosedRange<Date>) -> some View {
        let shown = hovered.flatMap { date in
            samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        let reading = shown ?? samples.last
        let charge = [
            Series(
                name: "Charge", tint: Theme.green,
                points: samples.map { Point(date: $0.date, value: Double($0.percent)) })
        ]
        let temperature = [
            Series(
                name: "Temperature", tint: Theme.amber,
                points: samples.compactMap { s in s.temperature.map { Point(date: s.date, value: unit.value($0)) } })
        ]
        let power = [
            Series(
                name: "Mac", tint: .secondary,
                points: samples.compactMap { s in s.systemPower.map { Point(date: s.date, value: $0) } }),
            Series(
                name: "Charger", tint: Theme.green,
                points: samples.compactMap { s in s.wallPower.map { Point(date: s.date, value: $0) } }),
            Series(
                name: "Battery", tint: Theme.amber,
                points: samples.compactMap { s in s.batteryPower.map { Point(date: s.date, value: $0) } }),
        ]
        return VStack(spacing: 16) {
            MetricChart(
                title: "Charge", series: charge, domain: domain, yDomain: 0...100, hovered: $hovered,
                reading: reading.map { "\($0.percent)%" } ?? "–", limit: model.settings.map { Double($0.limit) },
                format: { "\(Int($0))%" })
            MetricChart(
                title: "Temperature", series: temperature, domain: domain, hovered: $hovered,
                reading: unit.format(reading?.temperature), format: { String(format: "%.0f", $0) })
            MetricChart(
                title: "Power", series: power, domain: domain, hovered: $hovered,
                reading: reading.map { powerReading($0) } ?? "–", showsLegend: true, includesZero: true,
                format: { String(format: "%.0f W", $0) })
            if let shown {
                Text(shown.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func powerReading(_ sample: HistorySample) -> String {
        var parts = ["Mac \(Format.watts(sample.systemPower))", "charger \(Format.watts(sample.wallPower))"]
        if let battery = sample.batteryPower {
            parts.append("battery \(abs(battery) < 0.05 ? "0 W" : Format.signedWatts(battery))")
        }
        return parts.joined(separator: "  ·  ")
    }
}

private struct Point: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

private struct Series: Identifiable {
    var id: String { name }
    let name: String
    let tint: Color
    let points: [Point]
}

private struct MetricChart: View {
    let title: String
    let series: [Series]
    let domain: ClosedRange<Date>
    var yDomain: ClosedRange<Double>?
    @Binding var hovered: Date?
    let reading: String
    var limit: Double?
    var showsLegend = false
    var includesZero = false
    let format: (Double) -> String

    var body: some View {
        let yDomain = yDomain ?? autoDomain
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if showsLegend {
                    ForEach(series) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.tint).frame(width: 6, height: 6)
                            Text(item.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.leading, 6)
                    }
                }
                Spacer()
                Text(reading).monospacedDigit()
            }
            Chart {
                ForEach(series) { item in
                    ForEach(item.points) { point in
                        if series.count == 1 {
                            // Filled from the bottom of the visible range, never from zero off-screen.
                            AreaMark(
                                x: .value("Time", point.date), yStart: .value("Base", yDomain.lowerBound),
                                yEnd: .value(item.name, point.value)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [item.tint.opacity(0.25), item.tint.opacity(0.02)], startPoint: .top,
                                    endPoint: .bottom))
                        }
                        LineMark(
                            x: .value("Time", point.date), y: .value(item.name, point.value),
                            series: .value("Series", item.name)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(item.tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                }
                if let limit {
                    RuleMark(y: .value("Limit", limit))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                }
                if let hovered {
                    RuleMark(x: .value("Time", hovered))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { $0.clipped() }
            .chartXSelection(value: $hovered)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(Theme.chipFill)
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.chipFill)
                    AxisValueLabel { Text(format(value.as(Double.self) ?? 0)) }
                }
            }
            .frame(height: 130)
        }
    }

    private var autoDomain: ClosedRange<Double> {
        var values: [Double] = []
        for item in series { values.append(contentsOf: item.points.map(\.value)) }
        if includesZero { values.append(0) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.15, 1)
        let bottom = includesZero && low >= 0 ? 0 : low - pad
        return bottom...(high + pad)
    }
}
