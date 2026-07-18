import SwiftUI

// Dünner Wrapper — falls FileDeleteConfirmSheet irgendwo noch einzeln
// (ohne Tabs) präsentiert wird, funktioniert das weiterhin unverändert.
struct FileDeleteConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
                    FileDeleteContent(onRequestDismiss: { dismiss() })
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

struct FileDeleteContent: View {
    @Environment(FileSwipeViewModel.self) private var viewModel
    @Environment(DeletionStatsStore.self) private var deletionStatsStore

    var onRequestDismiss: () -> Void
    @Binding var triggerDelete: Bool
    @Binding var triggerRestore: Bool
    var onCountsChange: (Int, Int, Int64) -> Void

    @State private var excludedURLs: Set<URL> = []
    @State private var isDeleting = false

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
            if viewModel.deleteQueue.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(viewModel.deleteQueue, id: \.url) { item in
                        FileThumbnailCell(
                            item: item,
                            isExcluded: excludedURLs.contains(item.url),
                            viewModel: viewModel
                        )
                        .onTapGesture {
                            toggleExclude(item.url)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 100)
            }
        }
        .onChange(of: viewModel.deleteQueue.count) { _, _ in reportCounts() }
        .onChange(of: excludedURLs) { _, _ in reportCounts() }
        .onAppear { reportCounts() }
        .onChange(of: triggerDelete) { _, newValue in
            guard newValue else { return }
            Task { await confirmDelete() }
        }
        .onChange(of: triggerRestore) { _, newValue in
            guard newValue else { return }
            restoreExcluded()
            triggerRestore = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("Keine Dateien zum Löschen vorgemerkt")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }

    private func reportCounts() {
        let remainingItems = viewModel.deleteQueue.filter { !excludedURLs.contains($0.url) }
        let bytes = remainingItems.reduce(Int64(0)) { $0 + $1.size }
        onCountsChange(remainingItems.count, excludedURLs.count, bytes)
    }

    private func toggleExclude(_ url: URL) {
        if excludedURLs.contains(url) {
            excludedURLs.remove(url)
        } else {
            excludedURLs.insert(url)
        }
    }

    private func confirmDelete() async {
        isDeleting = true
        let toDelete = viewModel.deleteQueue.filter { !excludedURLs.contains($0.url) }
        let toRestore = viewModel.deleteQueue.filter { excludedURLs.contains($0.url) }
        let bytesToFree = toDelete.reduce(Int64(0)) { $0 + $1.size }

        for item in toDelete {
            viewModel.confirmQueuedDeletion(item)
        }
        if !toDelete.isEmpty {
            deletionStatsStore.recordDeletion(count: toDelete.count, bytes: bytesToFree)
        }
        for item in toRestore {
            viewModel.restoreQueuedItem(item)
        }

        isDeleting = false
        triggerDelete = false
        onRequestDismiss()
    }

    private func restoreExcluded() {
        let toRestore = viewModel.deleteQueue.filter { excludedURLs.contains($0.url) }
        for item in toRestore {
            viewModel.restoreQueuedItem(item)
        }
        excludedURLs.removeAll()
        reportCounts()
    }
}

private struct FileThumbnailCell: View {
    let item: FileItem
    let isExcluded: Bool
    let viewModel: FileSwipeViewModel

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
            } else {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
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
        .task {
            image = await viewModel.thumbnail(for: item)
        }
    }
}
