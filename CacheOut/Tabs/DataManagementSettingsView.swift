import SwiftUI

struct DataManagementSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(DeletionStatsStore.self) private var deletionStatsStore
    @Environment(StreakTracker.self) private var streakTracker
    @Environment(AchievementStore.self) private var achievementStore
    @Environment(FileSwipeViewModel.self) private var fileViewModel
    @Environment(NuetzlichesPreviewCache.self) private var nuetzlichesPreviewCache
    @Environment(MeinLebenPreviewCache.self) private var meinLebenPreviewCache
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppSettingsStore.self) private var appSettings

    @State private var showResetConfirm = false
    @State private var isClearingCache = false

    var body: some View {
        @Bindable var appSettings = appSettings

        ScrollView {
            VStack(spacing: 24) {
                SettingsSection(title: "Bisher gelöscht") {
                    StatRow(icon: "photo.fill", iconColor: AppTheme.accent,
                            label: "Fotos", value: "\(deletionStatsStore.totalDeletedPhotos)")
                    Divider().padding(.leading, 52)
                    StatRow(icon: "video.fill", iconColor: .pink,
                            label: "Videos", value: "\(deletionStatsStore.totalDeletedVideos)")
                    Divider().padding(.leading, 52)
                    StatRow(icon: "internaldrive.fill", iconColor: AppTheme.keepGreen,
                            label: "Freigegebener Speicher", value: deletionStatsStore.formattedTotalSize)
                }

                SettingsSection(title: "Speicher & Cache") {
                    Button {
                        guard !isClearingCache else { return }
                        isClearingCache = true
                        nuetzlichesPreviewCache.clearAll()
                        meinLebenPreviewCache.clearAll()
                        Task {
                            await nuetzlichesPreviewCache.preload(photoService: photoService)
                            await meinLebenPreviewCache.preload(photoService: photoService)
                            isClearingCache = false
                        }
                    } label: {
                        SettingsNavRow(icon: isClearingCache ? "arrow.triangle.2.circlepath" : "trash",
                                       iconColor: .secondary,
                                       title: isClearingCache ? "Wird geleert…" : "Vorschau-Cache leeren",
                                       value: nil, showChevron: false)
                    }
                    .disabled(isClearingCache)
                }

                SettingsSection(title: "") {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        SettingsNavRow(icon: "arrow.counterclockwise", iconColor: AppTheme.deleteRed,
                                       title: "Fortschritt zurücksetzen", value: nil, showChevron: false)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Datenverwaltung")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .background(AppTheme.background(colorScheme).ignoresSafeArea())
        .alert("Fortschritt wirklich zurücksetzen?", isPresented: $showResetConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Zurücksetzen", role: .destructive) {
                swipeStore.resetAllProgress()
                deletionStatsStore.resetAll()
                streakTracker.resetAll()
                achievementStore.resetAll()
                fileViewModel.resetAll()
            }
        } message: {
            Text("Alle Swipe-Entscheidungen, Erfolge und Statistiken werden gelöscht. Das kann nicht rückgängig gemacht werden.")
        }
    }
}
