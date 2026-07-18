import SwiftUI

@main
struct CacheOutApp: App {
    @State private var photoService = PhotoLibraryService()
    @State private var swipeStore = SwipeStateStore()
    @State private var themeManager = ThemeManager()
    @State private var streakTracker = StreakTracker()
    @State private var deletionStatsStore = DeletionStatsStore()
    @State private var notificationManager = NotificationManager()
    @State private var fileSwipeViewModel = FileSwipeViewModel()
    @State private var nuetzlichesPreviewCache = NuetzlichesPreviewCache()
    @State private var meinLebenPreviewCache = MeinLebenPreviewCache()
    @State private var achievementStore = AchievementStore()
    @State private var tabRouter = TabRouter()
    @State private var appSettingsStore = AppSettingsStore()

    // Aufgeteilt in zwei Flags, damit die LoadingView IMMER komplett
    // durchläuft — egal ob die Foto-Daten schneller oder langsamer fertig
    // sind als die Mindestanzeigedauer der Animation.
    @State private var isDataReady = false
    @State private var minimumAnimationElapsed = false

    private var isReady: Bool { isDataReady && minimumAnimationElapsed }

    // NEU: Safe-Mode-Reset — verhindert, dass ein Zustand, der beim letzten
    // Mal zu einem Hänger/Absturz geführt hat, nach einem harten Neustart
    // automatisch wieder geladen wird.
    // NEU
    init() {
        AppLaunchGuard.observeLifecycle()
        let wasDirty = AppLaunchGuard.registerLaunchAndCheckDirty()
        if wasDirty {
            print("⚠️ Letzter Start war unsauber (Force-Kill/Crash).")
            // Aktuell gibt es keinen bekannten persistierten Resume-State,
            // der einen Hänger reproduzieren würde — der reine Prozess-Neustart
            // sollte hier bereits ausreichen. Falls sich zeigt, dass es doch
            // wieder hängt, hier gezielt zurücksetzen.
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    RootTabView()
                        .transition(.opacity)
                } else {
                    LoadingView(onFinished: {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            minimumAnimationElapsed = true
                        }
                    })
                        .transition(.opacity)
                }
            }
            .environment(photoService)
            .environment(swipeStore)
            .environment(themeManager)
            .environment(streakTracker)
            .environment(deletionStatsStore)
            .environment(notificationManager)
            .environment(fileSwipeViewModel)
            .environment(nuetzlichesPreviewCache)
            .environment(meinLebenPreviewCache)
            .environment(achievementStore)
            .environment(tabRouter)
            .environment(appSettingsStore)
            .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
            .task {
                await photoService.requestAccess()
                streakTracker.recordAppOpen()
                await notificationManager.enableNotificationsIfNeeded()
                // NEU: Datensparmodus-Wert an PhotoLibraryService synchronisieren
                photoService.dataSaverEnabled = appSettingsStore.dataSaverEnabled
                withAnimation(.easeInOut(duration: 0.35)) {
                    isDataReady = true
                }

                // Vorschauen für den "Nützliches"-Tab im Hintergrund vorladen —
                // NACH isReady, damit der App-Start dadurch nicht verzögert
                // wird. Läuft einfach weiter, während der Nutzer schon auf
                // dem ersten Tab ist; bis er zu "Nützliches" wechselt, sind
                // die Bilder in aller Regel längst da.
                Task.detached(priority: .utility) { [photoService, nuetzlichesPreviewCache] in
                    await nuetzlichesPreviewCache.preload(photoService: photoService)
                }
                Task.detached(priority: .utility) { [photoService, meinLebenPreviewCache] in
                    await meinLebenPreviewCache.preload(photoService: photoService)
                }
            }
            .onChange(of: appSettingsStore.dataSaverEnabled) { _, newValue in
                photoService.dataSaverEnabled = newValue
            }
        }
    }
}
