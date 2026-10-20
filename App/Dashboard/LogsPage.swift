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
        case .observed: entry.source == .observed
        case .chargectl: entry.source == .chargectl
        case .warnings: entry.level == .warning
        }
    }
}

struct LogsPage: View {
    let model: AppModel
    @State private var filter = LogFilter.all

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $filter) {
                ForEach(LogFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            Group {
                if model.service != .running {
                    ServiceRequired(
                        model: model, description: "The helper logs what the battery does and what it changes."
                    )
                } else {
                    let entries = Array(model.logs.reversed().filter(filter.includes))
                    if entries.isEmpty {
                        ContentUnavailableView("Nothing Here Yet", systemImage: "list.bullet.rectangle")
                    } else {
                        List(entries) { entry in LogRow(entry: entry) }
                            .listStyle(.inset)
                            .alternatingRowBackgrounds()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            while !Task.isCancelled {
                await model.loadLogs()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.date, format: Self.time)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(entry.percent.map { "\($0)%" } ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .imageScale(.small)
                .frame(width: 16)
                .help(help)
            Text(entry.message)
                .foregroundStyle(entry.source == .chargectl ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        if entry.level == .warning { return "exclamationmark.triangle.fill" }
        switch entry.source {
        case .observed: return "battery.75percent"
        case .chargectl: return "gearshape"
        case nil: return "info.circle"
        }
    }

    private var tint: Color {
        entry.level == .warning ? Theme.amber : entry.source == .observed ? Theme.green : .secondary
    }

    private var help: String {
        if entry.level == .warning { return "Warning" }
        switch entry.source {
        case .observed: return "Measured from the battery and charger"
        case .chargectl: return "What Chargectl decided or did"
        case nil: return "Service message"
        }
    }

    private static let time = Date.FormatStyle().hour().minute().second()
}
