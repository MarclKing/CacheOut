import Foundation
import UIKit
import Photos
import Observation

// Zentraler Vorschau-Cache für den "Nützliches"-Tab. Wird beim App-Start
// im Hintergrund befüllt (siehe CacheOutApp), damit beim ersten Tab-Wechsel
// KEIN Laden mehr passiert und die Karten sofort da sind — kein Ruckeln.
@MainActor
@Observable
final class NuetzlichesPreviewCache {
    private(set) var dayMemoryAssets: [Int: [PHAsset]] = [:]
    private(set) var dayMemoryThumbnails: [Int: [UIImage]] = [:]

    private(set) var smartFilterCounts: [String: Int] = [:]
    private(set) var smartFilterPreviews: [String: UIImage] = [:]

    private(set) var isPreloaded = false

    // Einheitliche Quelle für Tages-Erinnerungen & Smart-Filter — sowohl
    // NuetzlichesTab als auch der Preload beim App-Start nutzen DIESELBEN
    // Definitionen, damit die Cache-Keys garantiert übereinstimmen.
    static var dayMemories: [DayMemory] {
        (0..<7).map { offset in
            let calendar = Calendar.current
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            return DayMemory(
                offset: offset,
                referenceDate: date,
                day: calendar.component(.day, from: date),
                month: calendar.component(.month, from: date)
            )
        }
    }

    static var smartFilters: [SmartFilterSelection] {
        [
            SmartFilterSelection(title: "Nur Videos", filter: .onlyVideos),
            SmartFilterSelection(title: "Nur Screenshots", filter: .onlyScreenshots),
            SmartFilterSelection(title: "Letzte 7 Tage", filter: .lastDays(7)),
            SmartFilterSelection(title: "Letzte 31 Tage", filter: .lastDays(31)),
            SmartFilterSelection(title: "Favoriten", filter: .onlyFavorites),
            SmartFilterSelection(title: "Fotos", filter: .onlyPhotos),
            SmartFilterSelection(title: "Live Fotos", filter: .onlyLivePhotos),
            SmartFilterSelection(title: "Porträts", filter: .onlyPortraits)
        ]
    }

    func preload(photoService: PhotoLibraryService) async {
        guard !isPreloaded else { return }

        for memory in Self.dayMemories {
            let fetched = photoService.fetchAssets(filter: .dayAcrossYears(day: memory.day, month: memory.month))
            var loaded: [UIImage] = []
            for asset in fetched.prefix(4) {
                if let image = await photoService.loadImage(for: asset, targetSize: CGSize(width: 300, height: 400)) {
                    loaded.append(image)
                }
            }
            dayMemoryAssets[memory.offset] = fetched
            dayMemoryThumbnails[memory.offset] = loaded
        }

        for filter in Self.smartFilters {
            let assets = photoService.fetchAssets(filter: filter.filter)
            smartFilterCounts[filter.title] = assets.count

            var chosenAsset: PHAsset?
            if case .lastDays(let days) = filter.filter, days > 7 {
                chosenAsset = assets.randomElement()
            } else {
                chosenAsset = assets.first
            }
            if let chosenAsset,
               let image = await photoService.loadImage(for: chosenAsset, targetSize: CGSize(width: 300, height: 300)) {
                smartFilterPreviews[filter.title] = image
            }
        }

        isPreloaded = true
    }

    // NEU: Leert den gesamten Cache
    func clearAll() {
        dayMemoryAssets.removeAll()
        dayMemoryThumbnails.removeAll()
        smartFilterCounts.removeAll()
        smartFilterPreviews.removeAll()
        isPreloaded = false
    }
}
