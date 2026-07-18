import Foundation
import UIKit

enum AppLaunchGuard {
    private static let key = "app.launchguard.cleanShutdown"
    private static let crashCountKey = "app.launchguard.dirtyLaunchStreak"

    /// Beim App-Start (in App-Init oder didFinishLaunching) aufrufen.
    /// Gibt zurück, ob der letzte Start "dirty" war (Crash/Force-Kill während aktiver Session).
    @discardableResult
    static func registerLaunchAndCheckDirty() -> Bool {
        let wasClean = UserDefaults.standard.bool(forKey: key)
        // Direkt auf "false" setzen — wird erst bei sauberem Beenden wieder auf true gesetzt.
        UserDefaults.standard.set(false, forKey: key)

        if !wasClean {
            let streak = UserDefaults.standard.integer(forKey: crashCountKey) + 1
            UserDefaults.standard.set(streak, forKey: crashCountKey)
        } else {
            UserDefaults.standard.set(0, forKey: crashCountKey)
        }

        return !wasClean
    }

    /// Aufeinanderfolgende dirty Launches — z.B. ab 2x Safe-Mode erzwingen.
    static var dirtyLaunchStreak: Int {
        UserDefaults.standard.integer(forKey: crashCountKey)
    }

    static func markCleanShutdown() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func observeLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in markCleanShutdown() }

        // Auch beim regulären Backgrounding als "clean" werten,
        // sonst greift der Reset schon beim normalen Home-Button-Druck.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in markCleanShutdown() }
    }
}
