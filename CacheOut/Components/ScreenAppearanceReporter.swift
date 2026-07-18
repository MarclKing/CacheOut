import SwiftUI
import UIKit

final class ScreenAppearanceViewController: UIViewController {
    var onAppear: (() -> Void)?
    var onDisappear: (() -> Void)?

    // FIX: viewWillAppear statt viewDidAppear — beide Seiten (Appear/Disappear)
    // feuern früh am Anfang der Transition, wodurch die kritische Lücke zwischen
    // "A verschwindet" und "B erscheint" auf ein Runloop-Fenster reduziert wird.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onAppear?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onDisappear?()
    }
}

// Meldet zuverlässig, wann DIESER Screen wirklich vorne/sichtbar ist —
// im Gegensatz zu SwiftUIs .onAppear/.onDisappear, die bei TabViews
// unzuverlässig für "wirklich sichtbar" sind.
struct ScreenAppearanceReporter: UIViewControllerRepresentable {
    let onAppear: () -> Void
    let onDisappear: () -> Void

    func makeUIViewController(context: Context) -> ScreenAppearanceViewController {
        let vc = ScreenAppearanceViewController()
        vc.onAppear = onAppear
        vc.onDisappear = onDisappear
        return vc
    }

    func updateUIViewController(_ uiViewController: ScreenAppearanceViewController, context: Context) {
        uiViewController.onAppear = onAppear
        uiViewController.onDisappear = onDisappear
    }
}
