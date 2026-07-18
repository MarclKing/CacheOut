import Foundation

// Merkt sich, welche Assets schon geswiped wurden + die Delete-Queue
@Observable
class SwipeStateStore {
    private(set) var swipedIds: Set<String> = []
    private(set) var deleteQueueIds: [String] = []
    private(set) var lastSwipedId: String?
    private(set) var todayCount: Int = 0

    // NEU: nach den bestehenden private(set) var-Deklarationen
    private(set) var recentActionKinds: [String] = []   // "keep" / "delete", letzte 20
    private(set) var recentMediaFlags: [Bool] = []       // NEU: true = Video, parallel zu recentActionKinds
    private var dailyActivity: [String: Int] = [:]       // "yyyy-MM-dd" -> Anzahl
    private(set) var lastActivityDayKey: String?         // NEU: für "Faulenzer"

    private let swipedKey = "swipedAssetIds"
    private let deleteQueueKey = "deleteQueueIds"
    private let todayCountKey = "swipeTodayCount"
    private let todayDateKey = "swipeTodayDate"
    private let recentActionsKey = "recentSwipeActionKinds"
    private let recentMediaKey = "recentSwipeMediaFlags"       // NEU
    private let dailyActivityKey = "swipeDailyActivity"
    private let lastActivityDayKey_ = "lastActivityDayKey"     // NEU (eigener Storage-Key, Name kollidiert sonst mit Property)

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        swipedIds = Set(UserDefaults.standard.stringArray(forKey: swipedKey) ?? [])
        deleteQueueIds = UserDefaults.standard.stringArray(forKey: deleteQueueKey) ?? []
        loadTodayCount()
        // NEU: im init(), nach loadTodayCount()
        recentActionKinds = UserDefaults.standard.stringArray(forKey: recentActionsKey) ?? []
        recentMediaFlags = (UserDefaults.standard.array(forKey: recentMediaKey) as? [Bool]) ?? []   // NEU
        dailyActivity = (UserDefaults.standard.dictionary(forKey: dailyActivityKey) as? [String: Int]) ?? [:]
        lastActivityDayKey = UserDefaults.standard.string(forKey: lastActivityDayKey_)               // NEU
    }

    // Setzt den Tageszähler zurück, falls seit dem letzten Swipe ein neuer
    // Kalendertag begonnen hat — sonst einfach den gespeicherten Wert laden.
    private func loadTodayCount() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let storedDate = UserDefaults.standard.object(forKey: todayDateKey) as? Date

        if let storedDate, calendar.isDate(storedDate, inSameDayAs: today) {
            todayCount = UserDefaults.standard.integer(forKey: todayCountKey)
        } else {
            todayCount = 0
            UserDefaults.standard.set(today, forKey: todayDateKey)
            UserDefaults.standard.set(0, forKey: todayCountKey)
        }
    }

    private func incrementTodayCount() {
        loadTodayCount() // stellt sicher, dass ein Tageswechsel seit App-Start erkannt wird
        todayCount += 1
        UserDefaults.standard.set(todayCount, forKey: todayCountKey)
        recordDailyActivity()
    }

    private func recordDailyActivity() {
        let key = dayKey(for: Date())
        dailyActivity[key, default: 0] += 1
        lastActivityDayKey = key
        UserDefaults.standard.set(key, forKey: lastActivityDayKey_)
        pruneDailyActivity()
    }

    private func pruneDailyActivity() {
        // 60 Tage Puffer — mehr als genug für die aktuell genutzten letzten 7 Tage
        // und den Streak-Zähler, verhindert aber unbegrenztes Wachstum über Jahre.
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) else { return }
        let cutoffKey = dayKey(for: cutoff)
        // "yyyy-MM-dd"-Strings sind lexikographisch sortierbar wie Daten
        dailyActivity = dailyActivity.filter { $0.key >= cutoffKey }
    }

    private func dayKey(for date: Date) -> String {
        Self.dayKeyFormatter.string(from: date)
    }

    // Letzte 7 Tage, älteste zuerst — direkt für StreakRibbonBanner nutzbar
    var activityLast7Days: [Int] {
        (0..<7).reversed().map { offset in
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            return dailyActivity[dayKey(for: date)] ?? 0
        }
    }

    // NEU: Streak-Erkennung für "5 in a row"-Medaillen — merkt sich die letzten
    // Aktionen (keep/delete), unabhängig vom Asset-Typ.
    private func recordActionKind(_ kind: String, isVideo: Bool) {
        recentActionKinds.append(kind)
        recentMediaFlags.append(isVideo)
        if recentActionKinds.count > 20 { recentActionKinds.removeFirst() }
        if recentMediaFlags.count > 20 { recentMediaFlags.removeFirst() }

        // NEU: Aktivitätstag für "Faulenzer" merken
        lastActivityDayKey = dayKey(for: Date())
        UserDefaults.standard.set(lastActivityDayKey, forKey: lastActivityDayKey_)
    }

    var currentKeepStreak: Int { trailingStreak(of: "keep") }
    var currentDeleteStreak: Int { trailingStreak(of: "delete") }

    // NEU: Video-Serie — unabhängig von keep/delete, zählt nur ob's ein Video war
    var currentVideoStreak: Int {
        var streak = 0
        for isVideo in recentMediaFlags.reversed() {
            if isVideo { streak += 1 } else { break }
        }
        return streak
    }

    // NEU: Tage seit der letzten Swipe-Aktion — Basis für "Faulenzer"
    var daysSinceLastActivity: Int {
        guard let lastKey = lastActivityDayKey else { return 0 }
        guard let lastDate = Self.dayKeyFormatter.date(from: lastKey) else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return max(0, days)
    }

    private func trailingStreak(of kind: String) -> Int {
        var streak = 0
        for action in recentActionKinds.reversed() {
            if action == kind { streak += 1 } else { break }
        }
        return streak
    }

    // NEU – Streak direkt aus den echten Swipe-Tagen berechnen
    var currentActivityStreak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())

        // Wenn heute noch nicht geswiped wurde, ab gestern weiterzählen,
        // damit der Streak nicht sofort auf 0 fällt, solange der Tag noch läuft.
        if (dailyActivity[dayKey(for: day)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }

        var streak = 0
        while (dailyActivity[dayKey(for: day)] ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    func hasBeenSwiped(_ id: String) -> Bool {
        swipedIds.contains(id)
    }

    func markKeep(_ id: String, isVideo: Bool = false) {
        swipedIds.insert(id)
        lastSwipedId = id
        incrementTodayCount()
        recordActionKind("keep", isVideo: isVideo)
        persist()
    }

    func markDelete(_ id: String, isVideo: Bool = false) {
        swipedIds.insert(id)
        if !deleteQueueIds.contains(id) {
            deleteQueueIds.append(id)
        }
        lastSwipedId = id
        incrementTodayCount()
        recordActionKind("delete", isVideo: isVideo)
        persist()
    }

    // Für den "Zurück"-Button: letzte Entscheidung rückgängig machen
    func undoLast() {
        guard let id = lastSwipedId else { return }
        swipedIds.remove(id)
        deleteQueueIds.removeAll { $0 == id }
        lastSwipedId = nil
        persist()
    }

    // Setzt ein Asset komplett zurück in den "unbehandelt"-Zustand
    func unmarkAsset(_ id: String) {
        swipedIds.remove(id)
        deleteQueueIds.removeAll { $0 == id }
        if lastSwipedId == id {
            lastSwipedId = nil
        }
        persist()
    }

    // Nach echtem Löschen oder "Später löschen"
    func clearFromDeleteQueue(_ id: String) {
        deleteQueueIds.removeAll { $0 == id }
        persist()
    }

    func clearDeleteQueue() {
        deleteQueueIds.removeAll()
        persist()
    }

    // Für "Fortschritt zurücksetzen" in den Einstellungen
    func resetAllProgress() {
        swipedIds.removeAll()
        deleteQueueIds.removeAll()
        lastSwipedId = nil
        recentActionKinds.removeAll()
        recentMediaFlags.removeAll()
        dailyActivity.removeAll()
        lastActivityDayKey = nil
        todayCount = 0
        UserDefaults.standard.set(0, forKey: todayCountKey)
        UserDefaults.standard.removeObject(forKey: todayDateKey)
        UserDefaults.standard.removeObject(forKey: lastActivityDayKey_)
        persist()
    }

    private var persistTask: Task<Void, Never>?

    private func persist() {
        persistTask?.cancel()
        let swiped = Array(swipedIds)
        let queue = deleteQueueIds
        let actions = recentActionKinds
        let mediaFlags = recentMediaFlags
        let activity = dailyActivity
        let lastDay = lastActivityDayKey
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(swiped, forKey: swipedKey)
            UserDefaults.standard.set(queue, forKey: deleteQueueKey)
            UserDefaults.standard.set(actions, forKey: recentActionsKey)
            UserDefaults.standard.set(mediaFlags, forKey: recentMediaKey)
            UserDefaults.standard.set(activity, forKey: dailyActivityKey)
            UserDefaults.standard.set(lastDay, forKey: lastActivityDayKey_)
        }
    }
}
