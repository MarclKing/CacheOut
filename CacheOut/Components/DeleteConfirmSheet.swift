import SwiftUI
import Photos

// Dünner Wrapper — falls DeleteConfirmSheet irgendwo noch einzeln (ohne
// Tabs) präsentiert wird, funktioniert das weiterhin unverändert.
// Der eigentliche Inhalt lebt jetzt in PhotoDeleteContent, damit
// UnifiedDeleteConfirmSheet ihn ohne doppelte NavigationStack einbetten kann.
struct DeleteConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PhotoDeleteContent(onRequestDismiss: { dismiss() })
                .navigationTitle("Löschen bestätigen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Abbrechen") { dismiss() }
                    }
                }
        }
    }
}

struct PhotoDeleteContent: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(DeletionStatsStore.self) private var deletionStatsStore

    var onRequestDismiss: () -> Void
    @Binding var triggerDelete: Bool
    @Binding var triggerRestore: Bool
    var onCountsChange: (Int, Int, Int64) -> Void

    @State private var assetsToDelete: [PHAsset] = []
    @State private var excludedIds: Set<String> = []
    @State private var isDeleting = false
    @State private var reportTask: Task<Void, Never>?

    init(
        onRequestDismiss: @escaping () -> Void = {},
        triggerDelete: Binding<Bool> = .constant(false),
        triggerRestore: Binding<Bool> = .constant(false),
        onCountsChange: @escaping (Int, Int, Int64) -> Void = { _, _, _ in }
    ) {
        self.onRequestDismiss = onRequestDismiss
        self._triggerDelete = triggerDelete
        self._triggerRestore = triggerRestore
        self.onCountsChange = onCountsChange
    }

    private var columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        ScrollView {
            if assetsToDelete.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(assetsToDelete, id: \.localIdentifier) { asset in
                        ThumbnailCell(
                            asset: asset,
                            isExcluded: excludedIds.contains(asset.localIdentifier),
                            photoService: photoService
                        )
                        .onTapGesture {
                            toggleExclude(asset.localIdentifier)
                        }
                        .assetPeek(asset: asset, photoService: photoService) {
                            Button {
                                toggleExclude(asset.localIdentifier)
                            } label: {
                                Label(excludedIds.contains(asset.localIdentifier) ? "Doch löschen" : "Behalten",
                                      systemImage: excludedIds.contains(asset.localIdentifier) ? "trash" : "arrow.uturn.backward")
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 100)
            }
        }
        .task { loadAssets() }
        .onChange(of: assetsToDelete.count) { _, _ in reportCounts() }
        .onChange(of: excludedIds) { _, _ in reportCounts() }
        .onChange(of: triggerDelete) { _, newValue in
            guard newValue else { return }
            Task { await confirmDelete() }
        }
        .onChange(of: triggerRestore) { _, newValue in
            guard newValue else { return }
            restoreSelected()
            triggerRestore = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("Keine Inhalte zum Löschen vorgemerkt")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }

    private func reportCounts() {
        let remainingAssets = assetsToDelete.filter { !excludedIds.contains($0.localIdentifier) }
        let remainingCount = remainingAssets.count
        let excludedCount = excludedIds.count

        reportTask?.cancel()
        reportTask = Task {
            let bytes = await photoService.totalFileSize(for: remainingAssets)
            guard !Task.isCancelled else { return }
            onCountsChange(remainingCount, excludedCount, bytes)
        }
    }

    private func loadAssets() {
        let ids = swipeStore.deleteQueueIds
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        assetsToDelete = assets
        reportCounts()
    }

    private func toggleExclude(_ id: String) {
        if excludedIds.contains(id) {
            excludedIds.remove(id)
        } else {
            excludedIds.insert(id)
        }
    }

    private func confirmDelete() async {
        isDeleting = true
        let finalAssets = assetsToDelete.filter { !excludedIds.contains($0.localIdentifier) }
        let restoredAssets = assetsToDelete.filter { excludedIds.contains($0.localIdentifier) }
        let bytesToFree = await photoService.totalFileSize(for: finalAssets)
        let photosCount = finalAssets.filter { $0.mediaType == .image }.count
        let videosCount = finalAssets.filter { $0.mediaType == .video }.count

        do {
            try await photoService.deleteAssets(finalAssets)
            deletionStatsStore.recordDeletion(photosCount: photosCount, videosCount: videosCount, bytes: bytesToFree)
            for asset in finalAssets {
                swipeStore.clearFromDeleteQueue(asset.localIdentifier)
            }
            for asset in restoredAssets {
                swipeStore.unmarkAsset(asset.localIdentifier)
            }
        } catch {
            print("Delete error: \(error)")
        }

        isDeleting = false
        triggerDelete = false
        onRequestDismiss()
    }

    private func restoreSelected() {
        let toRestore = assetsToDelete.filter { excludedIds.contains($0.localIdentifier) }
        for asset in toRestore {
            swipeStore.unmarkAsset(asset.localIdentifier)
        }
        assetsToDelete.removeAll { excludedIds.contains($0.localIdentifier) }
        excludedIds.removeAll()
        reportCounts()
    }
}

private struct ThumbnailCell: View {
    let asset: PHAsset
    let isExcluded: Bool
    let photoService: PhotoLibraryService

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(isExcluded ? 0.45 : 1)
            }

            if isExcluded {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.25))
            }

            Circle()
                .fill(isExcluded ? AppTheme.keepGreen : .black.opacity(0.4))
                .frame(width: 20, height: 20)
                .overlay {
                    if isExcluded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(6)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 12))   // Tap-Fläche = Zelle (Bild ragt sonst in Nachbarzelle)
        .task {
            image = await photoService.loadImage(for: asset, targetSize: CGSize(width: 200, height: 200))
        }
    }
}
