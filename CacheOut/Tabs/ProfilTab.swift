import SwiftUI
import Photos

struct ProfilTab: View {
    @Environment(StreakTracker.self) private var streakTracker
    @Environment(DeletionStatsStore.self) private var deletionStatsStore
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(FileSwipeViewModel.self) private var fileViewModel
    @Environment(AchievementStore.self) private var achievementStore
    // @Environment(MedalStore.self) private var medalStore  // ENTFERNT
    @Environment(TabRouter.self) private var tabRouter

    @State private var showSettings = false
    @State private var totalAssetsCount: Int = 0
    @State private var sortedAssetsCount: Int = 0
    @State private var smartSuggestion: SmartSuggestion?
    @State private var suggestedFilter: PhotoFilter?
    // @State private var showMedalGallery = false  // ENTFERNT
    // @State private var selectedMedal: MedalDisplay?  // ENTFERNT

    private var progressFraction: Double {
        guard totalAssetsCount > 0 else { return 0 }
        return Double(sortedAssetsCount) / Double(totalAssetsCount)
    }

    private var progressPercentText: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }

    private var goalDisplays: [AchievementDisplay] {
        AchievementCatalog.buildGoalDisplays(store: achievementStore, swipeStore: swipeStore, stats: deletionStatsStore, streak: streakTracker)
    }

    // private var medalDisplays: [MedalDisplay] { ... }  // ENTFERNT

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    heroProgressBanner

                    // #1: Streak jetzt als 2. Banner, #2: korrekte Quelle für den Streak-Wert
                    StreakTileRow(currentStreak: swipeStore.currentActivityStreak, dailyActivity: swipeStore.activityLast7Days)

                    if let smartSuggestion {
                        SmartTodoBanner(suggestion: smartSuggestion) {
                            if let filter = smartSuggestion.filter {
                                suggestedFilter = filter
                            } else {
                                tabRouter.selectedTab = 3
                            }
                        }
                    }

                    GoalsGrid(goals: goalDisplays)

                    // MedalChipRow(...)  // ENTFERNT

                    contentTypeRow

                    // #8: Gesamt-Banner statt Wochen-Graph
                    TotalStorageFreedBanner(
                        totalBytes: deletionStatsStore.totalDeletedBytes,
                        totalCount: deletionStatsStore.totalDeletedCount
                    )
                }
                .padding()
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $suggestedFilter) { filter in
                FilterSwipeScreen(title: smartSuggestion?.title ?? "", filter: filter)
            }
            .background(
                ScreenAppearanceReporter(
                    onAppear: { DeleteBadgeWindowManager.shared.forceHideNow() },
                    onDisappear: {}
                )
            )
        }
        // .sheet(isPresented: $showMedalGallery) { ... }  // ENTFERNT
        // .overlay { if let selectedMedal { ... } }  // ENTFERNT
        .onAppear {
            loadProgress()
            // medalStore.update(...)  // ENTFERNT
            Task {
                smartSuggestion = await SmartSuggestionEngine.compute(photoService: photoService, swipeStore: swipeStore, fileViewModel: fileViewModel)
            }
        }
    }

    // MARK: - Hero-Banner (Streak-Badge entfernt)
    private var heroProgressBanner: some View {
        BannerCard(config: BannerConfig(
            style: .hero,
            iconTopGradient: [Color(hex: "9B87F5"), Color(hex: "5B3FE0")],
            iconBottomGradient: [Color(hex: "22D3B6"), Color(hex: "0FA98F")],
            title: "Dein Fortschritt",
            highlight: progressPercentText,
            subtitle: nil,
            footnote: "\(sortedAssetsCount) von \(totalAssetsCount) sortiert",
            progress: progressFraction,
            heroGradient: AppTheme.heroGradient
        ))
    }

    private var contentTypeRow: some View {
        HStack(spacing: 12) {
            ContentTypeTile(icon: "photo.fill", value: deletionStatsStore.totalDeletedPhotos, label: "Fotos", colors: AppTheme.imageGradient)
            ContentTypeTile(icon: "video.fill", value: deletionStatsStore.totalDeletedVideos, label: "Videos", colors: [AppTheme.accent, Color(hex: "5B3FE0")])
            ContentTypeTile(icon: "doc.fill", value: fileViewModel.deletedCount, label: "Dateien", colors: AppTheme.keepGradient)
        }
    }

    private func loadProgress() {
        Task {
            let all = photoService.fetchAssets(filter: .all)
            let sortedCount = all.filter { swipeStore.hasBeenSwiped($0.localIdentifier) }.count
            totalAssetsCount = all.count
            sortedAssetsCount = sortedCount
        }
    }
}

private struct ContentTypeTile: View {
    let icon: String
    let value: Int
    let label: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("\(value)")
                .font(.title3).bold()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassCard()
    }
}
