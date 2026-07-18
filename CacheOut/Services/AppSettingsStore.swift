import Foundation

// Zentrale, einfache App-weite Schalter — analog zu ThemeManager.
@Observable
class AppSettingsStore {
    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: hapticsKey) }
    }
    var videoAutoplayEnabled: Bool {
        didSet { UserDefaults.standard.set(videoAutoplayEnabled, forKey: videoAutoplayKey) }
    }
    // NEU: Datensparmodus — deaktiviert automatischen iCloud-Download für Fotos
    var dataSaverEnabled: Bool {
        didSet { UserDefaults.standard.set(dataSaverEnabled, forKey: dataSaverKey) }
    }
    // NEU: reduzierte Bewegung beim Swipen — Karte folgt dem Finger nicht mehr
    // live, sondern spielt beim Loslassen nur noch eine feste Animation ab.
    var reducedSwipeMotionEnabled: Bool {
        didSet { UserDefaults.standard.set(reducedSwipeMotionEnabled, forKey: reducedMotionKey) }
    }

    private let hapticsKey = "settings_hapticsEnabled"
    private let videoAutoplayKey = "settings_videoAutoplayEnabled"
    private let dataSaverKey = "settings_dataSaverEnabled"
    private let reducedMotionKey = "settings_reducedSwipeMotionEnabled"

    init() {
        // Haptik & Autoplay: Standard AN, daher object(forKey:)-Check statt
        // bool(forKey:) — sonst würde ein fehlender Key fälschlich als "false" gelesen.
        hapticsEnabled = UserDefaults.standard.object(forKey: hapticsKey) != nil
            ? UserDefaults.standard.bool(forKey: hapticsKey) : true
        videoAutoplayEnabled = UserDefaults.standard.object(forKey: videoAutoplayKey) != nil
            ? UserDefaults.standard.bool(forKey: videoAutoplayKey) : true

        // Datensparmodus & reduzierte Bewegung: Standard AUS
        dataSaverEnabled = UserDefaults.standard.bool(forKey: dataSaverKey)
        reducedSwipeMotionEnabled = UserDefaults.standard.bool(forKey: reducedMotionKey)
    }
}
