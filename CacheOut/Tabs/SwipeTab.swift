import SwiftUI
import Photos

struct SwipeTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore

    @State private var assets: [PHAsset] = []
    @State private var showDeleteSheet = false
    @State private var isLoadingAssets = false

    var body: some View {
            // NEU: eigener NavigationStack als Tab-Root — dadurch gibt's automatisch
            // KEINEN nativen Zurück-Button (nichts im Stack zum Zurückgehen), aber
            // dieselbe native Löschen-Toolbar wie auf allen anderen Screens.
            NavigationStack {
                ZStack {
                    AppTheme.background(colorScheme).ignoresSafeArea()
                    if isLoadingAssets {
                        ProgressView().tint(.white)
                    } else {
                        SwipeDeckView(
                            assets: assets,
                            photoService: photoService,
                            swipeStore: swipeStore
                        )
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
            }
            .sheet(isPresented: $showDeleteSheet) {
                UnifiedDeleteConfirmSheet()
            }
            .onAppear {
                loadAssets()
            }
        }

    private func loadAssets() {
        guard assets.isEmpty else { return }
        isLoadingAssets = true
        Task.detached(priority: .userInitiated) {
            let loaded = await photoService.shuffledAllAssets()
            await MainActor.run {
                assets = loaded
                isLoadingAssets = false
            }
        }
    }
}

#Preview {
    SwipeTab()
        .environment(PhotoLibraryService())
        .environment(SwipeStateStore())
}
