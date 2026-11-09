import SwiftUI

@main
struct ChargectlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @AppStorage(PreferenceKey.showInMenuBar) private var showInMenuBar = true

    init() {
        CommandLineActions.runIfRequested()
        #if DEBUG
            // Before the model exists, so rendering never starts the refresh loop or the updater.
            DesignRender.runIfRequested()
        #endif
        #if DEBUG
            // Debug builds started with --demo show sample data everywhere and never talk to the
            // helper, so they can be tried without changing how the Mac charges.
            if Setup.isDemo {
                _model = State(initialValue: Sample.model(manyLogs: true))
                return
            }
        #endif
        _model = State(initialValue: AppModel())
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
        .defaultLaunchBehavior(Setup.isDemo || !(showInMenuBar || Setup.isNeeded) ? .presented : .suppressed)
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
    /// Debug builds started with --demo (every run from Xcode): sample data, no helper, and
    /// the dashboard opens right away.
    static var isDemo: Bool {
        #if DEBUG
            CommandLine.arguments.contains("--demo")
        #else
            false
        #endif
    }

    static var isNeeded: Bool {
        if isDemo { return false }
        return !UserDefaults.standard.bool(forKey: PreferenceKey.setupComplete)
            || ServiceInstaller().registration != .enabled
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: PreferenceKey.setupComplete)
    }
}
