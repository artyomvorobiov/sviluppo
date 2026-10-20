import UIKit
import UserNotifications

extension Notification.Name {
    /// Внутренний переход по ссылке kvartet://… (например, из уведомления).
    static let kvartetOpenURL = Notification.Name("kvartetOpenURL")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ImageStore.shared.trimDiskCache()
        return true
    }

    // Показываем напоминание, даже если приложение открыто.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    // Нажатие на напоминание открывает выпуск дня.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let link = response.notification.request.content.userInfo["url"] as? String
        if let link, let url = URL(string: link) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .kvartetOpenURL, object: url)
            }
        }
        completionHandler()
    }
}
