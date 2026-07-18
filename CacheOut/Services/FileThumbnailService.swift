import QuickLookThumbnailing
import UIKit

// Analog zu PhotoLibraryService: NSCache (RAM-limitiert, wird bei
// Speicherdruck automatisch von iOS geleert) + Request-IDs zum
// Verwerfen veralteter Anfragen beim schnellen Weiterwischen.
final class FileThumbnailService {
    private let cache = NSCache<NSString, UIImage>()
    private var activeRequests: [URL: QLThumbnailGenerator.Request] = [:]

    init() {
        cache.countLimit = 60 // ungefähr Karten-Vorrat + Prefetch-Puffer
    }

    func thumbnail(for url: URL, size: CGSize) async -> UIImage? {
        let key = cacheKey(url: url, size: size)
        if let cached = cache.object(forKey: key) { return cached }

        let scale = UITraitCollection.current.displayScale
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: scale, representationTypes: .thumbnail
        )
        activeRequests[url] = request

        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        activeRequests[url] = nil
        cache.setObject(representation.uiImage, forKey: key)
        return representation.uiImage
    }

    func cancelRequest(for url: URL) {
        // QLThumbnailGenerator hat kein direktes Cancel-per-URL, daher
        // markieren wir es nur als "nicht mehr aktiv" — der Aufrufer prüft
        // bei Rückkehr, ob die Karte inzwischen gewechselt hat (siehe Guard
        // in loadCurrentThumbnail unten), verwirft das Ergebnis dann selbst.
        activeRequests[url] = nil
    }

    private func cacheKey(url: URL, size: CGSize) -> NSString {
        "\(url.path)_\(Int(size.width))x\(Int(size.height))" as NSString
    }
}
