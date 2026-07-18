import Foundation
import UserNotifications

// Verwaltet die zwei Erinnerungs-Toggles aus den Settings
@Observable
class NotificationManager {
    var dailyReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dailyReminderEnabled, forKey: dailyKey)
            if dailyReminderEnabled {
                Task { await scheduleDailyReminder() }
            } else {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: [dailyIdentifier])
            }
        }
    }

    var dailyReminderTime: Date {
        didSet {
            UserDefaults.standard.set(dailyReminderTime, forKey: dailyTimeKey)
            if dailyReminderEnabled {
                Task { await scheduleDailyReminder() }
            }
        }
    }

    var streakReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(streakReminderEnabled, forKey: streakKey)
            if streakReminderEnabled {
                Task { await scheduleStreakReminder() }
            } else {
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: [streakIdentifier])
            }
        }
    }

    private let dailyKey = "notif_dailyReminderEnabled"
    private let streakKey = "notif_streakReminderEnabled"
    private let dailyTimeKey = "notif_dailyReminderTime"
    private let dailyIdentifier = "dailyReminder"
    private let streakIdentifier = "streakReminder"

    init() {
        dailyReminderEnabled = UserDefaults.standard.bool(forKey: dailyKey)
        streakReminderEnabled = UserDefaults.standard.bool(forKey: streakKey)

        if let saved = UserDefaults.standard.object(forKey: dailyTimeKey) as? Date {
            dailyReminderTime = saved
        } else {
            var comps = DateComponents()
            comps.hour = 20
            comps.minute = 0
            dailyReminderTime = Calendar.current.date(from: comps) ?? Date()
        }
    }

    func enableNotificationsIfNeeded() async {
        guard dailyReminderEnabled || streakReminderEnabled else { return }
        let granted = await requestAuthorization()
        guard granted else { return }
        if dailyReminderEnabled { await scheduleDailyReminder() }
        if streakReminderEnabled { await scheduleStreakReminder() }
    }

    private func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private func scheduleDailyReminder() async {
        guard await requestAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zeit zum Aufräumen"
        content.body = "Ein paar Minuten swipen und wieder Speicherplatz freimachen?"
        content.sound = .default

        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: dailyReminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: dailyIdentifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func scheduleStreakReminder() async {
        guard await requestAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Streak in Gefahr!"
        content.body = "Du hast heute noch nicht geswiped – nicht deine Serie verlieren!"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 21
        dateComponents.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(identifier: streakIdentifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
