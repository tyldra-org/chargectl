import AppKit
import SwiftUI

extension EnvironmentValues {
    /// False while the window is closed, minimised, on another Space or covered by other windows.
    /// Looping animations and rolling numbers stop then, because they would go on drawing.
    @Entry var isOnScreen = true
}

/// A window's content, built only while the window is open and told whether it is on screen.
/// SwiftUI keeps a closed window's views alive, and their animations and once-a-second updates
/// go on drawing it off screen, which kept the app at half a CPU core with no window open.
struct WindowContent<Content: View>: View {
    /// Off for the menu bar panel, which sizes itself to its content and so must keep it.
    var dropsContentWhenClosed = true
    @ViewBuilder var content: Content
    @State private var isOpen = true
    @State private var isOnScreen = true

    var body: some View {
        ZStack {
            if isOpen || !dropsContentWhenClosed {
                content.environment(\.isOnScreen, isOnScreen)
            }
        }
        .background {
            WindowObserver { open, onScreen in
                if open != isOpen { isOpen = open }
                if onScreen != isOnScreen { isOnScreen = onScreen }
            }
        }
    }
}

private struct WindowObserver: NSViewRepresentable {
    let report: (_ isOpen: Bool, _ isOnScreen: Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) { view.report = report }

    final class ObserverView: NSView {
        var report: ((Bool, Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var isOpen = true

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            observers = [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.windowChanged(name) }
                }
            }
        }

        private func windowChanged(_ name: Notification.Name) {
            guard let window else { return }
            if name == NSWindow.willCloseNotification {
                isOpen = false
            } else if window.isVisible {
                // A closed window that is shown again comes back through its occlusion state.
                isOpen = true
            }
            report?(isOpen, isOpen && window.occlusionState.contains(.visible))
        }
    }
}
