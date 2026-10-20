import Foundation
import UserNotifications

/// Ежедневные напоминания. Выпуски известны заранее, поэтому уведомления планируются
/// на месяц вперёд — с темой и названием первой рекомендации каждого дня.
enum ReminderScheduler {
    private static let identifierPrefix = "kvartet.daily."

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    @MainActor
    static func reschedule(model: AppModel, prefs: Preferences) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard prefs.reminderEnabled, await isAuthorized() else { return }

        let calendar = Days.calendar
        let now = Date()
        for offset in 0..<AppConfig.reminderDaysAhead {
            let day = Days.adding(days: offset, to: now)
            guard let fireDate = calendar.date(bySettingHour: prefs.reminderHour, minute: prefs.reminderMinute, second: 0, of: day),
                  fireDate > now
            else { continue }

            let issue = model.issue(for: day)
            let items = issue.items(for: prefs.enabledKinds)
            let content = UNMutableNotificationContent()
            content.title = "Тема дня — «\(issue.theme)»"
            content.body = body(for: items)
            content.sound = .default
            content.userInfo = ["url": "\(AppConfig.urlScheme)://today"]

            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + Days.key(for: day), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func body(for items: [Item]) -> String {
        guard let first = items.first else { return "Новый выпуск уже ждёт." }
        let rest = items.count - 1
        let lead = "\(first.kind.title) «\(first.title)»"
        guard rest > 0 else { return lead + " — уже ждёт." }
        return "\(lead) и ещё \(Format.count(rest, "открытие", "открытия", "открытий"))."
    }
}
