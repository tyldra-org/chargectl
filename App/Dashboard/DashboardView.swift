import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview
    case control
    case history
    case logs
    case settings

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: "battery.75percent"
        case .control: "slider.horizontal.3"
        case .history: "chart.xyaxis.line"
        case .logs: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

struct DashboardView: View {
    let model: AppModel
    @SceneStorage("page") private var page = DashboardPage.overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                NoticeStack(model: model, includeService: page == .overview)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 900, minHeight: 600)
        .tint(Theme.green)
        .ignoresSafeArea(edges: .top)
        .onAppear { Dashboard.show() }
        .onDisappear { Dashboard.didClose() }
        .onOpenURL { url in
            // chargectl://dashboard/<page>
            if let target = DashboardPage(rawValue: url.lastPathComponent) { page = target }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: RingIcon.image(fraction: Double(model.battery?.percent ?? 0) / 100, size: 18))
                    .foregroundStyle(.secondary)
                Text("Chargectl").font(.headline)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
            ForEach(DashboardPage.allCases) { item in
                SidebarRow(page: item, isSelected: item == page) { page = item }
            }
            Spacer()
            ServiceBadge(model: model)
                .padding(.horizontal, 10)
        }
        .padding(.top, 52)
        .padding(.bottom, 16)
        .padding(.horizontal, 10)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .overview: OverviewPage(model: model)
        case .control: ControlPage(model: model)
        case .history: HistoryPage(model: model)
        case .logs: LogsPage(model: model)
        case .settings: SettingsPage(model: model)
        }
    }
}

private struct SidebarRow: View {
    let page: DashboardPage
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            Label(page.title, systemImage: page.symbol)
                .labelStyle(SidebarLabelStyle())
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Color.primary.opacity(isSelected ? 0.08 : isHovered ? 0.04 : 0),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\((DashboardPage.allCases.firstIndex(of: page) ?? 0) + 1)")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.frame(width: 18)
            configuration.title
        }
    }
}

/// Sidebar footer: whether the daemon is enforcing the limit.
private struct ServiceBadge: View {
    let model: AppModel

    var body: some View {
        let (title, color): (String, Color) =
            switch model.service {
            case .running:
                (model.status?.settings.isEnabled == false ? "Control paused" : "Control active", Theme.green)
            case .checking: ("Checking…", .secondary)
            default: ("Read only", Theme.amber)
            }
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NoticeStack: View {
    let model: AppModel
    let includeService: Bool

    var body: some View {
        let notices = model.notices.filter { includeService || !$0.isService }
        if !notices.isEmpty {
            VStack(spacing: 8) {
                ForEach(notices) { notice in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Theme.amber)
                        Text(notice.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if let action = notice.action, let title = notice.actionTitle {
                            Button(title) { model.handle(action) }
                                .controlSize(.small)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }
}
