import AppKit
import UserNotifications

/// Posts what the user turned on in Settings › Notifications: problems, finished jobs and the limit
/// being reached. Asks for permission the first time one is turned on or due.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static func isEnabled(_ kind: StatusEvent.Kind) -> Bool {
        UserDefaults.standard.object(forKey: key(kind)) as? Bool ?? (kind != .limit)
    }

    static func key(_ kind: StatusEvent.Kind) -> String {
        switch kind {
        case .problems: PreferenceKey.notifyProblems
        case .jobs: PreferenceKey.notifyJobs
        case .limit: PreferenceKey.notifyLimit
        }
    }

    /// Asks macOS once; returns whether notifications may be shown.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func post(_ events: [StatusEvent]) {
        let wanted = events.filter { Self.isEnabled($0.kind) }
        guard !wanted.isEmpty else { return }
        Task {
            guard await Self.requestPermission() else { return }
            for event in wanted {
                let content = UNMutableNotificationContent()
                content.title = event.title
                content.body = event.body
                content.threadIdentifier = event.kind.rawValue
                if event.kind == .problems { content.sound = .default }
                let request = UNNotificationRequest(
                    identifier: "\(event.kind.rawValue).\(UUID().uuidString)", content: content, trigger: nil)
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }

    /// Shown also while a Chargectl window is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Clicking one opens the dashboard.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            Dashboard.show()
            NSWorkspace.shared.open(WindowID.dashboardURL)
        }
    }
}
