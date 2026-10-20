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

        // Shown on every launch until setup is finished.
        Window("Welcome to Chargectl", id: WindowID.welcome) {
            WelcomeView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Setup.isNeeded ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [WindowID.welcome])

        Window("Chargectl", id: WindowID.dashboard) {
            DashboardView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1080, height: 740)
        .defaultLaunchBehavior(showInMenuBar || Setup.isNeeded ? .suppressed : .presented)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [WindowID.dashboard])
    }
}

enum WindowID {
    static let dashboard = "dashboard"
    static let welcome = "welcome"
    /// Opening these URLs shows a window, also when no SwiftUI view is on screen to call openWindow.
    static let dashboardURL = URL(string: "chargectl://dashboard")!
    static let welcomeURL = URL(string: "chargectl://welcome")!
}

/// First-run setup: the welcome window opens on every launch until the user finished it and the
/// helper is installed.
enum Setup {
    static var isNeeded: Bool {
        !UserDefaults.standard.bool(forKey: PreferenceKey.setupComplete) || !ServiceInstaller().isInstalled
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: PreferenceKey.setupComplete)
    }
}
