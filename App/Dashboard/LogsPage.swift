import AppKit
import SwiftUI

enum LogFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case observed = "Battery"
    case chargectl = "Chargectl"
    case warnings = "Warnings"

    var id: Self { self }

    func includes(_ entry: LogEntry) -> Bool {
        switch self {
        case .all: true
        case .observed: entry.source == .observed && entry.level != .warning
        case .chargectl: entry.source == .chargectl && entry.level != .warning
        case .warnings: entry.level == .warning
        }
    }
}

struct LogsPage: View {
    let model: AppModel
    @State private var filter = LogFilter.all
    @State private var query = ""
    @State private var copied = false
    @FocusState private var searchFocused: Bool
    @Namespace private var namespace

    var body: some View {
        Group {
            if model.service != .running {
                HelperEmptyState(
                    model: model, symbols: ["battery.75percent", "gearshape", "list.bullet.rectangle"],
                    title: "Install the helper to see its log",
                    message:
                        "The helper logs what the battery does and what Chargectl changes, even while the app is closed. macOS asks for your password once."
                )
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .settleIn(0)
            } else {
                let all = Array(model.logs.reversed())
                let visible = all.filter { filter.includes($0) && matches($0) }
                VStack(spacing: 10) {
                    toolbar(all: all, visible: visible).padding(.horizontal, 24).settleIn(0)
                    LogList(
                        entries: visible, total: all.count, query: query, filter: filter,
                        helperStart: all.last { $0.source == nil && $0.message.hasSuffix(" started") }?.date
                    ) { suggestion in
                        query = suggestion
                    }
                    // Only the filter's thumb slides; hundreds of rows animating would stutter.
                    .animation(nil, value: filter)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .settleIn(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            while !Task.isCancelled {
                await model.loadLogs()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func matches(_ entry: LogEntry) -> Bool {
        query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
    }

    private func toolbar(all: [LogEntry], visible: [LogEntry]) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(LogFilter.allCases) { item in
                    let selected = item == filter
                    let count = all.filter(item.includes).count
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { filter = item }
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.rawValue)
                            Text("\(count)")
                                .font(.system(size: 10.5, weight: item == .warnings && count > 0 ? .semibold : .medium))
                                .monospacedDigit()
                                .foregroundStyle(
                                    item == .warnings && count > 0
                                        ? AnyShapeStyle(Theme.window) : AnyShapeStyle(.tertiary)
                                )
                                .padding(.horizontal, item == .warnings && count > 0 ? 5 : 0)
                                .background(item == .warnings && count > 0 ? Theme.warn : .clear, in: Capsule())
                        }
                        .font(.system(size: 12, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? .primary : .tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.cardTop)
                                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(
                                            Theme.lineStrong)
                                    )
                                    .matchedGeometryEffect(id: "filter", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue), \(count)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Spacer(minLength: 12)
            searchField(count: visible.count)
            Button {
                copy(visible)
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(SoftButtonStyle(kind: copied ? .ok : .normal))
            .disabled(visible.isEmpty)
            .help("Copy the entries shown as plain text")
        }
    }

    private func searchField(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.tertiary)
            TextField("Search messages", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    query = ""
                    searchFocused = false
                    return .handled
                }
            if query.isEmpty {
                Text("⌘F")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.lineStrong))
            } else {
                Text("\(count) \(count == 1 ? "match" : "matches")").font(.system(size: 11)).foregroundStyle(.tertiary)
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 300, height: 28)
        .background(
            searchFocused ? AnyShapeStyle(Theme.cardTop) : AnyShapeStyle(Color.primary.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? Theme.lineStrong : Theme.line)
        )
        .shadow(color: searchFocused ? Theme.accent.opacity(0.25) : .clear, radius: 0.5)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent.opacity(searchFocused ? 0.25 : 0), lineWidth: 3)
                .padding(-3)
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private func copy(_ entries: [LogEntry]) {
        let text = entries.map { entry in
            let time = entry.date.formatted(.dateTime.year().month().day().hour().minute().second())
            let percent = entry.percent.map { "\($0)%" } ?? ""
            return "\(time)\t\(percent)\t\(entry.level == .warning ? "warning: " : "")\(entry.message)"
        }
        .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Confirmations.shared.show("Copied \(entries.count) \(entries.count == 1 ? "entry" : "entries")")
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { copied = false }
        }
    }
}

// MARK: - List

/// Entries from the same second as one moment on a rail, grouped by day.
private struct LogList: View {
    let entries: [LogEntry]
    let total: Int
    let query: String
    let filter: LogFilter
    let helperStart: Date?
    let suggest: (String) -> Void

    struct Moment: Identifiable {
        let id: UUID
        let date: Date
        let lines: [LogEntry]
        var hasWarning: Bool { lines.contains { $0.level == .warning } }
        var isBoot: Bool { lines.contains { $0.source == nil && $0.message.hasSuffix(" started") } }
    }

    private var days: [(day: Date, moments: [Moment])] {
        var moments: [Moment] = []
        var current: [LogEntry] = []
        for entry in entries {
            if let first = current.first, Int(first.date.timeIntervalSince1970) != Int(entry.date.timeIntervalSince1970)
            {
                moments.append(Moment(id: first.id, date: first.date, lines: current))
                current = []
            }
            current.append(entry)
        }
        if let first = current.first { moments.append(Moment(id: first.id, date: first.date, lines: current)) }
        let calendar = Calendar.current
        var days: [(Date, [Moment])] = []
        for moment in moments {
            let day = calendar.startOfDay(for: moment.date)
            if days.last?.0 == day { days[days.count - 1].1.append(moment) } else { days.append((day, [moment])) }
        }
        return days
    }

    var body: some View {
        // The card fills the window and scrolls inside, so the filters and search stay in view.
        Panel(padding: 0) {
            if entries.isEmpty {
                empty.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.day) { day in
                            let count = day.moments.reduce(0) { $0 + $1.lines.count }
                            HStack(alignment: .firstTextBaseline) {
                                Text(dayTitle(day.day)).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(count) \(count == 1 ? "entry" : "entries")").font(.system(size: 11.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                            ForEach(Array(day.moments.enumerated()), id: \.element.id) { index, moment in
                                MomentRow(
                                    moment: moment, query: query, isFirst: index == 0,
                                    isLast: index == day.moments.count - 1)
                                if moment.isBoot, index + 1 < day.moments.count || day.day != days.last?.day {
                                    RestartMarker()
                                }
                            }
                        }
                        Text("\(entries.count) of \(total) entries · the helper keeps the last 300")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .padding(.bottom, 12)
                    }
                    .padding(.top, 4)
                }
                .scrollIndicators(.automatic)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder private var empty: some View {
        VStack(spacing: 0) {
            if !query.isEmpty {
                emptyTile("magnifyingglass", accent: false)
                Text("Nothing matches “\(query)”").font(.system(size: 15, weight: .semibold)).padding(.bottom, 6)
                Text("Search looks through every message\(filter == .all ? "" : " in this filter"). Try one of these:")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.bottom, 14)
                HStack(spacing: 6) {
                    ForEach(["charger", "limit", "wall power", "discharging"], id: \.self) { word in
                        Button(word) { suggest(word) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.lineStrong))
                    }
                }
                .padding(.bottom, 14)
                Button("Clear search") { suggest("") }.buttonStyle(SoftButtonStyle(small: true))
            } else if filter == .warnings {
                emptyTile("checkmark.shield", accent: true)
                Text("No warnings").font(.system(size: 15, weight: .semibold)).padding(.bottom, 6)
                Text(
                    helperStart.map {
                        "Chargectl hasn’t run into a problem since the helper started at \($0.formatted(.dateTime.hour().minute()))."
                    } ?? "Chargectl hasn’t run into a problem."
                )
                .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(
                    maxWidth: 380)
            } else {
                emptyTile("list.bullet.rectangle", accent: false)
                Text("Nothing here yet").font(.system(size: 15, weight: .semibold)).padding(.bottom, 6)
                Text("The helper writes a line when the battery or a setting changes.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private func emptyTile(_ symbol: String, accent: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19))
            .foregroundStyle(accent ? Theme.accent : .secondary)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineStrong))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
            .padding(.bottom, 16)
    }
}

private struct MomentRow: View {
    let moment: LogList.Moment
    let query: String
    let isFirst: Bool
    let isLast: Bool
    @State private var isHovered = false

    private var ordered: [LogEntry] {
        // The battery's line first, then Chargectl's response; at startup the helper's own lines lead.
        func rank(_ entry: LogEntry) -> Int {
            switch entry.source {
            case .observed: moment.isBoot ? 1 : 0
            case .chargectl: 2
            case nil: moment.isBoot ? 0 : 3
            }
        }
        return moment.lines.enumerated().sorted { (rank($0.element), -$0.offset) < (rank($1.element), -$1.offset) }
            .map(\.element)
    }

    var body: some View {
        let lines = ordered
        let hasObserved = lines.contains { $0.source == .observed }
        HStack(alignment: .top, spacing: 10) {
            Text(moment.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 86, alignment: .trailing)
                .padding(.top, 2)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.lineStrong)
                    .frame(width: 1.5)
                    .padding(.top, isFirst ? 10 : -6)
                    .padding(.bottom, isLast ? 0 : -6)
                    .frame(maxHeight: isLast ? 10 : .infinity, alignment: .top)
                Circle()
                    .fill(moment.hasWarning ? Theme.warn : hasObserved ? Theme.accent : Theme.window)
                    .overlay(
                        Circle().strokeBorder(
                            moment.hasWarning || hasObserved ? .clear : Color.secondary, lineWidth: 1.5)
                    )
                    .frame(width: 9, height: 9)
                    .background(Circle().fill(Theme.window).frame(width: 15, height: 15))
                    .shadow(color: moment.hasWarning ? Theme.warn : hasObserved ? Theme.glow : .clear, radius: 5)
                    .padding(.top, 6)
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, entry in
                    LogLine(
                        entry: entry, query: query,
                        isReply: index > 0 && entry.source == .chargectl && entry.level != .warning
                            && lines[index - 1].source != nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(moment.lines.first?.percent.map { "\($0)%" } ?? "")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background {
            if moment.hasWarning {
                LinearGradient(colors: [Theme.warnSoft, .clear], startPoint: .leading, endPoint: .trailing)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(Theme.warn).frame(width: 2).padding(.vertical, 6)
                    }
            } else if isHovered {
                Theme.hover
            }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
    }
}

private struct LogLine: View {
    let entry: LogEntry
    let query: String
    let isReply: Bool

    private enum Kind { case observed, chargectl, helper, warning }

    private var kind: Kind {
        if entry.level == .warning { return .warning }
        switch entry.source {
        case .observed: return .observed
        case .chargectl: return .chargectl
        case nil: return .helper
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
            highlighted
                .font(
                    kind == .helper
                        ? .system(size: 11.5, design: .monospaced)
                        : .system(size: 13, weight: kind == .warning ? .medium : .regular)
                )
                .foregroundStyle(color)
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, isReply ? 26 : 0)
        .overlay(alignment: .topLeading) {
            if isReply {
                Elbow()
                    .stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 10, height: 14)
                    .offset(x: 8, y: -4)
            }
        }
        .help(help)
    }

    private var text: String {
        guard kind != .helper, !entry.message.hasPrefix("macOS") else { return entry.message }
        return entry.message.capitalizedFirst
    }

    private var highlighted: Text {
        guard !query.isEmpty else { return Text(text) }
        var value = AttributedString(text)
        var search = value.startIndex
        while search < value.endIndex,
            let range = value[search...].range(of: query, options: .caseInsensitive)
        {
            value[range].backgroundColor = Theme.accent.opacity(0.28)
            search = range.upperBound
        }
        return Text(value)
    }

    private var color: Color {
        switch kind {
        case .observed: .primary
        case .chargectl: .secondary
        case .helper: Color.secondary.opacity(0.8)
        case .warning: Theme.warn
        }
    }

    @ViewBuilder private var icon: some View {
        let (symbol, fg, bg): (String, Color, Color) =
            switch kind {
            case .observed: ("battery.75percent", LogTone.observedIcon, LogTone.observedTile)
            case .chargectl: ("gearshape", LogTone.chargectlIcon, LogTone.chargectlTile)
            case .helper: ("info.circle", Color.secondary, .clear)
            case .warning: ("exclamationmark.triangle", LogTone.warnIcon, LogTone.warnTile)
            }
        Image(systemName: symbol)
            .font(.system(size: kind == .helper ? 10 : 10.5, weight: .semibold))
            .foregroundStyle(fg)
            .frame(width: kind == .helper ? 14 : 18, height: 18)
            .background(bg, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                if kind == .observed {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(LogTone.observedEdge)
                }
            }
    }

    private var help: String {
        switch kind {
        case .observed: "Measured from the battery and charger"
        case .chargectl: "What Chargectl decided or did"
        case .helper: "Helper message"
        case .warning: "Warning"
        }
    }
}

/// Icon tiles in the log. Light mode uses darker inks so the small icons stay readable.
private enum LogTone {
    static let observedIcon = Theme.hex(light: 0x0F6E2C, dark: 0x32D74B)
    static let observedTile = Theme.hex(light: 0xDCF3E2, dark: 0x32D74B, darkAlpha: 0.13)
    static let observedEdge = Theme.hex(light: 0x0F6E2C, dark: 0x32D74B, lightAlpha: 0.22, darkAlpha: 0)
    static let chargectlIcon = Theme.hex(light: 0x48484D, dark: 0xA4A4A9)
    static let chargectlTile = Theme.hex(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)
    static let warnIcon = Theme.hex(light: 0xA34F00, dark: 0xFFB340)
    static let warnTile = Theme.hex(light: 0xFDECD2, dark: 0xFFB340, darkAlpha: 0.12)
}

private struct RestartMarker: View {
    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 86)
            Rectangle()
                .fill(.clear)
                .frame(width: 22, height: 24)
                .overlay(
                    Rectangle().stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(
                        width: 0.5))
            Label("Helper restarted", systemImage: "arrow.clockwise")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(LinearGradient(colors: [Theme.lineStrong, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }
}
