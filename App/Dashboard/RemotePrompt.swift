import AppKit
import SwiftUI

/// A prompt from the remote config, in the middle of the dashboard on every page, made like the
/// update prompt. The update prompt goes first when both are due.
struct RemotePrompt: View {
    private let remote = RemoteContent.shared
    private let updater = Updater.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let item = updater.promptVersion == nil ? remote.prompt : nil
        ZStack {
            if let item {
                Color.black.opacity(scheme == .dark ? 0.42 : 0.2)
                    .contentShape(Rectangle())
                    .transition(.opacity)
                card(item)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: item?.id)
        // Back from Terminal: hide a prompt whose steps were just done.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            remote.recheck()
        }
    }

    private func card(_ item: RemoteConfig.Item) -> some View {
        let warning = item.tone == .warning
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.symbol ?? (warning ? "exclamationmark.triangle" : "info.circle"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(warning ? Theme.warn : Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        warning ? Theme.warnSoft : Theme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(item.body)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let commands = item.commands, !commands.isEmpty {
                Text(commands.joined(separator: "\n"))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        Theme.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.lineStrong))
                    .padding(.top, 16)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 12)
                Button(item.dismissal == .done ? "Done" : "Later") { dismiss(item) }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                primaryButton(item)
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(width: 480, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(Theme.window)
            shape.fill(LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.lineStrong))
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.18), radius: 32, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder private func primaryButton(_ item: RemoteConfig.Item) -> some View {
        if let commands = item.commands, !commands.isEmpty {
            Button {
                RemoteActions.copy(commands)
            } label: {
                Label("Copy Commands", systemImage: "doc.on.doc")
            }
            .buttonStyle(SoftButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
        } else if let link = item.webLink {
            Button(item.linkTitle ?? "Open") {
                NSWorkspace.shared.open(link)
                dismiss(item)
            }
            .buttonStyle(SoftButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func dismiss(_ item: RemoteConfig.Item) {
        if item.dismissal == .done { remote.finish(item) } else { remote.later(item) }
    }
}

/// Banners from the remote config, at the top of every dashboard page.
struct RemoteBanners: View {
    private let remote = RemoteContent.shared

    var body: some View {
        let banners = remote.banners
        if !banners.isEmpty {
            VStack(spacing: 8) {
                ForEach(banners) { item in
                    let warning = item.tone == .warning
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: item.symbol ?? (warning ? "exclamationmark.triangle" : "info.circle"))
                            .foregroundStyle(warning ? Theme.warn : Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 12.5, weight: .semibold))
                            Text(item.body)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let commands = item.commands, !commands.isEmpty {
                            Button("Copy Commands") { RemoteActions.copy(commands) }
                                .buttonStyle(SoftButtonStyle(small: true))
                        } else if let link = item.webLink {
                            Button(item.linkTitle ?? "Open") { NSWorkspace.shared.open(link) }
                                .buttonStyle(SoftButtonStyle(small: true))
                        }
                        Button {
                            if item.dismissal == .done { remote.finish(item) } else { remote.later(item) }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel(item.dismissal == .done ? "Done" : "Later")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        warning ? Theme.warnSoft : Theme.accentSoft,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder((warning ? Theme.warn : Theme.accent).opacity(0.25)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }
}

enum RemoteActions {
    static func copy(_ commands: [String]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(commands.joined(separator: "\n"), forType: .string)
        Confirmations.shared.show("Copied")
    }
}
