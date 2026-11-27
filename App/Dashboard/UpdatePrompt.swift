import SwiftUI

/// A new version, in the middle of the dashboard on every page, with Restart to Update and Later.
/// Later puts it away for this version, which then installs once the window is closed; the prompt
/// also says when an install from it failed.
struct UpdatePrompt: View {
    private let updater = Updater.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let version = updater.promptVersion {
                Color.black.opacity(scheme == .dark ? 0.42 : 0.2)
                    .contentShape(Rectangle())
                    .transition(.opacity)
                card(version)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: updater.promptVersion)
    }

    private func card(_ version: String) -> some View {
        let failed: String? = if case .failed = updater.phase { updater.failure?.reason } else { nil }
        let installing = if case .installing = updater.phase { true } else { false }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: failed == nil ? "arrow.down.to.line" : "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(failed == nil ? Theme.accent : Theme.warn)
                    .frame(width: 36, height: 36)
                    .background(
                        failed == nil ? Theme.accentSoft : Theme.warnSoft,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(failed == nil ? "Chargectl \(version) is available" : "The update to \(version) failed")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(failed == nil ? "You have \(DaemonIdentity.version)." : "Nothing was changed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text(
                        failed
                            ?? "Chargectl restarts into the new version. It’s downloaded from GitHub and checked against its published checksum and code signature first."
                    )
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                }
            }
            if installing {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                    Text("Installing \(version)…").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }
                .padding(.top, 18)
            } else {
                HStack(spacing: 8) {
                    Text(
                        failed == nil
                            ? "Later installs it when you close this window."
                            : "You are still on \(DaemonIdentity.version)."
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Later") { updater.postpone() }
                        .buttonStyle(SoftButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button {
                        Task { await updater.installAvailable() }
                    } label: {
                        Label(
                            failed == nil ? "Restart to Update" : "Try Again",
                            systemImage: failed == nil ? "arrow.down.to.line" : "arrow.clockwise")
                    }
                    .buttonStyle(SoftButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 18)
            }
        }
        .padding(20)
        .frame(width: 440, alignment: .leading)
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
}
