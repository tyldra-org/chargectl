import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the menu bar's Quit item. Anything else that asks the app to quit (⌘Q, the Dock's
    /// Quit) only closes the dashboard, because charge control lives in the menu bar.
    static var quitRequested = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openAtLoginOnFirstLaunch()
    }

    /// Like other menu bar utilities, Chargectl opens at login unless the user turns it off in
    /// Settings. Only the first launch decides; later choices are left alone.
    private func openAtLoginOnFirstLaunch() {
        let key = "didSetUpOpenAtLogin"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.quitRequested || Self.isSystemQuit { return .terminateNow }
        Dashboard.close()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again from Finder or the Dock shows the dashboard, which matters when the
    /// menu bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let window = Dashboard.window {
            Dashboard.show(window)
        } else {
            NSWorkspace.shared.open(WindowID.dashboardURL)
        }
        return false
    }

    /// Log out, restart and shut down send a quit event with a reason; those must always succeed.
    private static var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEQuitApplication)
        else { return false }
        return event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
    }
}

/// The dashboard window and the Dock icon that comes with it.
enum Dashboard {
    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.dashboard) == true }
    }

    /// Shows the Dock icon and brings the window forward.
    static func show(_ window: NSWindow? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        (window ?? Self.window)?.makeKeyAndOrderFront(nil)
    }

    /// Back to a menu bar–only app.
    static func didClose() {
        NSApp.setActivationPolicy(.accessory)
    }

    static func close() {
        window?.close()
        didClose()
    }

    static func quit() {
        AppDelegate.quitRequested = true
        NSApp.terminate(nil)
    }
}
