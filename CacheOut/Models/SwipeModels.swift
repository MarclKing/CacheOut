import Foundation
import Photos

// Was der Nutzer bei einem Bild entschieden hat
enum SwipeDecision: String, Codable {
    case keep
    case delete
}

// Ein Eintrag in der "zu löschen"-Warteschlange
struct DeleteQueueItem: Identifiable {
    let id: String            // PHAsset.localIdentifier
    let asset: PHAsset
}

// Filter-Optionen für "Nützliches"-Tab und "Mein Leben"
enum PhotoFilter: Equatable, Hashable {
    case all
    case onlyVideos
    case onlyScreenshots
    case onlyFavorites
    case onlyPhotos          // NEU
    case onlyLivePhotos      // NEU
    case onlyPortraits       // NEU
    case lastDays(Int)
    case month(year: Int, month: Int)
    case onThisDay
    case dayAcrossYears(day: Int, month: Int)
    case yearAll(Int)   // NEU: komplettes Jahr für den Jahres-Banner-Tap in "Mein Leben"
    }

// NEU — zentrale Aktion für Swipe-Buttons UND Drag-Geste, damit beide
// dieselbe Animation im SwipeCardContainer auslösen können.
enum SwipeAction: Equatable {
    case keep
    case delete
    case skip
}
