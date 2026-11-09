import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the menu bar's Quit item. Anything else that asks the app to quit (⌘Q, the Dock's
    /// Quit) only closes the dashboard, because charge control lives in the menu bar.
    static var quitRequested = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppearanceMode.current.apply()
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
    /// Opening the app again from Finder or the Dock shows setup until it is finished, then the
    /// dashboard. That matters when the menu bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let id = Setup.isNeeded ? WindowID.welcome : WindowID.dashboard
        if let window = Dashboard.window(id) {
            Dashboard.show(window)
        } else if let open = Dashboard.openWindow {
            Dashboard.show()
            open(id: id)
        } else {
            NSWorkspace.shared.open(Setup.isNeeded ? WindowID.welcomeURL : WindowID.dashboardURL)
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

/// The app's windows and the Dock icon that comes with them.
enum Dashboard {
    /// SwiftUI's openWindow, captured from a view so AppKit code can open windows too.
    static var openWindow: OpenWindowAction?

    static var window: NSWindow? { window(WindowID.dashboard) }

    static func window(_ id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(id) == true }
    }

    /// Shows the Dock icon and brings the window forward.
    static func show(_ window: NSWindow? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let window = window ?? Self.window
        #if DEBUG
            if let window { ScreenshotLayout.place(window) }
        #endif
        window?.makeKeyAndOrderFront(nil)
    }

    /// Back to a menu bar–only app once no window of ours is open.
    static func didClose() {
        DispatchQueue.main.async {
            if !isShowingWindow { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// Whether the dashboard or the welcome window is on screen.
    static var isShowingWindow: Bool {
        [WindowID.dashboard, WindowID.welcome].contains { window($0)?.isVisible == true }
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

#if DEBUG
    /// Debug builds started with `--screenshots` (scripts/screenshots.sh): each window opens in the
    /// middle of the sharpest screen, and the dashboard at 1240 × 880 points, so the README's
    /// screenshots come out the same every time.
    enum ScreenshotLayout {
        static let isOn = CommandLine.arguments.contains("--screenshots")
        static let dashboardSize = NSSize(width: 1240, height: 880)

        static func place(_ window: NSWindow) {
            guard isOn, let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor })
            else { return }
            var frame = window.frame
            if window.identifier?.rawValue.hasPrefix(WindowID.dashboard) == true {
                frame.size = window.frameRect(forContentRect: NSRect(origin: .zero, size: dashboardSize)).size
            }
            let visible = screen.visibleFrame
            frame.origin = NSPoint(
                x: (visible.midX - frame.width / 2).rounded(), y: (visible.midY - frame.height / 2).rounded())
            window.setFrame(frame, display: true)
        }
    }
#endif
