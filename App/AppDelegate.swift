import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()
    }

    /// Opening the app again from Finder shows the dashboard, which matters when the menu bar
    /// item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        sender.activate()
        if let dashboard = sender.windows.first(where: { $0.identifier?.rawValue == WindowID.dashboard }) {
            dashboard.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(WindowID.dashboardURL)
        }
        return false
    }
}
