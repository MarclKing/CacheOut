import Foundation

// Zählt, an wie vielen Tagen in Folge die App geöffnet wurde
@Observable
class StreakTracker {
    private(set) var currentStreak: Int = 0
    private(set) var lastOpenDate: Date?

    private let lastOpenKey = "streakLastOpenDate"
    private let currentStreakKey = "streakCurrentStreak"

    init() {
        currentStreak = UserDefaults.standard.integer(forKey: currentStreakKey)
        lastOpenDate = UserDefaults.standard.object(forKey: lastOpenKey) as? Date
    }

    // Beim App-Start aufrufen
    func recordAppOpen() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let last = lastOpenDate else {
            currentStreak = 1
            lastOpenDate = today
            persist()
            return
        }

        let lastDay = calendar.startOfDay(for: last)
        if lastDay == today {
            return // heute schon gezählt
        }

        let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

        if daysBetween == 1 {
            currentStreak += 1
        } else {
            currentStreak = 1 // Streak gerissen
        }

        lastOpenDate = today
        persist()
    }

    // NEU: Reset des Streaks
    func resetAll() {
        currentStreak = 0
        lastOpenDate = nil
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(currentStreak, forKey: currentStreakKey)
        UserDefaults.standard.set(lastOpenDate, forKey: lastOpenKey)
    }
}
