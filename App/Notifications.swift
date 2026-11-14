import Foundation
import UserNotifications

// Уведомления о напоминаниях: за неделю и в сам день, в 10:00.
enum Notifications {
    static func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func schedule(_ r: Reminder) async {
        cancel(r)
        guard !r.done, let due = r.dueDate else { return }
        guard await requestAccess() else { return }
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current

        let moments: [(String, Date, String)] = [
            ("week", cal.date(byAdding: .day, value: -7, to: due) ?? due, "Через неделю: \(r.title)"),
            ("day", due, "Сегодня: \(r.title)"),
        ]
        for (suffix, day, text) in moments {
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 10
            guard let fire = cal.date(from: comps), fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "AutoNote"
            content.body = text
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "\(r.notificationID)-\(suffix)",
                                                        content: content, trigger: trigger))
        }
    }

    static func cancel(_ r: Reminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["\(r.notificationID)-week", "\(r.notificationID)-day"])
    }
}
