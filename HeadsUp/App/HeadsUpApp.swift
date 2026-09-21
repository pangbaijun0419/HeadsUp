import SwiftUI
@preconcurrency import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await NotificationService.shared.registerCommitmentCategories() }
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == NotificationService.commitmentActionIdentifier {
            let label = response.notification.request.content.userInfo["commitmentButtonTitle"] as? String
                ?? "我选择主动结束"
            try? await UsageStore.shared.recordCommitment(label)
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run {
                NotificationCenter.default.post(name: .headsUpReminderOpened, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let headsUpReminderOpened = Notification.Name("headsUpReminderOpened")
}

@main
struct HeadsUpApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
