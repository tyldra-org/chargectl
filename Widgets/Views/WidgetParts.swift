import SwiftUI
import WidgetKit

/// Chargectl's widget colours for one appearance. Fixed per scheme rather than dynamic NSColors,
/// which a widget's archived view does not resolve.
struct WidgetPalette {
    let scheme: ColorScheme

    var accent: Color {
        scheme == .dark ? Color(red: 0.196, green: 0.843, blue: 0.294) : Color(red: 0.133, green: 0.643, blue: 0.278)
    }
    var warn: Color {
        scheme == .dark ? Color(red: 1, green: 0.702, blue: 0.251) : Color(red: 0.78, green: 0.416, blue: 0)
    }
    var track: Color { Color.primary.opacity(scheme == .dark ? 0.13 : 0.09) }
    var line: Color { Color.primary.opacity(scheme == .dark ? 0.09 : 0.08) }
    var chip: Color { Color.primary.opacity(scheme == .dark ? 0.09 : 0.055) }
    /// Text on an accent fill.
    var onAccent: Color { scheme == .dark ? Color(white: 0.05) : .white }

    var background: LinearGradient {
        scheme == .dark
            ? LinearGradient(
                colors: [Color(red: 0.118, green: 0.118, blue: 0.129), Color(red: 0.078, green: 0.078, blue: 0.086)],
                startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [.white, Color(white: 0.965)], startPoint: .top, endPoint: .bottom)
    }

    func tone(_ tone: WidgetFacts.Tone) -> Color {
        switch tone {
        case .active: accent
        case .quiet: Color.secondary
        case .problem: warn
        }
    }
}

/// The menu bar ring at widget size: the track ends at the limit, the charge fills it.
struct WidgetRing<Center: View>: View {
    let facts: WidgetFacts
    var lineWidth: CGFloat = 3.4
    var showsGlyph = true
    @ViewBuilder var center: Center
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        let end = facts.trackEnd.map { Double($0) / 100 }
        let fill = min(Double(facts.percent) / 100, end ?? 1)
        ZStack {
            Group {
                if let end {
                    Circle().trim(from: 0, to: end)
                        .stroke(palette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                } else {
                    Circle().stroke(
                        palette.track,
                        style: StrokeStyle(
                            lineWidth: lineWidth, lineCap: .round, dash: [lineWidth * 0.5, lineWidth * 1.5]))
                }
                Circle().trim(from: 0, to: fill)
                    .stroke(
                        facts.tone == .problem ? palette.warn : palette.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .widgetAccentable()
            }
            .rotationEffect(.degrees(-90))
            .padding(lineWidth / 2)
            if showsGlyph, let glyph = facts.glyph {
                Image(systemName: Self.symbol(glyph))
                    .font(.system(size: lineWidth * 3.4, weight: .bold))
                    .foregroundStyle(glyph == .problem ? palette.warn : .primary)
            }
            center
        }
    }

    static func symbol(_ glyph: WidgetFacts.Glyph) -> String {
        switch glyph {
        case .charging: "bolt.fill"
        case .holding: "pause.fill"
        case .discharging: "arrow.down"
        case .problem: "exclamationmark"
        }
    }
}

extension WidgetRing where Center == EmptyView {
    init(facts: WidgetFacts, lineWidth: CGFloat = 3.4, showsGlyph: Bool = true) {
        self.init(facts: facts, lineWidth: lineWidth, showsGlyph: showsGlyph) { EmptyView() }
    }
}

/// A thin track with the charge, the sailing range hatched under the limit and a tick at the
/// limit or target.
struct WidgetMeter: View {
    let percent: Int
    var limit: Int?
    var lowerBound: Int?
    var label: String?
    var showsScale = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = { (value: Int) in width * CGFloat(value) / 100 }
                ZStack(alignment: .topLeading) {
                    Capsule().fill(palette.track).frame(height: 4).offset(y: label == nil ? 4 : 18)
                    if let limit, let lowerBound, lowerBound < limit {
                        Hatching(color: palette.accent)
                            .frame(width: x(limit) - x(lowerBound), height: 4)
                            .offset(x: x(lowerBound), y: label == nil ? 4 : 18)
                            .widgetAccentable()
                    }
                    Capsule().fill(palette.accent)
                        .frame(width: max(x(percent), 4), height: 4)
                        .offset(y: label == nil ? 4 : 18)
                        .widgetAccentable()
                    if let limit {
                        Capsule().fill(Color.primary)
                            .frame(width: 2, height: 12)
                            .offset(x: x(limit) - 1, y: label == nil ? 0 : 14)
                        if let label {
                            Text(label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(x: min(max(x(limit), 30), width - 30), y: 5)
                        }
                    }
                }
            }
            .frame(height: label == nil ? 12 : 26)
            if showsScale {
                HStack {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                        Text("\(value)")
                        if value != 100 { Spacer(minLength: 0) }
                    }
                }
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(limit.map { "\(percent) percent, limit \($0) percent" } ?? "\(percent) percent")
    }
}

/// Diagonal stripes for the sailing range.
struct Hatching: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 3.4
            }
            context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 1.2)
        }
    }
}

/// The charge over the last hours: a soft area, the line, the limit dashed and a dot at now.
struct ChargeArea: View {
    let samples: [HistorySample]
    let now: Date
    var hours: Double = 6
    var limit: Int?
    var showsGrid = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        GeometryReader { geometry in
            let size = geometry.size
            let points = self.points(in: size)
            ZStack(alignment: .topLeading) {
                if showsGrid {
                    ForEach([0, 50, 100], id: \.self) { value in
                        horizontal(at: y(Double(value), size), width: size.width).stroke(palette.line, lineWidth: 1)
                    }
                }
                if let limit {
                    horizontal(at: y(Double(limit), size), width: size.width)
                        .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                if let last = points.last, points.count > 1 {
                    area(points, height: size.height)
                        .fill(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.24), palette.accent.opacity(0)], startPoint: .top,
                                endPoint: .bottom)
                        )
                        .widgetAccentable()
                    line(points)
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .widgetAccentable()
                    Circle().fill(palette.accent).frame(width: 5.5, height: 5.5).position(last).widgetAccentable()
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func y(_ percent: Double, _ size: CGSize) -> CGFloat {
        size.height - 2 - (size.height - 6) * CGFloat(percent / 100)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let start = now.addingTimeInterval(-hours * 3600)
        return samples.filter { $0.date >= start }.map { sample in
            CGPoint(
                x: size.width * CGFloat(sample.date.timeIntervalSince(start) / (hours * 3600)),
                y: y(Double(sample.percent), size))
        }
    }

    private func horizontal(at y: CGFloat, width: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }
}

/// A line through points, and the area under it down to a height.
private func line(_ points: [CGPoint]) -> Path {
    Path { path in
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
    }
}

private func area(_ points: [CGPoint], height: CGFloat) -> Path {
    var path = line(points)
    guard let first = points.first, let last = points.last else { return path }
    path.addLine(to: CGPoint(x: last.x, y: height))
    path.addLine(to: CGPoint(x: first.x, y: height))
    path.closeSubpath()
    return path
}

/// A trend from a list of values, scaled to its own range.
struct TrendLine: View {
    let values: [Double]
    var filled = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        GeometryReader { geometry in
            let points = self.points(in: geometry.size)
            ZStack(alignment: .topLeading) {
                if let last = points.last, points.count > 1 {
                    if filled {
                        area(points, height: geometry.size.height)
                            .fill(
                                LinearGradient(
                                    colors: [palette.accent.opacity(0.22), palette.accent.opacity(0)], startPoint: .top,
                                    endPoint: .bottom)
                            )
                            .widgetAccentable()
                    }
                    line(points)
                        .stroke(palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .widgetAccentable()
                    Circle().fill(palette.accent).frame(width: 5, height: 5).position(last).widgetAccentable()
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let low = values.min() ?? 0
        let span = max((values.max() ?? 1) - low, 0.4)
        return values.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                y: size.height - 3 - (size.height - 6) * CGFloat((value - low) / span))
        }
    }
}

/// Today as a strip: charging, resting on the charger, or on battery.
struct DayStrip: View {
    let samples: [HistorySample]
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        let start = Calendar.current.startOfDay(for: now)
        let span = max(now.timeIntervalSince(start), 60)
        Canvas { context, size in
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(palette.track))
            let today = samples.filter { $0.date >= start }
            for (index, sample) in today.enumerated() where (sample.wallPower ?? 0) > 0.5 {
                let end = index + 1 < today.count ? today[index + 1].date : sample.date.addingTimeInterval(60)
                let x0 = size.width * sample.date.timeIntervalSince(start) / span
                let x1 = size.width * end.timeIntervalSince(start) / span
                let charging = (sample.batteryPower ?? 0) > 0.5
                context.fill(
                    Path(CGRect(x: x0, y: 0, width: max(x1 - x0, 1), height: size.height)),
                    with: .color(charging ? palette.accent : palette.accent.opacity(0.4)))
            }
        }
        .clipShape(Capsule())
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

/// A large thin number with its unit after it.
struct BigValue: View {
    let parts: [(String, String)]
    var size: CGFloat = 46
    var color: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.0)
                    .font(.system(size: size, weight: .thin))
                    .tracking(-size * 0.04)
                    .foregroundStyle(color ?? .primary)
                    .contentTransition(.numericText())
                Text(part.1)
                    .font(.system(size: size * 0.32, weight: .light))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
                    .padding(.trailing, 5)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// A coloured dot and the status sentence.
struct StatusLine: View {
    let facts: WidgetFacts
    var size: CGFloat = 12
    var showsDetail = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(palette.tone(facts.tone)).frame(width: 6, height: 6).widgetAccentable()
                Text(facts.title)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(facts.tone == .problem ? palette.warn : .primary)
            }
            if showsDetail, let detail = facts.detail {
                Text(detail).font(.system(size: size - 1)).foregroundStyle(.secondary).padding(.leading, 12)
            }
        }
        .lineLimit(1)
    }
}

/// A small caption with an icon, and an optional note on the right.
struct WidgetLabel: View {
    let symbol: String
    let title: String
    var note: String?

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .labelStyle(TightWidgetLabelStyle())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let note { Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
        }
        .lineLimit(1)
    }
}

struct TightWidgetLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10.5, weight: .semibold))
            configuration.title
        }
    }
}

/// A figure: caption, value with its unit, optional detail.
struct WidgetFigure: View {
    let title: String
    let value: String
    var unit: String = ""
    var detail: String?
    var size: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: size, weight: .light)).tracking(-0.3).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(unit).font(.system(size: 10)).foregroundStyle(.tertiary).layoutPriority(-1) }
            }
            if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of figures divided by hairlines.
struct FigureRow: View {
    let figures: [WidgetFigure]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = WidgetPalette(scheme: scheme)
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                figure
                    .padding(.leading, index == 0 ? 0 : 8)
                    .overlay(alignment: .leading) {
                        if index > 0 { Rectangle().fill(palette.line).frame(width: 1) }
                    }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
    }
}

/// A key and value with a hairline above.
struct WidgetRow: View {
    let title: String
    let value: String
    var first = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).layoutPriority(-1)
            Spacer(minLength: 4)
            Text(value)
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
        .padding(.vertical, 5)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(WidgetPalette(scheme: scheme).line).frame(height: 1) }
        }
    }
}

/// A pill button for a widget, filled when it is the main action.
struct WidgetPillStyle: ButtonStyle {
    var filled = false
    var dimmed = false
    var expands = false
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let palette = WidgetPalette(scheme: scheme)
        configuration.label
            .labelStyle(TightWidgetLabelStyle())
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(filled ? palette.onAccent : .primary)
            .padding(.horizontal, expands ? 6 : 10)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: 26)
            .background(Capsule().fill(filled ? palette.accent : palette.chip))
            .opacity(dimmed ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}
