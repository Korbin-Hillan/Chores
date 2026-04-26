import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.korbinhillan.choresapp", category: "Notifications")

enum NotificationScheduler {

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            logger.error("Notification permission request failed: \(error)")
            return false
        }
    }

    static func scheduleChoreReminder(
        hour: Int,
        minute: Int,
        chores: [APIChore]
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        // Remove any previously scheduled daily reminder
        center.removePendingNotificationRequests(withIdentifiers: ["daily-chore-reminder"])

        let dueChores = chores.filter { chore in
            guard !chore.archived else { return false }
            switch chore.scheduleSnapshot().state {
            case .dueToday, .overdue:
                return true
            case .unscheduled, .upcoming:
                return false
            }
        }
        guard !dueChores.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Chores reminder"
        content.body = dueChores.count == 1
            ? "Don't forget: \(dueChores[0].title)"
            : "You have \(dueChores.count) recurring chores to check on today."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily-chore-reminder",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            let timeString = "\(hour):" + String(format: "%02d", minute)
            logger.info("Scheduled daily chore reminder at \(timeString)")
        } catch {
            logger.error("Failed to schedule notification: \(error)")
        }
    }

    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["daily-chore-reminder"]
        )
    }
}
