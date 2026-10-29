import SwiftUI
import Photos

// MARK: - Modelle

nonisolated struct DuplicateGroup: Identifiable, Hashable, @unchecked Sendable {
    let id: String               // localIdentifier des Hauptbilds
    let main: PHAsset            // bleibt erhalten
    let duplicates: [PHAsset]    // Kopien
    let isVideo: Bool
    let bytesPerItem: Int64

    var all: [PHAsset] { [main] + duplicates }

    static func == (lhs: DuplicateGroup, rhs: DuplicateGroup) -> Bool {
        lhs.id == rhs.id && lhs.duplicates.count == rhs.duplicates.count
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct MergePlan: @unchecked Sendable {
    let main: PHAsset
    let albums: [PHAssetCollection]
    let makeFavorite: Bool
}

// MARK: - Engine

nonisolated enum DuplicateEngine {

    /// Exakte Kopien: gleiche Aufnahmezeit (Sekunde), gleiche Maße/Dauer UND gleiche Dateigröße.
    static func findGroups(in assets: [PHAsset]) -> [DuplicateGroup] {
        var buckets: [String: [PHAsset]] = [:]
        for asset in assets {
            guard asset.mediaType == .image || asset.mediaType == .video,
                  let date = asset.creationDate else { continue }
            let key = "\(asset.mediaType.rawValue)|\(Int(date.timeIntervalSince1970))|\(asset.pixelWidth)x\(asset.pixelHeight)|\(Int(asset.duration.rounded()))"
            buckets[key, default: []].append(asset)
        }

        var groups: [DuplicateGroup] = []
        for (_, bucket) in buckets where bucket.count > 1 {
            var bySize: [Int64: [PHAsset]] = [:]
            for asset in bucket {
                let size = primarySize(of: asset)
                guard size > 0 else { continue }
                bySize[size, default: []].append(asset)
            }
            for (size, same) in bySize where same.count > 1 {
                let ordered = same.sorted { mainOrder($0, $1) }
                groups.append(DuplicateGroup(
                    id: ordered[0].localIdentifier,
                    main: ordered[0],
                    duplicates: Array(ordered.dropFirst()),
                    isVideo: ordered[0].mediaType == .video,
                    bytesPerItem: size
                ))
            }
        }
        return groups
    }

    // Hauptbild: Favorit zuerst, sonst die älteste Änderung
    private static func mainOrder(_ a: PHAsset, _ b: PHAsset) -> Bool {
        if a.isFavorite != b.isFavorite { return a.isFavorite }
        let ad = a.modificationDate ?? .distantFuture
        let bd = b.modificationDate ?? .distantFuture
        if ad != bd { return ad < bd }
        return a.localIdentifier < b.localIdentifier
    }

    private static func primarySize(of asset: PHAsset) -> Int64 {
        let isVideo = asset.mediaType == .video
        let resources = PHAssetResource.assetResources(for: asset)
        guard let r = resources.first(where: { $0.type == (isVideo ? .video : .photo) }) else { return 0 }
        return (r.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }
}

// MARK: - Store

@MainActor
@Observable
final class DuplicateStore {
    private(set) var groups: [DuplicateGroup] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false

    private(set) var isWorking = false
    private(set) var stage: WorkStage = .processing
    private(set) var progressText = ""
    private(set) var progressFraction: Double = 0
    var lastMessage: String?

    var duplicateCount: Int { groups.reduce(0) { $0 + $1.duplicates.count } }

    func scanIfNeeded(photoService: PhotoLibraryService) {
        guard !hasScanned, !isScanning else { return }
        let all = photoService.fetchAssets(filter: .all)
        guard !all.isEmpty else { return }
        isScanning = true

        Task.detached(priority: .utility) { [store = self] in
            let found = DuplicateEngine.findGroups(in: all).shuffled()
            let result = found
            await store.finishScan(result)
        }
    }

    private func finishScan(_ result: [DuplicateGroup]) {
        groups = result
        isScanning = false
        hasScanned = true
    }

    func merge(_ selectedIds: Set<String>, photoService: PhotoLibraryService) async {
        guard !isWorking, !selectedIds.isEmpty else { return }
        isWorking = true
        lastMessage = nil
        stage = .processing
        progressFraction = 0
        progressText = "Duplikate werden geprüft …"
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isWorking = false
            stage = .processing
            progressText = ""
            UIApplication.shared.isIdleTimerDisabled = false
        }
        let startedAt = Date()

        var plans: [MergePlan] = []
        var toDelete: [PHAsset] = []
        var removedIds: Set<String> = []
        var freedBytes: Int64 = 0

        let affected = groups.filter { group in
            group.duplicates.contains(where: { selectedIds.contains($0.localIdentifier) })
        }

        for (index, group) in affected.enumerated() {
            progressFraction = Double(index) / Double(max(affected.count, 1))
            progressText = "\(index + 1) von \(affected.count) wird zusammengefasst …"

            let dups = group.duplicates.filter { selectedIds.contains($0.localIdentifier) }

            // Alben, in denen das Hauptbild schon liegt
            var mainAlbumIds = Set<String>()
            PHAssetCollection.fetchAssetCollectionsContaining(group.main, with: .album, options: nil)
                .enumerateObjects { collection, _, _ in mainAlbumIds.insert(collection.localIdentifier) }

            // Alben der Kopien, die das Hauptbild noch bekommen soll
            var albums: [String: PHAssetCollection] = [:]
            for dup in dups {
                PHAssetCollection.fetchAssetCollectionsContaining(dup, with: .album, options: nil)
                    .enumerateObjects { collection, _, _ in
                        if !mainAlbumIds.contains(collection.localIdentifier), collection.canPerform(.addContent) {
                            albums[collection.localIdentifier] = collection
                        }
                    }
            }

            let anyFavorite = dups.contains(where: { $0.isFavorite })
            plans.append(MergePlan(main: group.main, albums: Array(albums.values), makeFavorite: !group.main.isFavorite && anyFavorite))
            toDelete.append(contentsOf: dups)
            for dup in dups { removedIds.insert(dup.localIdentifier) }
            freedBytes += group.bytesPerItem * Int64(dups.count)
        }
        progressFraction = 1

        // Absichtlich nicht zu schnell, damit der Ablauf nachvollziehbar ist
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 2.0 { try? await Task.sleep(for: .seconds(2.0 - elapsed)) }
        stage = .processed
        progressText = "Zusammengefasst"
        try? await Task.sleep(for: .seconds(2.2))
        stage = .deleting
        progressText = "Überzählige Kopien werden gelöscht …"

        let plansCopy = plans
        let deleteCopy = toDelete
        do {
            try await CompressionEngine.performLibraryChanges {
                for plan in plansCopy {
                    if plan.makeFavorite {
                        PHAssetChangeRequest(for: plan.main).isFavorite = true
                    }
                    for collection in plan.albums {
                        PHAssetCollectionChangeRequest(for: collection)?.addAssets([plan.main] as NSArray)
                    }
                }
                PHAssetChangeRequest.deleteAssets(deleteCopy as NSArray)
            }
        } catch {
            let ns = error as NSError
            if ns.domain == PHPhotosErrorDomain && ns.code == PHPhotosError.userCancelled.rawValue {
                lastMessage = "Abgebrochen. Es wurde nichts verändert."
            } else {
                lastMessage = "Fehler beim Zusammenfassen: \(error.localizedDescription)"
            }
            return
        }

        groups = groups.compactMap { group in
            let rest = group.duplicates.filter { !removedIds.contains($0.localIdentifier) }
            guard !rest.isEmpty else { return nil }
            return DuplicateGroup(id: group.id, main: group.main, duplicates: rest, isVideo: group.isVideo, bytesPerItem: group.bytesPerItem)
        }
        photoService.invalidateLibraryCaches()

        let countText = removedIds.count == 1 ? "1 Duplikat" : "\(removedIds.count) Duplikate"
        lastMessage = "\(countText) zusammengefasst, ca. \(compressionByteString(freedBytes)) frei. Die Kopien liegen 30 Tage in „Zuletzt gelöscht“ (Fotos). Der Platz wird frei, wenn du dort leerst."
    }
}

// MARK: - Kachel für den Nützliches-Tab

struct DuplicateTile: View {
    let store: DuplicateStore
    let photoService: PhotoLibraryService
    @State private var previewImage: UIImage?

    private var countText: String {
        if store.isScanning && store.groups.isEmpty { return "…" }
        return store.duplicateCount > 0 ? "\(store.duplicateCount)" : "—"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            if let previewImage {
                GeometryReader { geo in
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                LinearGradient(
                    colors: [.black.opacity(0.7), .black.opacity(0.0)],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                        .padding(8)
                        .background(
                            Circle().fill(previewImage == nil ? AppTheme.accent.opacity(0.15) : .white.opacity(0.2))
                        )
                    Spacer()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplikate")
                        .font(.subheadline).bold()
                        .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                        .lineLimit(1)
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(previewImage == nil ? Color.secondary : Color.white.opacity(0.8))
                }
            }
            .padding(12)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task(id: store.groups.first?.id) {
            guard let main = store.groups.first?.main else { previewImage = nil; return }
            previewImage = await photoService.loadImage(for: main, targetSize: CGSize(width: 300, height: 300))
        }
    }
}

// MARK: - Duplikate-Seite (Design wie Löschen-Sheet)

struct DuplicateGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(DuplicateStore.self) private var store
    @Environment(PhotoLibraryService.self) private var photoService

    private nonisolated enum Kind: Hashable, Sendable { case photos, videos }

    @State private var kind: Kind = .photos
    @State private var selection: Set<String> = []   // localIdentifier der markierten Kopien
    @Namespace private var glassNamespace

    private var displayGroups: [DuplicateGroup] {
        store.groups.filter { $0.isVideo == (kind == .videos) }
    }
    private var photoCount: Int {
        store.groups.filter { !$0.isVideo }.reduce(0) { $0 + $1.duplicates.count }
    }
    private var videoCount: Int {
        store.groups.filter { $0.isVideo }.reduce(0) { $0 + $1.duplicates.count }
    }
    private var selectedBytes: Int64 {
        store.groups.reduce(Int64(0)) { sum, group in
            let n = group.duplicates.filter { selection.contains($0.localIdentifier) }.count
            return sum + group.bytesPerItem * Int64(n)
        }
    }
    private var allIds: [String] {
        displayGroups.flatMap { $0.duplicates.map { $0.localIdentifier } }
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
                LazyVStack(alignment: .leading, spacing: 18) {
                    if store.isScanning && store.groups.isEmpty {
                        ProgressView("Duplikate werden gesucht …")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if displayGroups.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(kind == .photos ? "Keine doppelten Fotos gefunden" : "Keine doppelten Videos gefunden")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(displayGroups) { group in
                            groupRow(group)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(AppTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Duplikate")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .navigationBarBackButtonHidden(store.isWorking)
        .toolbar {
            if !displayGroups.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allIds.allSatisfy({ selection.contains($0) }) ? "Keine" : "Alle") {
                        if allIds.allSatisfy({ selection.contains($0) }) {
                            selection.subtract(allIds)
                        } else {
                            selection.formUnion(allIds)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !store.isWorking {
                mergeBar
            }
        }
        .overlay {
            if store.isWorking {
                WorkProgressOverlay(
                    stage: store.stage,
                    fraction: store.progressFraction,
                    text: store.progressText,
                    processingTitle: "Zusammenfassen",
                    processedTitle: "Zusammengefasst",
                    deleteTitle: "Danach: überzählige Kopien löschen",
                    note: "Das Hauptbild bleibt mit allen Alben erhalten. Die Kopien müssen gelöscht werden, sonst würde dein Speicher nicht frei. Sie bleiben 30 Tage in „Zuletzt gelöscht“."
                )
            }
        }
        .alert("Duplikate", isPresented: Binding(
            get: { store.lastMessage != nil },
            set: { if !$0 { store.lastMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastMessage ?? "")
        }
        .background(
            ScreenAppearanceReporter(
                onAppear: { DeleteBadgeWindowManager.shared.forceHideNow() },
                onDisappear: {}
            )
        )
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 12) {
            GlassSegmentTile(title: "Fotos", icon: "photo.fill", count: photoCount, tint: AppTheme.accent,
                             isSelected: kind == .photos, tileID: Kind.photos, namespace: glassNamespace) {
                withAnimation(.easeInOut(duration: 0.2)) { kind = .photos }
            }
            GlassSegmentTile(title: "Videos", icon: "video.fill", count: videoCount, tint: AppTheme.skipBlue,
                             isSelected: kind == .videos, tileID: Kind.videos, namespace: glassNamespace) {
                withAnimation(.easeInOut(duration: 0.2)) { kind = .videos }
            }
        }
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
        if selection.isEmpty {
            return "Tippe aufs Hauptbild, um alle Kopien zu markieren"
        }
        return "\(selection.count) ausgewählt · Hauptbild bleibt erhalten"
    }

    // MARK: Gruppen-Reihe

    private func groupRow(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(group.all.count) Kopien · je \(compressionByteString(group.bytesPerItem))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(group.all.enumerated()), id: \.element.localIdentifier) { index, asset in
                        Button {
                            tap(asset: asset, index: index, in: group)
                        } label: {
                            DuplicateCell(
                                asset: asset,
                                isMain: index == 0,
                                isSelected: isSelected(asset, index: index, in: group),
                                photoService: photoService
                            )
                        }
                        .buttonStyle(.plain)
                        .assetPeek(asset: asset, photoService: photoService) {
                            Button {
                                tap(asset: asset, index: index, in: group)
                            } label: {
                                Label(index == 0 ? "Alle Kopien markieren" : (selection.contains(asset.localIdentifier) ? "Abwählen" : "Auswählen"),
                                      systemImage: "checkmark.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func tap(asset: PHAsset, index: Int, in group: DuplicateGroup) {
        withAnimation(.snappy(duration: 0.18)) {
            if index == 0 {
                let ids = group.duplicates.map { $0.localIdentifier }
                if ids.allSatisfy({ selection.contains($0) }) {
                    selection.subtract(ids)
                } else {
                    selection.formUnion(ids)
                }
            } else {
                let id = asset.localIdentifier
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            }
        }
    }

    private func isSelected(_ asset: PHAsset, index: Int, in group: DuplicateGroup) -> Bool {
        if index == 0 {
            return group.duplicates.allSatisfy { selection.contains($0.localIdentifier) }
        }
        return selection.contains(asset.localIdentifier)
    }

    // MARK: Aktionsleiste

    private var mergeBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                run()
            } label: {
                VStack(spacing: 1) {
                    Label("\(selection.count) zusammenfassen", systemImage: "square.on.square")
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
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func run() {
        let ids = selection
        selection.removeAll()
        Task { await store.merge(ids, photoService: photoService) }
    }
}

private struct DuplicateCell: View {
    let asset: PHAsset
    let isMain: Bool
    let isSelected: Bool
    let photoService: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .frame(width: 124, height: 124)
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
            .overlay(alignment: .bottomLeading) {
                if isMain {
                    Label("Hauptbild", systemImage: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.keepGreen, in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if asset.mediaType == .video {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !isMain {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? AppTheme.deleteRed : Color.white.opacity(0.9))
                        .background(Circle().fill(.black.opacity(isSelected ? 0 : 0.25)))
                        .padding(6)
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isMain ? AppTheme.keepGreen : AppTheme.deleteRed, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .task(id: asset.localIdentifier) {
                image = await photoService.loadImage(for: asset, targetSize: CGSize(width: 300, height: 300))
            }
    }
}
