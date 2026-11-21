import Foundation
import Observation
import SwiftData
import UserNotifications

// MARK: - Settings

struct ReminderSettings: Equatable, Sendable {
    var enabled: Bool
    /// Time of day, minutes after midnight.
    var minutes: Int
    var dayBefore: Bool
    var badge: Bool

    var hour: Int { minutes / 60 }
    var minute: Int { minutes % 60 }
}

// MARK: - Scheduling

/// Schedules local notifications for due dates. Everything is rebuilt from
/// scratch each time, which keeps it simple and always in sync with the data.
enum ReminderScheduler {
    static let identifierPrefix = "catobase.reminder."
    /// iOS keeps at most 64 pending notifications per app; leave some room.
    static let maxPending = 60

    struct Plan: Sendable {
        let fireDate: Date
        let title: String
        let body: String
        let thread: String
        let catID: Data?
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// Notifications for these items: on the due day and optionally the day before,
    /// at the chosen time. Past times are skipped; overdue items show in the badge instead.
    @MainActor
    static func plans(for items: [DueItem], settings: ReminderSettings, now: Date = .now) -> [Plan] {
        let calendar = Calendar.current
        let encoder = JSONEncoder()
        var plans: [Plan] = []

        for item in items {
            var parts = calendar.dateComponents([.year, .month, .day], from: item.date)
            parts.hour = settings.hour
            parts.minute = settings.minute
            guard let onDay = calendar.date(from: parts) else { continue }

            let catName = item.cat.displayName
            let catID = try? encoder.encode(item.cat.persistentModelID)
            var detail = item.kind.label
            if let dose = item.treatment?.dose, !dose.trimmed.isEmpty {
                detail += " · \(dose)"
            }

            if onDay > now {
                plans.append(Plan(fireDate: onDay, title: "\(catName): \(item.title) due today",
                                  body: detail, thread: catName, catID: catID))
            }
            if settings.dayBefore,
               let dayBefore = calendar.date(byAdding: .day, value: -1, to: onDay),
               dayBefore > now {
                plans.append(Plan(fireDate: dayBefore, title: "\(catName): \(item.title) due tomorrow",
                                  body: detail, thread: catName, catID: catID))
            }
        }
        return plans.sorted { $0.fireDate < $1.fireDate }
    }

    /// Replaces all scheduled reminders and updates the app icon badge.
    /// Returns how many reminders are now scheduled.
    @discardableResult
    static func apply(_ plans: [Plan], overdueCount: Int, settings: ReminderSettings) async -> Int {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard settings.enabled, await isAuthorized() else {
            try? await center.setBadgeCount(0)
            return 0
        }

        let calendar = Calendar.current
        var scheduled = 0
        for (index, plan) in plans.prefix(maxPending).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = plan.thread
            if let catID = plan.catID {
                content.userInfo = ["catID": catID]
            }
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(index)",
                                                content: content, trigger: trigger)
            do {
                try await center.add(request)
                scheduled += 1
            } catch {
                continue
            }
        }
        try? await center.setBadgeCount(settings.badge ? overdueCount : 0)
        return scheduled
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .count
    }

    /// A notification in five seconds, to check that reminders get through.
    static func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Cat-o-Base"
        content.body = "Reminders are working. 🐾"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "catobase.test", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Opening a cat from a notification

/// Which cat a tapped notification asked to open. Views watch this.
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var pendingCatID: PersistentIdentifier?
    private init() {}
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let data = response.notification.request.content.userInfo["catID"] as? Data,
              let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
        else { return }
        await MainActor.run {
            NotificationRouter.shared.pendingCatID = id
        }
    }
}
