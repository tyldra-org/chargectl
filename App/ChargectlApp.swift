import SwiftUI

@main
struct ChargectlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage(PreferenceKey.showInMenuBar) private var showInMenuBar = true

    init() {
        CommandLineActions.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Chargectl", id: WindowID.dashboard) {
            DashboardView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 740)
        .defaultLaunchBehavior(showInMenuBar ? .suppressed : .presented)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [WindowID.dashboard])
    }
}

enum WindowID {
    static let dashboard = "dashboard"
    /// Opening this URL shows the dashboard, also when no SwiftUI view is on screen to call openWindow.
    static let dashboardURL = URL(string: "chargectl://dashboard")!
}
