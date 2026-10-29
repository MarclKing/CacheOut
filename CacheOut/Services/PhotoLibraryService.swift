import Foundation
import Photos
import SwiftUI

@Observable
class PhotoLibraryService {
    var authorizationStatus: PHAuthorizationStatus = .notDetermined

    // Bleibt für die Dauer der App-Session stabil, erst bei Neustart neu gemischt
    private var cachedShuffleOrder: [String]?

    // Caching-Manager statt PHImageManager.default() — cached bereits angeforderte
    // Bilder intern und macht Prefetching für kommende Swipe-Karten möglich.
    private let imageManager = PHCachingImageManager()

    // Tag/Monat-Index, einmalig aus der kompletten Bibliothek gebaut.
    // Verhindert, dass "Nützliches" bei jedem Öffnen 7x die ganze Library scannt
    // (eine Karte pro Erinnerungstag), weil .dayAcrossYears bisher kein
    // NSPredicate hatte und jedes Mal komplett neu enumeriert wurde.
    @ObservationIgnored private var dayMonthIndexCache: [String: [PHAsset]]?
    @ObservationIgnored private var monthIndexCache: [String: [PHAsset]]?   // Schlüssel "jahr-monat"
    @ObservationIgnored private let cacheLock = NSRecursiveLock()

    // NEU: verhindert, dass warmupExportPipelineIfNeeded() mehrfach läuft.
    private var didWarmupExportPipeline = false

    // NEU: Caches für Fetches
    @ObservationIgnored private var allAssetsCache: [PHAsset]?
    @ObservationIgnored private var assetsByYearCache: [Int: [PHAsset]]?

    // NEU: Datensparmodus — deaktiviert automatischen iCloud-Download für
    // Foto-Karten/-Vorschauen. Wird von CacheOutApp aus AppSettingsStore synchronisiert.
    var dataSaverEnabled: Bool = false

    private func dayMonthIndex() -> [String: [PHAsset]] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = dayMonthIndexCache { return cached }
        let all = fetchAssets(filter: .all)
        let calendar = Calendar.current
        var index: [String: [PHAsset]] = [:]
        for asset in all {
            guard let date = asset.creationDate else { continue }
            let key = "\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))"
            index[key, default: []].append(asset)
        }
        if !all.isEmpty { dayMonthIndexCache = index }
        return index
    }

    private func monthIndex() -> [String: [PHAsset]] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = monthIndexCache { return cached }
        let all = allAssets()
        let calendar = Calendar.current
        var index: [String: [PHAsset]] = [:]
        for asset in all {
            guard let date = asset.creationDate else { continue }
            let c = calendar.dateComponents([.year, .month], from: date)
            guard let y = c.year, let m = c.month else { continue }
            index["\(y)-\(m)", default: []].append(asset)
        }
        if !all.isEmpty { monthIndexCache = index }
        return index
    }

    private func assetsForDay(_ day: Int, month: Int, excludingYear: Int? = nil) -> [PHAsset] {
        let matches = dayMonthIndex()["\(month)-\(day)"] ?? []
        guard let excludingYear else { return matches }
        let calendar = Calendar.current
        return matches.filter {
            guard let date = $0.creationDate else { return false }
            return calendar.component(.year, from: date) != excludingYear
        }
    }

    // MARK: - Permission
    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        // NEU: sobald Zugriff da ist, PHAssetResourceManager schon mal
        // "warmlaufen" lassen — siehe warmupExportPipelineIfNeeded().
        if status == .authorized || status == .limited {
            warmupExportPipelineIfNeeded()
        }
    }

    // NEU: PHAssetResourceManager.default() baut bei seiner allerersten
    // Nutzung in der App-Session im Hintergrund die XPC-Verbindung zum
    // Photos-Daemon auf — das kostet unabhängig von der Dateigröße einmalig
    // spürbar Zeit (genau der "beim ersten Mal nach App-Start langsam,
    // danach immer schnell"-Effekt beim Pfeil-hoch-Vorschau-Button). Wir
    // stoßen diesen Aufwärm-Vorgang deshalb schon hier an, ganz am Anfang der
    // App-Session, mit einem trivialen, sofort wieder gelöschten Export —
    // lange bevor der Nutzer überhaupt eine Swipe-Karte sieht.
    func warmupExportPipelineIfNeeded() {
        guard !didWarmupExportPipeline else { return }
        didWarmupExportPipeline = true
        Task {
            let assets = fetchAssets(filter: .all)
            guard let first = assets.first else { return }
            if let url = await exportToTemporaryURL(for: first) {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
    }

    // NEU
    private func allAssets() -> [PHAsset] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = allAssetsCache { return cached }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        if !assets.isEmpty { allAssetsCache = assets }
        return assets
    }

    // NEU — für Jahres-Auswertungen (SmartSuggestionEngine, yearItemCounts)
    func assetsGroupedByYear() -> [Int: [PHAsset]] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = assetsByYearCache { return cached }
        var result: [Int: [PHAsset]] = [:]
        for asset in allAssets() {
            guard let date = asset.creationDate else { continue }
            let year = Calendar.current.component(.year, from: date)
            result[year, default: []].append(asset)
        }
        if !result.isEmpty { assetsByYearCache = result }
        return result
    }

    // MARK: - Fetch mit Filter
    func fetchAssets(filter: PhotoFilter) -> [PHAsset] {
        // Tages-basierte Filter laufen jetzt über den Index statt über einen
        // vollen Bibliotheks-Scan pro Aufruf.
        switch filter {
        case .onThisDay:
            let today = Date()
            let calendar = Calendar.current
            return assetsForDay(
                calendar.component(.day, from: today),
                month: calendar.component(.month, from: today),
                excludingYear: calendar.component(.year, from: today)
            )
        case .month(let year, let month):
            return monthIndex()["\(year)-\(month)"] ?? []
        case .yearAll(let year):
            return assetsGroupedByYear()[year] ?? []
        case .dayAcrossYears(let day, let month):
            // Erinnerungen = dieser Tag in früheren Jahren; das laufende Jahr zählt nicht.
            return assetsForDay(day, month: month,
                                excludingYear: Calendar.current.component(.year, from: Date()))
        case .all:
            return allAssets()   // NEU: gecacht statt bei jedem Aufruf neu enumeriert
        default:
            break
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var predicate: NSPredicate?

        switch filter {
        case .onlyVideos:
            predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

        case .onlyPhotos:
            predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        case .onlyScreenshots:
            predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)

        case .onlyLivePhotos:
            predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoLive.rawValue)

        case .onlyPortraits:
            predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoDepthEffect.rawValue)

        case .onlyFavorites:
            predicate = NSPredicate(format: "isFavorite == YES")

        case .lastDays(let days):
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            predicate = NSPredicate(format: "creationDate >= %@", cutoff as NSDate)

        case .month(let year, let month):
            var startComponents = DateComponents()
            startComponents.year = year
            startComponents.month = month
            startComponents.day = 1
            let start = Calendar.current.date(from: startComponents)!
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start)!
            predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
            
        case .yearAll(let year):
            var startComponents = DateComponents()
            startComponents.year = year
            startComponents.month = 1
            startComponents.day = 1
            let start = Calendar.current.date(from: startComponents)!
            let end = Calendar.current.date(byAdding: .year, value: 1, to: start)!
            predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)

        case .onThisDay, .dayAcrossYears, .all:
            // Werden bereits oben im ersten switch behandelt und per return
            // abgefangen — dieser Fall wird hier nie erreicht.
            break
        }

        options.predicate = predicate

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
    
    // NEU — Gesamtanzahl Elemente pro Jahr, für die Jahres-Banner in "Mein Leben"
    func yearItemCounts() -> [Int: Int] {
        assetsGroupedByYear().mapValues { $0.count }
    }

    // MARK: - Shuffled All Assets (stabil für App-Session)
    func shuffledAllAssets() -> [PHAsset] {
        let all = fetchAssets(filter: .all)

        if let order = cachedShuffleOrder {
            var lookup: [String: PHAsset] = [:]
            for asset in all { lookup[asset.localIdentifier] = asset }

            var result: [PHAsset] = order.compactMap { lookup[$0] }
            let knownIds = Set(order)
            let newOnes = all.filter { !knownIds.contains($0.localIdentifier) }.shuffled()
            result.append(contentsOf: newOnes)

            cachedShuffleOrder = result.map { $0.localIdentifier }
            return result
        } else {
            let shuffled = all.shuffled()
            cachedShuffleOrder = shuffled.map { $0.localIdentifier }
            return shuffled
        }
    }

    // Jahre + Monate für "Mein Leben"-Übersicht
    func availableYearsAndMonths() -> [Int: Set<Int>] {
        var result: [Int: Set<Int>] = [:]
        for key in monthIndex().keys {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 { result[parts[0], default: []].insert(parts[1]) }
        }
        return result
    }

    private func availableYearsAndMonthsLegacy() -> [Int: Set<Int>] {
        let assets = fetchAssets(filter: .all)
        var result: [Int: Set<Int>] = [:]
        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let year = Calendar.current.component(.year, from: date)
            let month = Calendar.current.component(.month, from: date)
            result[year, default: []].insert(month)
        }
        return result
    }

    // MARK: - Fotoreichste Kalendertage (Basis für die "Storys" in Mein Leben)
    func topPhotoRichDays(limit: Int = 40) -> [(year: Int, month: Int, day: Int, count: Int)] {
        let assets = fetchAssets(filter: .all)
        let calendar = Calendar.current
        var counts: [String: (year: Int, month: Int, day: Int, count: Int)] = [:]

        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { continue }
            let key = "\(y)-\(m)-\(d)"
            if var existing = counts[key] {
                existing.count += 1
                counts[key] = existing
            } else {
                counts[key] = (year: y, month: m, day: d, count: 1)
            }
        }

        return counts.values
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    // NEU: nach Änderungen außerhalb von deleteAssets (z. B. Komprimierung) aufrufen
    func invalidateLibraryCaches() {
        cacheLock.lock(); defer { cacheLock.unlock() }
        dayMonthIndexCache = nil
        monthIndexCache = nil
        allAssetsCache = nil
        assetsByYearCache = nil
    }

    // MARK: - Delete
    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        // Index enthält jetzt gelöschte Assets — beim nächsten Zugriff neu bauen.
        dayMonthIndexCache = nil
        monthIndexCache = nil
        allAssetsCache = nil        // NEU
        assetsByYearCache = nil     // NEU
    }

    // MARK: - Prefetching für die Swipe-Karten
    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }
    
    func cancelRequest(_ id: PHImageRequestID) {
        imageManager.cancelImageRequest(id)
    }

    // MARK: - Dateigröße ermitteln (für Profil-Statistik)
    func fileSize(for asset: PHAsset) async -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var total: Int64 = 0
        for resource in resources {
            if let sizeNumber = resource.value(forKey: "fileSize") as? NSNumber {
                total += sizeNumber.int64Value
            }
        }
        return total
    }

    // Jetzt parallel statt seriell — bei vielen Assets (z. B. Profil-Stats
    // nach großem Löschvorgang) spürbar schneller.
    func totalFileSize(for assets: [PHAsset]) async -> Int64 {
        await withTaskGroup(of: Int64.self) { group in
            for asset in assets {
                group.addTask { await self.fileSize(for: asset) }
            }
            var total: Int64 = 0
            for await size in group { total += size }
            return total
        }
    }

    // MARK: - Image laden (für Swipe-Karten)
    // Für einmalige Loads (z. B. Share-Export) — wartet auf EIN finales Bild.
    func loadImage(
        for asset: PHAsset,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .highQualityFormat
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = deliveryMode
            options.isSynchronous = false
            options.isNetworkAccessAllowed = !dataSaverEnabled
            options.resizeMode = .fast

            var didResume = false
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Bei .highQualityFormat kommt nur EIN finaler Callback — safe.
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    // NEU: Progressive Variante für die Swipe-Karten. Feuert bis zu 2x:
    // sofort ein schnelles Vorschaubild (isDegraded = true), kurz danach
    // automatisch die scharfe Version. onUpdate wird bei JEDEM Callback
    // aufgerufen — der Aufrufer entscheidet, was er damit macht.
    @discardableResult
    func loadImageProgressive(
        for asset: PHAsset,
        targetSize: CGSize,
        onUpdate: @escaping (UIImage?, _ isDegraded: Bool) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        options.isNetworkAccessAllowed = !dataSaverEnabled
        options.resizeMode = .fast

        return imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            onUpdate(image, isDegraded)
        }
    }

    // MARK: - Export für QuickLook-Vorschau
    // PHAsset hat keine direkt nutzbare Datei-URL — wird für die
    // QuickLook-Vollansicht (Long-Press / Expand-Button) gebraucht, exportiert
    // die Original-Ressource in eine temporäre Datei. Bei iCloud-Assets kann
    // das kurz dauern, daher async + Network-Access erlaubt.
    func exportToTemporaryURL(for asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .video || $0.type == .fullSizeVideo
        }) ?? resources.first else { return nil }

        // Eigener UUID-Unterordner pro Export, damit gleichnamige Dateien
        // (z. B. mehrere "IMG_0001.HEIC" aus unterschiedlichen Assets) sich
        // nicht gegenseitig überschreiben.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent(resource.originalFilename)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: fileURL, options: options) { error in
                continuation.resume(returning: error == nil ? fileURL : nil)
            }
        }
    }
}
