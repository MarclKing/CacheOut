import Foundation
import UIKit
import Photos
import Observation

// Zentraler Vorschau-Cache für "Mein Leben" — analog zu NuetzlichesPreviewCache.
// Übernimmt jetzt auch die komplette Story-Tage-Auswahl-Logik (inkl. der
// "einmal pro Tag einfrieren"-UserDefaults-Logik), die vorher in MeinLebenTab
// steckte — einzige Quelle der Wahrheit, kein doppelter Ladepfad zwischen
// Preload beim App-Start und dem Tab selbst.
@MainActor
@Observable
final class MeinLebenPreviewCache {
    private(set) var yearsData: [Int: Set<Int>] = [:]
    private(set) var storyDays: [StoryDay] = []
    private(set) var storyItems: [StoryPhotoItem] = []
    private(set) var startIdByDay: [String: String] = [:]
    private(set) var assetIdsByDay: [String: [String]] = [:]   // NEU
    private(set) var storyPreviewImages: [String: UIImage] = [:]

    // Nur das aktuelle Jahr wird vorgeladen — alle anderen Jahre/Monate
    // bleiben bewusst lazy über die LazyVGrid im Tab.
    private(set) var currentYearMonthPreviews: [Int: UIImage] = [:]

    private(set) var isPreloaded = false

    private let storyDaysKey = "storyDaysSelection"
    private let storyDaysDateKey = "storyDaysSelectionDate"

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longDayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMMM yyyy"
        return f
    }()

    func preload(photoService: PhotoLibraryService) async {
        guard !isPreloaded else { return }

        yearsData = photoService.availableYearsAndMonths()
        await loadStoryDays(photoService: photoService)
        await loadCurrentYearMonthPreviews(photoService: photoService)

        isPreloaded = true
    }

    // MARK: - Stories

    private func todayDateKey() -> String {
        Self.dayKeyFormatter.string(from: Date())
    }

    private func loadStoryDays(photoService: PhotoLibraryService) async {
        let todayKey = todayDateKey()

        var days: [StoryDay] = []
        if UserDefaults.standard.string(forKey: storyDaysDateKey) == todayKey,
           let saved = UserDefaults.standard.array(forKey: storyDaysKey) as? [String] {
            days = saved.compactMap { StoryDay(idString: $0) }
        }

        if days.isEmpty {
            let richDays = photoService.topPhotoRichDays(limit: 40)
            days = Array(richDays.shuffled().prefix(12))
                .map { StoryDay(year: $0.year, month: $0.month, day: $0.day) }
            UserDefaults.standard.set(days.map { $0.id }, forKey: storyDaysKey)
            UserDefaults.standard.set(todayKey, forKey: storyDaysDateKey)
        }

        // storyDays = days   // ENTFERNT — wird jetzt erst in buildStoryItems final gesetzt (gefiltert)
        await buildStoryItems(for: days, photoService: photoService)
    }

    private struct DayBuildResult {
        let day: StoryDay
        let items: [StoryPhotoItem]
        let startId: String
        let assetIds: [String]
        let preview: UIImage?
    }

    private func buildStoryItems(for days: [StoryDay], photoService: PhotoLibraryService) async {
        let orderIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1.id, $0) })

        let results = await withTaskGroup(of: DayBuildResult?.self) { group -> [DayBuildResult] in
            for day in days {
                group.addTask { @MainActor in
                    let dayAssets = photoService.fetchAssets(filter: .month(year: day.year, month: day.month))
                        .filter { asset in
                            guard let date = asset.creationDate else { return false }
                            return Calendar.current.component(.day, from: date) == day.day
                        }

                    guard dayAssets.count > 7 else { return nil }   // NEU

                    let limited = dayAssets.prefix(15)                // GEÄNDERT
                    guard let first = limited.first else { return nil }
                    let label = self.shortDayLabel(day)
                    let items = limited.map {
                        StoryPhotoItem(id: $0.localIdentifier, asset: $0, dayLabel: label, dayId: day.id)
                    }
                    let preview = await photoService.loadImage(for: first, targetSize: CGSize(width: 150, height: 150))
                    return DayBuildResult(
                        day: day,
                        items: items,
                        startId: first.localIdentifier,
                        assetIds: limited.map { $0.localIdentifier },   // GEÄNDERT
                        preview: preview
                    )
                }
            }
            var collected: [DayBuildResult] = []
            for await result in group {
                if let result { collected.append(result) }
            }
            return collected
        }

        let ordered = results.sorted { (orderIndex[$0.day.id] ?? 0) < (orderIndex[$1.day.id] ?? 0) }

        var items: [StoryPhotoItem] = []
        var startIds: [String: String] = [:]
        var idsByDay: [String: [String]] = [:]
        var previews: [String: UIImage] = [:]

        for result in ordered {
            items.append(contentsOf: result.items)
            startIds[result.day.id] = result.startId
            idsByDay[result.day.id] = result.assetIds
            if let preview = result.preview {
                previews[result.day.id] = preview
            }
        }

        storyDays = ordered.map { $0.day }   // NEU: nur qualifizierte Tage landen final in storyDays
        storyItems = items
        startIdByDay = startIds
        assetIdsByDay = idsByDay
        storyPreviewImages = previews
    }

    private func shortDayLabel(_ day: StoryDay) -> String {
        var comps = DateComponents()
        comps.year = day.year
        comps.month = day.month
        comps.day = day.day
        let date = Calendar.current.date(from: comps) ?? Date()
        return Self.longDayLabelFormatter.string(from: date)
    }

    // MARK: - Monats-Kacheln (nur aktuelles Jahr)

    private func loadCurrentYearMonthPreviews(photoService: PhotoLibraryService) async {
        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())
        guard let months = yearsData[currentYear] else { return }
        let validMonths = months.filter { $0 <= currentMonth }

        let results = await withTaskGroup(of: (Int, UIImage?).self) { group -> [(Int, UIImage?)] in
            for month in validMonths {
                group.addTask { @MainActor in
                    let assets = photoService.fetchAssets(filter: .month(year: currentYear, month: month))
                    guard let first = assets.first else { return (month, nil) }
                    let image = await photoService.loadImage(for: first, targetSize: CGSize(width: 150, height: 150))
                    return (month, image)
                }
            }
            var collected: [(Int, UIImage?)] = []
            for await r in group { collected.append(r) }
            return collected
        }

        for (month, image) in results {
            if let image { currentYearMonthPreviews[month] = image }
        }
    }

    // NEU: Cache leeren (für den "Vorschau-Cache leeren"-Button in Settings)
    func clearAll() {
        yearsData.removeAll()
        storyDays.removeAll()
        storyItems.removeAll()
        startIdByDay.removeAll()
        assetIdsByDay.removeAll()
        storyPreviewImages.removeAll()
        currentYearMonthPreviews.removeAll()
        isPreloaded = false
        // Bewusst NICHT storyDaysKey/storyDaysDateKey löschen — die
        // Story-Tage-Auswahl ist tagesfest gemeint (siehe loadStoryDays),
        // das ist Feature, kein Cache-Bug. "Cache leeren" soll nur veraltete
        // Bilder auffrischen, nicht die Tagesauswahl neu würfeln.
    }
}
