import Charts
import SwiftUI

/// Battery health over months: one point a day from the helper's daily record, plus today from the
/// live reading, next to how long each day the battery spent at 90% or more.
struct LongTermHealth: View {
    let model: AppModel
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @State private var range = Span.threeMonths

    enum Span: String, CaseIterable, Hashable {
        case month = "1M"
        case threeMonths = "3M"
        case year = "1Y"
        case all = "All"

        var days: Int? {
            switch self {
            case .month: 30
            case .threeMonths: 91
            case .year: 365
            case .all: nil
            }
        }
    }

    var body: some View {
        let points = self.points
        Panel(padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                PanelHeader(title: "Battery health over time", symbol: "heart.text.square") {
                    SlidingSegments(options: Span.allCases.map { ($0, $0.rawValue) }, selection: $range, compact: true)
                }
                if points.count < 2 {
                    VStack(spacing: 6) {
                        Text("Collecting, one point a day").font(.system(size: 13, weight: .medium))
                        Text(
                            "Chargectl saves a summary of each day. Health changes slowly; the chart says the most after a few weeks."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        healthChart(points).frame(maxWidth: .infinity)
                        highChargeChart(points).frame(maxWidth: .infinity)
                    }
                }
                if let latest = points.last {
                    HStack(spacing: 0) {
                        stat(
                            "Health", latest.health.map { String(format: "%.1f%%", $0 * 100) } ?? "–",
                            healthChange(points))
                        stat("Cycles", "\(latest.cycleCount)", cycleChange(points))
                        stat("At 90% or more", highChargeAverage(points), "a day, on average")
                        stat("Warmest", warmest(points).0, warmest(points).1)
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
    }

    /// The daily record in the range, with today's reading as the last point.
    private var points: [DailySample] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var points = model.daily.filter { $0.day < today }
        if let battery = model.battery {
            points.append(
                DailySample.summarize(day: today, samples: model.history, battery: battery)
                    ?? DailySample(
                        day: today, fullChargeCapacity: battery.fullChargeCapacity,
                        designCapacity: battery.designCapacity, cycleCount: battery.cycleCount, minutesRecorded: 0,
                        minutesPlugged: 0, minutesHighCharge: 0, averageTemperature: battery.temperature,
                        maxTemperature: battery.temperature))
        }
        guard let days = range.days, let start = calendar.date(byAdding: .day, value: -days, to: today) else {
            return points
        }
        return points.filter { $0.day >= start }
    }

    private func healthChart(_ points: [DailySample]) -> some View {
        let values = points.compactMap { point in point.health.map { (point.day, $0 * 100) } }
        let low = (values.map(\.1).min() ?? 80).rounded(.down) - 1
        let high = min((values.map(\.1).max() ?? 100).rounded(.up) + 1, 100)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Health").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Chart {
                ForEach(values, id: \.0) { day, health in
                    AreaMark(
                        x: .value("Day", day, unit: .day), yStart: .value("Low", low), yEnd: .value("Health", health)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.2), Theme.accent.opacity(0)], startPoint: .top,
                            endPoint: .bottom))
                    LineMark(x: .value("Day", day, unit: .day), y: .value("Health", health))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYScale(domain: low...high)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { Text("\(value.as(Double.self).map { Int($0) } ?? 0)%") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 140)
        }
    }

    private func highChargeChart(_ points: [DailySample]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hours at 90% or more").font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Chart {
                ForEach(points, id: \.day) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Hours", Double(point.minutesHighCharge) / 60)
                    )
                    .foregroundStyle(
                        point.minutesHighCharge > 120 ? Theme.warn.opacity(0.8) : Theme.accent.opacity(0.55)
                    )
                    .cornerRadius(1.5)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { Text("\(value.as(Double.self).map { Int($0) } ?? 0) h") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 140)
        }
    }

    private func stat(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 17, weight: .medium)).monospacedDigit().rollingNumber(value)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func healthChange(_ points: [DailySample]) -> String {
        guard let first = points.first?.health, let last = points.last?.health, points.count > 1 else {
            return "of its capacity when new"
        }
        let change = (last - first) * 100
        let since = points[0].day.formatted(.dateTime.month(.abbreviated).day())
        return abs(change) < 0.05 ? "unchanged since \(since)" : String(format: "%+.1f since %@", change, since)
    }

    private func cycleChange(_ points: [DailySample]) -> String {
        guard let first = points.first, let last = points.last, points.count > 1 else { return "charge cycles" }
        let days = max(1, Calendar.current.dateComponents([.day], from: first.day, to: last.day).day ?? 1)
        let perMonth = Double(last.cycleCount - first.cycleCount) / Double(days) * 30
        return String(format: "%.1f a month", perMonth)
    }

    private func highChargeAverage(_ points: [DailySample]) -> String {
        let recorded = points.filter { $0.minutesRecorded > 0 }
        guard !recorded.isEmpty else { return "–" }
        let hours = Double(recorded.map(\.minutesHighCharge).reduce(0, +)) / Double(recorded.count) / 60
        return String(format: "%.1f h", hours)
    }

    private func warmest(_ points: [DailySample]) -> (String, String) {
        guard
            let day = points.filter({ $0.maxTemperature != nil }).max(by: { $0.maxTemperature! < $1.maxTemperature! }),
            let temperature = day.maxTemperature
        else { return ("–", "no readings yet") }
        return (unit.format(temperature, decimals: 0), day.day.formatted(.dateTime.month(.abbreviated).day()))
    }
}
