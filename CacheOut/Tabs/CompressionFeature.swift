import SwiftUI
import Photos
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreLocation
import Observation

// MARK: - Modelle

nonisolated struct LargeMediaItem: Identifiable, Hashable, @unchecked Sendable {
    let id: String              // PHAsset.localIdentifier
    let asset: PHAsset
    let bytes: Int64
    let isVideo: Bool
    let duration: TimeInterval

    static func == (lhs: LargeMediaItem, rhs: LargeMediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct PreparedCompression: Sendable {
    let originalId: String
    let compressedURL: URL
    let compressedFilename: String
    let isVideo: Bool
    let originalBytes: Int64
    let compressedBytes: Int64
}

nonisolated enum CompressionError: LocalizedError {
    case assetMissing, noResource, decodeFailed, encodeFailed, exportFailed

    var errorDescription: String? {
        switch self {
        case .assetMissing: return "Datei nicht mehr in der Mediathek."
        case .noResource: return "Originaldatei nicht gefunden."
        case .decodeFailed: return "Bild konnte nicht gelesen werden."
        case .encodeFailed: return "Bild konnte nicht neu kodiert werden."
        case .exportFailed: return "Video-Export fehlgeschlagen."
        }
    }
}

private nonisolated final class ChangeBox: @unchecked Sendable {
    var newIds: [String: String] = [:]
}

func compressionByteString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func compressionDurationString(_ t: TimeInterval) -> String {
    let s = Int(t.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Engine (läuft abseits des Main-Threads, nur Sendable-Parameter)

nonisolated enum CompressionEngine {

    static func largeItem(for asset: PHAsset, excluding: Set<String>) -> LargeMediaItem? {
        let isVideo: Bool
        let subtypes = asset.mediaSubtypes
        switch asset.mediaType {
        case .image:
            isVideo = false
            if subtypes.contains(.photoLive) || subtypes.contains(.photoDepthEffect) || subtypes.contains(.photoPanorama) { return nil }
        case .video:
            isVideo = true
            if subtypes.contains(.videoHighFrameRate) || subtypes.contains(.videoTimelapse) || subtypes.contains(.videoCinematic) { return nil }
        default:
            return nil
        }
        if excluding.contains(asset.localIdentifier) { return nil }

        let resources = PHAssetResource.assetResources(for: asset)
        // Bearbeitete Bilder und RAW+JPEG-Paare lassen wir bewusst aus.
        if resources.contains(where: { $0.type == .adjustmentData || $0.type == .alternatePhoto }) { return nil }
        guard let primary = resources.first(where: { $0.type == (isVideo ? .video : .photo) }) else { return nil }
        let bytes = (primary.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        let threshold = isVideo ? CompressionStore.videoThreshold : CompressionStore.photoThreshold
        guard bytes >= threshold else { return nil }

        return LargeMediaItem(id: asset.localIdentifier, asset: asset, bytes: bytes, isVideo: isVideo, duration: asset.duration)
    }

    @concurrent
    static func prepare(assetId: String, tempDir: URL) async throws -> PreparedCompression? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else {
            throw CompressionError.assetMissing
        }
        let isVideo = asset.mediaType == .video
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == (isVideo ? .video : .photo) }) else {
            throw CompressionError.noResource
        }
        let originalBytes = (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
        let originalName = resource.originalFilename

        // 1) Original nur kurz als temporäre Datei exportieren (kein dauerhaftes Backup mehr)
        let sourceURL = tempDir.appendingPathComponent("src-\(UUID().uuidString)-\(originalName)")
        try await writeResource(resource, to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // 2) Komprimieren
        let compressedURL: URL
        if isVideo {
            compressedURL = try await compressVideo(from: sourceURL, tempDir: tempDir)
        } else {
            let longSide = max(asset.pixelWidth, asset.pixelHeight)
            compressedURL = try compressPhoto(from: sourceURL, longSide: longSide, tempDir: tempDir)
        }

        // 3) Nur behalten, wenn mindestens 10 % kleiner
        let compressedBytes = fileSize(at: compressedURL)
        guard compressedBytes > 0,
              Double(compressedBytes) < Double(originalBytes) * CompressionStore.minimumSavingsFactor else {
            try? FileManager.default.removeItem(at: compressedURL)
            return nil
        }

        let base = (originalName as NSString).deletingPathExtension
        return PreparedCompression(
            originalId: assetId,
            compressedURL: compressedURL,
            compressedFilename: base + "." + compressedURL.pathExtension,
            isVideo: isVideo,
            originalBytes: originalBytes,
            compressedBytes: compressedBytes
        )
    }

    static func compressPhoto(from sourceURL: URL, longSide: Int, tempDir: URL) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { throw CompressionError.decodeFailed }

        let target = max(1, min(CompressionStore.photoMaxPixel, longSide))
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw CompressionError.decodeFailed
        }

        // Metadaten (EXIF, GPS …) übernehmen; Ausrichtung ist durch die Transformation bereits angewendet.
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 1
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        props.removeValue(forKey: kCGImagePropertyJFIFDictionary)
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            props[kCGImagePropertyExifDictionary] = exif
        }
        props[kCGImageDestinationLossyCompressionQuality] = CompressionStore.photoQuality

        let candidates: [(UTType, String)] = [(.heic, "heic"), (.jpeg, "jpg")]
        for (type, ext) in candidates {
            let url = tempDir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, props as CFDictionary)
            if CGImageDestinationFinalize(destination) { return url }
            try? FileManager.default.removeItem(at: url)
        }
        throw CompressionError.encodeFailed
    }

    @concurrent
    static func compressVideo(from sourceURL: URL, tempDir: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let presets = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720]
        var lastError: Error = CompressionError.exportFailed
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let outURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
            do {
                try await session.export(to: outURL, as: .mov)
                return outURL
            } catch {
                print("⚠️ Video-Export mit \(preset) fehlgeschlagen:", error)
                lastError = error
                try? FileManager.default.removeItem(at: outURL)
            }
        }
        throw lastError
    }

    static func writeResource(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    static func performLibraryChanges(_ block: @escaping @Sendable () -> Void) async throws {
        try await PHPhotoLibrary.shared().performChanges(block)
    }

    static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: - Store

@MainActor
@Observable
final class CompressionStore {
    // Scan
    private(set) var items: [LargeMediaItem] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false

    // Fortschritt
    private(set) var isWorking = false
    private(set) var progressText = ""
    private(set) var progressFraction: Double = 0
    var lastMessage: String?

    // IDs bereits komprimierter Dateien, damit sie nicht erneut vorgeschlagen werden
    private var compressedIds: Set<String>
    // Dateien, die sich nicht genug verkleinern ließen (nicht erneut vorschlagen)
    private var skippedIds: Set<String>
    private(set) var stage: WorkStage = .processing

    nonisolated static let photoThreshold: Int64 = 3_000_000    // Mindestgröße Foto (3 MB)
    nonisolated static let videoThreshold: Int64 = 50_000_000   // Mindestgröße Video (50 MB)
    nonisolated static let photoMaxPixel = 3000
    nonisolated static let photoQuality = 0.7
    nonisolated static let minimumSavingsFactor = 0.9
    private nonisolated static let compressedIdsKey = "compression.compressedIds"
    private nonisolated static let skippedIdsKey = "compression.skippedIds"

    init() {
        compressedIds = Set(UserDefaults.standard.stringArray(forKey: Self.compressedIdsKey) ?? [])
        skippedIds = Set(UserDefaults.standard.stringArray(forKey: Self.skippedIdsKey) ?? [])
    }

    private static func availableDiskBytes() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Scan

    func scanIfNeeded(photoService: PhotoLibraryService) {
        guard !hasScanned, !isScanning else { return }
        let all = photoService.fetchAssets(filter: .all)
        guard !all.isEmpty else { return }
        isScanning = true
        let excluded = compressedIds.union(skippedIds)

        Task.detached(priority: .utility) { [store = self] in
            var found: [LargeMediaItem] = []
            for asset in all {
                if let item = CompressionEngine.largeItem(for: asset, excluding: excluded) {
                    found.append(item)
                }
            }
            found.sort { $0.bytes > $1.bytes }
            let result = found
            await store.finishScan(result)
        }
    }

    private func finishScan(_ result: [LargeMediaItem]) {
        items = result
        isScanning = false
        hasScanned = true
    }

    // MARK: Komprimieren

    func compress(_ selected: [LargeMediaItem], photoService: PhotoLibraryService, statsStore: DeletionStatsStore, swipeStore: SwipeStateStore) async {
        guard !isWorking, !selected.isEmpty else { return }
        isWorking = true
        lastMessage = nil
        progressFraction = 0
        stage = .processing
        let startedAt = Date()
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isWorking = false
            progressText = ""
            stage = .processing
            UIApplication.shared.isIdleTimerDisabled = false
        }

        // Speicher-Check: komprimierte Kopien + 1 Original gleichzeitig + Puffer
        let totalBytes = selected.reduce(Int64(0)) { $0 + $1.bytes }
        let largest = selected.map { $0.bytes }.max() ?? 0
        let needed = Int64(Double(totalBytes) * 0.6) + largest + 200_000_000
        if let free = Self.availableDiskBytes(), free < needed {
            lastMessage = "Nicht genug freier Speicher. Für diese Auswahl werden ca. \(compressionByteString(needed)) benötigt, frei sind \(compressionByteString(free)). Wähle weniger Dateien aus."
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheOutCompress-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1) Alle Dateien komprimieren, noch ohne Mediathek-Änderung
        var prepared: [PreparedCompression] = []
        var skipped = 0
        var skippedNowIds: Set<String> = []
        var failed = 0
        var firstError: String?
        for (index, item) in selected.enumerated() {
            progressText = "\(index + 1) von \(selected.count) wird komprimiert …"
            progressFraction = Double(index) / Double(selected.count)
            do {
                if let result = try await CompressionEngine.prepare(assetId: item.id, tempDir: tempDir) {
                    prepared.append(result)
                } else {
                    skipped += 1
                    skippedNowIds.insert(item.id)
                    skippedIds.insert(item.id)
                }
            } catch {
                failed += 1
                print("⚠️ Komprimierung fehlgeschlagen:", error)
                if firstError == nil {
                    let ns = error as NSError
                    firstError = "\(error.localizedDescription) (\(ns.domain) \(ns.code))"
                }
            }
        }
        progressFraction = 1
        UserDefaults.standard.set(Array(skippedIds), forKey: Self.skippedIdsKey)
        items.removeAll { skippedNowIds.contains($0.id) }

        guard !prepared.isEmpty else {
            var text = "Nichts verändert: \(skipped) Datei(en) ließen sich nicht um mindestens 10 % verkleinern"
            if failed > 0 { text += ", \(failed) fehlgeschlagen" }
            text += "."
            if let firstError { text += " Fehler: \(firstError)" }
            lastMessage = text
            return
        }

        // Absichtlich nicht zu schnell, damit der Ablauf nachvollziehbar ist
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 2.5 { try? await Task.sleep(for: .seconds(2.5 - elapsed)) }
        stage = .processed
        progressText = "Komprimiert"
        try? await Task.sleep(for: .seconds(2.2))
        stage = .deleting
        progressText = "Originale werden gelöscht …"

        // 2) Originale und ihre Alben lesen
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: prepared.map { $0.originalId }, options: nil)
        var byId: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in byId[asset.localIdentifier] = asset }

        var albumsById: [String: [PHAssetCollection]] = [:]
        for (id, asset) in byId {
            var list: [PHAssetCollection] = []
            PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
                .enumerateObjects { collection, _, _ in
                    if collection.canPerform(.addContent) { list.append(collection) }
                }
            albumsById[id] = list
        }

        let commitList = prepared.filter { byId[$0.originalId] != nil }

        // 3) EIN atomarer Schritt: komprimierte Kopien anlegen + Originale löschen (ein iOS-Dialog)
        let box = ChangeBox()
        let originalsToDelete = commitList.compactMap { byId[$0.originalId] }
        let assetLookup = byId
        let albumLookup = albumsById
        do {
            try await CompressionEngine.performLibraryChanges {
                for p in commitList {
                    guard let original = assetLookup[p.originalId] else { continue }
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = p.compressedFilename
                    options.shouldMoveFile = true
                    request.addResource(with: p.isVideo ? .video : .photo, fileURL: p.compressedURL, options: options)
                    request.creationDate = original.creationDate
                    request.location = original.location
                    request.isFavorite = original.isFavorite
                    if let placeholder = request.placeholderForCreatedAsset {
                        box.newIds[p.originalId] = placeholder.localIdentifier
                        for collection in albumLookup[p.originalId] ?? [] {
                            PHAssetCollectionChangeRequest(for: collection)?.addAssets([placeholder] as NSArray)
                        }
                    }
                }
                PHAssetChangeRequest.deleteAssets(originalsToDelete as NSArray)
            }
        } catch {
            let ns = error as NSError
            if ns.domain == PHPhotosErrorDomain && ns.code == PHPhotosError.userCancelled.rawValue {
                lastMessage = "Abgebrochen. Es wurde nichts verändert."
            } else {
                lastMessage = "Fehler beim Schreiben in die Mediathek: \(error.localizedDescription)"
            }
            return
        }

        // 4) Erfolg: neue IDs merken, damit sie nicht erneut vorgeschlagen werden
        var savedBytes: Int64 = 0
        var doneCount = 0
        for p in commitList {
            guard let newId = box.newIds[p.originalId] else { continue }
            compressedIds.insert(newId)
            swipeStore.transferState(from: p.originalId, to: newId)
            savedBytes += max(0, p.originalBytes - p.compressedBytes)
            doneCount += 1
        }
        UserDefaults.standard.set(Array(compressedIds), forKey: Self.compressedIdsKey)
        statsStore.recordSavings(bytes: savedBytes)

        let doneIds = Set(commitList.map { $0.originalId })
        items.removeAll { doneIds.contains($0.id) }
        photoService.invalidateLibraryCaches()

        let countText = doneCount == 1 ? "1 Datei" : "\(doneCount) Dateien"
        var message = "\(countText) komprimiert, ca. \(compressionByteString(savedBytes)) gespart. Die Originale liegen 30 Tage in „Zuletzt gelöscht“ (Fotos) und können dort zurückgeholt werden."
        message += " Der Platz wird erst frei, wenn du „Zuletzt gelöscht“ leerst."
        if skipped > 0 { message += " \(skipped) übersprungen (nicht klein genug geworden)." }
        if failed > 0 { message += " \(failed) fehlgeschlagen." + (firstError.map { " Fehler: \($0)" } ?? "") }
        lastMessage = message
    }
}

// MARK: - Abschnitt im Nützliches-Tab

struct CompressionSection: View {
    @Environment(CompressionStore.self) private var store
    @Environment(PhotoLibraryService.self) private var photoService

    @ViewBuilder
    var body: some View {
        if store.isScanning || !store.items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bildkomprimierung")
                    .font(.title2).bold()
                    .padding(.horizontal)

                if store.items.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Große Dateien werden gesucht …")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                    .glassCard()
                    .padding(.horizontal)
                } else {
                    NavigationLink {
                        CompressionGalleryView()
                    } label: {
                        CompressionCollageCard(items: store.items, photoService: photoService)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }
}

// Reine Bild-Collage: Kartendeck in einer Reihe, mit Pfeil als Tipp-Hinweis.
private struct CompressionCollageCard: View {
    let items: [LargeMediaItem]
    let photoService: PhotoLibraryService
    @State private var thumbnails: [UIImage] = []

    private var sample: [LargeMediaItem] { Array(items.prefix(9)) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(hex: "12142B"))

            if thumbnails.isEmpty {
                Image(systemName: "photo.stack")
                    .font(.system(size: 34))
                    .foregroundStyle(.tertiary)
            } else {
                GeometryReader { geo in
                    let count = thumbnails.count
                    let cardW = geo.size.width * 0.30
                    let cardH = geo.size.height * 0.8
                    let step = count > 1 ? min((geo.size.width - 32 - cardW) / CGFloat(count - 1), cardW * 0.55) : 0
                    let startX = (geo.size.width - (cardW + step * CGFloat(max(count - 1, 0)))) / 2 + cardW / 2

                    ZStack {
                        ForEach(Array(thumbnails.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: cardW, height: cardH)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.6), lineWidth: 2.5))
                                .shadow(color: .black.opacity(0.35), radius: 6, x: -3, y: 2)
                                .position(x: startX + step * CGFloat(index), y: geo.size.height / 2)
                                .zIndex(Double(index))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .circle)
                .padding(.trailing, 12)
                .allowsHitTesting(false)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .task(id: sample.map { $0.id }) {
            var result: [UIImage] = []
            for item in sample {
                if let image = await photoService.loadImage(for: item.asset, targetSize: CGSize(width: 300, height: 400)) {
                    result.append(image)
                }
            }
            thumbnails = result
        }
    }
}

// MARK: - Galerie (Mehrfachauswahl)

struct CompressionGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CompressionStore.self) private var store
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(DeletionStatsStore.self) private var statsStore
    @Environment(SwipeStateStore.self) private var swipeStore

    private nonisolated enum Kind: Hashable, Sendable { case photos, videos }
    private enum SortMode { case largest, shuffled }

    @State private var kind: Kind = .photos
    @State private var sortMode: SortMode = .largest
    @State private var shuffleKeys: [String: Double] = [:]
    @State private var selection: Set<String> = []
    @Namespace private var glassNamespace
    @State private var showConfirm = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var photoCount: Int { store.items.filter { !$0.isVideo }.count }
    private var videoCount: Int { store.items.filter { $0.isVideo }.count }

    private var displayItems: [LargeMediaItem] {
        let filtered = store.items.filter { $0.isVideo == (kind == .videos) }
        switch sortMode {
        case .largest:
            return filtered
        case .shuffled:
            return filtered.sorted { (shuffleKeys[$0.id] ?? 0) < (shuffleKeys[$1.id] ?? 0) }
        }
    }

    private var selectedItems: [LargeMediaItem] {
        store.items.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 10)
            hintRow
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
        ScrollView {
            VStack(spacing: 14) {
                if store.isScanning && store.items.isEmpty {
                    ProgressView("Große Dateien werden gesucht …")
                        .padding(.top, 60)
                } else if displayItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(kind == .photos ? "Keine großen Fotos gefunden" : "Keine großen Videos gefunden")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(displayItems) { item in
                            Button {
                                toggle(item)
                            } label: {
                                MediaGridCell(item: item, isSelected: selection.contains(item.id), photoService: photoService)
                            }
                            .buttonStyle(.plain)
                            .assetPeek(asset: item.asset, photoService: photoService) {
                                Button {
                                    toggle(item)
                                } label: {
                                    Label(selection.contains(item.id) ? "Abwählen" : "Auswählen",
                                          systemImage: selection.contains(item.id) ? "circle" : "checkmark.circle")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        }
        .background(AppTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Komprimieren")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .navigationBarBackButtonHidden(store.isWorking)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sortMode = .largest
                    } label: {
                        Label("Größte zuerst", systemImage: "arrow.down.circle")
                    }
                    Button {
                        shuffle()
                    } label: {
                        Label("Zufällig mischen", systemImage: "shuffle")
                    }
                    Divider()
                    Button {
                        let ids = displayItems.map { $0.id }
                        if ids.allSatisfy({ selection.contains($0) }) {
                            selection.subtract(ids)
                        } else {
                            selection.formUnion(ids)
                        }
                    } label: {
                        Label("Alle in dieser Ansicht an/abwählen", systemImage: "checkmark.circle")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.isWorking {
                compressBar
            }
        }
        .overlay {
            if store.isWorking { workingOverlay }
        }
        .alert("\(selectedItems.count) Dateien komprimieren?", isPresented: $showConfirm) {
            Button("Komprimieren") { run() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("CacheOut ersetzt die Originale durch komprimierte Kopien. Danach zeigt iOS einmal eine Löschen-Abfrage – das ist normal. Die Originale bleiben 30 Tage in „Zuletzt gelöscht“ in Fotos und können dort zurückgeholt werden.")
        }
        .alert("Komprimierung", isPresented: Binding(
            get: { store.lastMessage != nil },
            set: { if !$0 { store.lastMessage = nil } }
        )) {
            Button("Fotos öffnen") { openPhotosApp() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastMessage ?? "")
        }
        .onChange(of: store.items) { _, newItems in
            selection.formIntersection(Set(newItems.map { $0.id }))
        }
        .background(
            ScreenAppearanceReporter(
                onAppear: { DeleteBadgeWindowManager.shared.forceHideNow() },
                onDisappear: {}
            )
        )
    }

    // MARK: - Kacheln (wie im Löschen-Sheet)

    private var header: some View {
        HStack(spacing: 12) {
            kindTile(title: "Fotos", icon: "photo.fill", count: photoCount, tint: AppTheme.accent, target: .photos)
            kindTile(title: "Videos", icon: "video.fill", count: videoCount, tint: AppTheme.skipBlue, target: .videos)
        }
    }

    private func kindTile(title: String, icon: String, count: Int, tint: Color, target: Kind) -> some View {
        let isSelected = kind == target

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                kind = target
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassEffect(kindGlassStyle(tint: tint, isSelected: isSelected), in: kindTileShape)
        .overlay {
            if isSelected {
                kindTileShape.stroke(tint.opacity(0.55), lineWidth: 1.5)
            }
        }
        .glassEffectID(target, in: glassNamespace)
    }

    private var kindTileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private func kindGlassStyle(tint: Color, isSelected: Bool) -> Glass {
        guard isSelected else { return .regular.interactive() }
        return .regular.tint(tint.opacity(0.16)).interactive()
    }

    private var hintRow: some View {
        HStack {
            Text(hintText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var hintText: String {
        if selectedItems.isEmpty {
            return "Tippe zum Auswählen"
        }
        return "\(selectedItems.count) ausgewählt · Originale bleiben 30 Tage in „Zuletzt gelöscht“"
    }

    private var selectedBytes: Int64 {
        selectedItems.reduce(Int64(0)) { $0 + $1.bytes }
    }

    // MARK: - Action Bar (wie deleteButton im Löschen-Sheet)

    private var compressBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                run()
            } label: {
                VStack(spacing: 1) {
                    Label("\(selectedItems.count) komprimieren", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.subheadline.weight(.semibold))
                    if selectedBytes > 0 {
                        Text(compressionByteString(selectedBytes))
                            .font(.caption2)
                            .opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .padding(.vertical, 2)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.accent)
            .controlSize(.regular)
            .disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var workingOverlay: some View {
        WorkProgressOverlay(
            stage: store.stage,
            fraction: store.progressFraction,
            text: store.progressText,
            processingTitle: "Komprimieren",
            processedTitle: "Komprimiert",
            deleteTitle: "Danach: alte Originale löschen",
            note: "Die Originale müssen gelöscht werden, sonst würde dein Speicher nicht frei. Sie bleiben 30 Tage in „Zuletzt gelöscht“."
        )
    }

    private func toggle(_ item: LargeMediaItem) {
        withAnimation(.snappy(duration: 0.18)) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        }
    }

    private func shuffle() {
        var keys: [String: Double] = [:]
        for item in store.items { keys[item.id] = Double.random(in: 0...1) }
        shuffleKeys = keys
        sortMode = .shuffled
    }

    private func run() {
        let chosen = selectedItems
        selection.removeAll()
        Task { await store.compress(chosen, photoService: photoService, statsStore: statsStore, swipeStore: swipeStore) }
    }

    private func openPhotosApp() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
    }
}

private struct MediaGridCell: View {
    let item: LargeMediaItem
    let isSelected: Bool
    let photoService: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.06))
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                Text(compressionByteString(item.bytes))
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.white.opacity(0.9))
                    .background(Circle().fill(.black.opacity(isSelected ? 0 : 0.25)))
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if item.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                        Text(compressionDurationString(item.duration))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.accent, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Tap-Fläche exakt auf die Zelle begrenzen (Bild mit .fill ragt sonst in die Nachbarzelle)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .task(id: item.id) {
                image = await photoService.loadImage(for: item.asset, targetSize: CGSize(width: 300, height: 300))
            }
    }
}
