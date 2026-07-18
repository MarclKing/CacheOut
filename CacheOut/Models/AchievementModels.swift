import SwiftUI

enum Rarity {
    case common, rare, epic

    var gradient: [Color] {
        switch self {
        case .common: return AppTheme.keepGradient
        case .rare: return AppTheme.imageGradient
        case .epic: return [Color(hex: "FAC775"), Color(hex: "D85A30")]
        }
    }

    var label: String {
        switch self {
        case .common: return ""
        case .rare: return "selten"
        case .epic: return "episch"
        }
    }
}

// MARK: - Erfolge (unendlich wachsende Ziele, 4 feste Kacheln im ProfilTab)

struct AchievementDisplay: Identifiable {
    let id: String
    let icon: String
    let title: String
    let rarity: Rarity
    let earnedCount: Int
    let progress: Double

    var isUnlocked: Bool { earnedCount > 0 }
}

// NEU: statt eines einzelnen festen Schwellwerts eine Liste konkret
// definierter Meilensteine (z. B. 50 → 100 → 250 → 500 → 1000 …), und
// danach ein fester "Fortsetzungs-Schritt", der endlos weiterläuft —
// dadurch gibt es nie ein "geschafft", die Ziele wachsen immer weiter,
// aber in sinnvoll größer werdenden Sprüngen statt immer gleich großen.
struct MilestoneSequence {
    let steps: [Double]
    let continuationIncrement: Double

    // Meilenstein für ein bestimmtes Level (0-indiziert): Level 0 = steps[0],
    // Level 1 = steps[1], usw. — nach Ende der Liste wird ab dem letzten
    // Wert um continuationIncrement weitergezählt.
    func milestone(at level: Int) -> Double {
        if level < steps.count {
            return steps[level]
        }
        let extraSteps = level - steps.count + 1
        return (steps.last ?? 0) + Double(extraSteps) * continuationIncrement
    }
}

enum AchievementDefinitionKind {
    case progressive(sequence: MilestoneSequence)   // GEÄNDERT (war: threshold: Double)
    case streak(threshold: Int)                       // einmalige Serien-Schwelle -> nur noch für den Celebration-Trigger genutzt
}

struct AchievementDefinition: Identifiable {
    let id: String
    let icon: String
    let title: String
    let rarity: Rarity
    let kind: AchievementDefinitionKind
    let currentValue: (SwipeStateStore, DeletionStatsStore, StreakTracker) -> Double
}

enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        AchievementDefinition(
            id: "photos_sorted", icon: "photo.fill", title: "Fotos sortiert",
            rarity: .common,
            kind: .progressive(sequence: MilestoneSequence(
                steps: [50, 100, 250, 500, 1000, 2000, 3000, 4000, 5000],
                continuationIncrement: 1000
            ))
        ) { _, stats, _ in Double(stats.totalDeletedPhotos) },

        AchievementDefinition(
            id: "streak_days", icon: "flame.fill", title: "Tage-Streak",
            rarity: .common,
            kind: .progressive(sequence: MilestoneSequence(
                steps: [7, 14, 30, 60, 100, 180, 365],
                continuationIncrement: 100
            ))
        ) { swipe, _, _ in Double(swipe.currentActivityStreak) },

        AchievementDefinition(
            id: "storage_freed", icon: "internaldrive.fill", title: "GB freigemacht",
            rarity: .rare,
            kind: .progressive(sequence: MilestoneSequence(
                steps: [5, 10, 25, 50, 100, 200, 300, 400, 500],
                continuationIncrement: 100
            ))
        ) { _, stats, _ in Double(stats.totalDeletedBytes) / 1_073_741_824 },

        // 4. Ziel, damit die Erfolge-Kachel-Grid genau 4 feste Kacheln hat
        AchievementDefinition(
            id: "videos_sorted", icon: "video.fill", title: "Videos sortiert",
            rarity: .common,
            kind: .progressive(sequence: MilestoneSequence(
                steps: [20, 50, 100, 250, 500, 1000],
                continuationIncrement: 500
            ))
        ) { _, stats, _ in Double(stats.totalDeletedVideos) },

        // Bleiben nur noch für den Celebration-Overlay-Trigger in SwipeDeckView relevant,
        // tauchen NICHT mehr in der Erfolge-Grid auf (siehe goalDefinitions-Filter unten).
        AchievementDefinition(
            id: "keep_streak_5", icon: "hand.raised.fill", title: "5 in Folge behalten",
            rarity: .rare, kind: .streak(threshold: 5)
        ) { swipe, _, _ in Double(swipe.currentKeepStreak) },

        AchievementDefinition(
            id: "delete_streak_10", icon: "trash.fill", title: "10 in Folge gelöscht",
            rarity: .epic, kind: .streak(threshold: 10)
        ) { swipe, _, _ in Double(swipe.currentDeleteStreak) }
    ]

    // nur die "unendlich wachsenden" Ziele -> das ist die 4er-Grid im ProfilTab
    static var goalDefinitions: [AchievementDefinition] {
        all.filter { if case .progressive = $0.kind { return true }; return false }
    }

    static func buildDisplays(store: AchievementStore, swipeStore: SwipeStateStore, stats: DeletionStatsStore, streak: StreakTracker) -> [AchievementDisplay] {
        all.map { definition in
            let value = definition.currentValue(swipeStore, stats, streak)
            let earned = store.count(for: definition.id)

            switch definition.kind {
            case .progressive(let sequence):
                // GEÄNDERT: Ziel- und Vorgänger-Meilenstein statt fixer Modulo-Rechnung
                let target = sequence.milestone(at: earned)
                let previous = earned > 0 ? sequence.milestone(at: earned - 1) : 0
                let span = target - previous
                let progress = span > 0 ? min(1, max(0, (value - previous) / span)) : 0
                return AchievementDisplay(
                    id: definition.id, icon: definition.icon,
                    title: "\(Int(target)) \(definition.title)",
                    rarity: definition.rarity, earnedCount: earned,
                    progress: progress
                )
            case .streak(let threshold):
                return AchievementDisplay(
                    id: definition.id, icon: definition.icon, title: definition.title,
                    rarity: definition.rarity, earnedCount: earned,
                    progress: min(1, value / Double(threshold))
                )
            }
        }
    }

    // gefilterte Version nur für die Erfolge-Grid (4 Stück)
    static func buildGoalDisplays(store: AchievementStore, swipeStore: SwipeStateStore, stats: DeletionStatsStore, streak: StreakTracker) -> [AchievementDisplay] {
        let goalIds = Set(goalDefinitions.map(\.id))
        return buildDisplays(store: store, swipeStore: swipeStore, stats: stats, streak: streak)
            .filter { goalIds.contains($0.id) }
    }
}

@Observable
class AchievementStore {
    private(set) var earnedCounts: [String: Int] = [:]
    private let key = "earnedAchievementCounts"

    init() {
        earnedCounts = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    func count(for id: String) -> Int { earnedCounts[id] ?? 0 }

    @discardableResult
    func checkForNewUnlock(swipeStore: SwipeStateStore, stats: DeletionStatsStore, streak: StreakTracker) -> AchievementDefinition? {
        for definition in AchievementCatalog.all {
            let value = definition.currentValue(swipeStore, stats, streak)
            let earned = earnedCounts[definition.id] ?? 0

            switch definition.kind {
            case .progressive(let sequence):
                // GEÄNDERT: statt Int(value/threshold) wird jetzt Meilenstein
                // für Meilenstein hochgezählt, bis der aktuelle Wert den
                // nächsten Meilenstein nicht mehr überschreitet — funktioniert
                // dadurch unabhängig von fester Schrittgröße.
                var level = earned
                while value >= sequence.milestone(at: level) {
                    level += 1
                }
                if level > earned {
                    earnedCounts[definition.id] = level
                    persist()
                    return definition
                }
            case .streak(let threshold):
                if Int(value) == threshold {
                    earnedCounts[definition.id, default: 0] += 1
                    persist()
                    return definition
                }
            }
        }
        return nil
    }

    private func persist() {
        UserDefaults.standard.set(earnedCounts, forKey: key)
    }

    // Reset aller Erfolge
    func resetAll() {
        earnedCounts.removeAll()
        persist()
    }
}
