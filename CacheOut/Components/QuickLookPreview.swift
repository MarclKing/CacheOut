import SwiftUI
import QuickLook

// Subclass, die QuickLooks eigenes Panning (in jede Richtung) komplett
// unterbindet, aber Pinch-to-Zoom bewusst intakt lässt — und die eigene
// Anzeige erst freigibt, sobald sich QuickLooks internes Layout beruhigt
// hat, um den Neupositionierungs-Jump nach dem Öffnen unsichtbar zu machen.
final class StaticQLPreviewController: QLPreviewController {

    private var revealWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        // NEU: erst unsichtbar — wird erst gezeigt, sobald das Layout sich
        // beruhigt hat (siehe scheduleReveal). Der SwiftUI-Platzhalter
        // dahinter bleibt in der Zwischenzeit sichtbar.
        view.alpha = 0
        lockDownViewHierarchy()
    }

    // QuickLook fügt seine echten Content-Views (ScrollView, Gesten,
    // Bild-Container) teils erst NACH dem ersten Layout-Pass ein bzw.
    // verändert Zoom/Position dabei noch mehrfach — exakt der Moment des
    // sichtbaren Jumps. Ein einmaliges Anwenden reicht deshalb nicht, wir
    // müssen bei JEDEM Layout-Pass neu durchgehen.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        lockDownViewHierarchy()
        scheduleReveal()
    }

    private func lockDownViewHierarchy() {
        applyRecursively(to: view)
    }

    private func applyRecursively(to view: UIView) {
        view.backgroundColor = .clear

        if let scrollView = view as? UIScrollView {
            scrollView.bounces = false
        }

        // NEU: nicht nur scrollView.panGestureRecognizer, sondern JEDEN
        // Pan-Recognizer in der Hierarchie deaktivieren — QuickLook nutzt
        // fürs Verschieben während des Zoomens teils eigene Pan-Recognizer,
        // die nicht direkt an einer UIScrollView hängen. Pinch bleibt
        // unangetastet, Zoomen funktioniert also weiterhin.
        view.gestureRecognizers?.forEach { recognizer in
            if let pan = recognizer as? UIPanGestureRecognizer {
                pan.isEnabled = false
            }
        }

        for subview in view.subviews {
            applyRecursively(to: subview)
        }
    }

    // NEU: Debounce fürs Einblenden. Jeder neue Layout-Pass verwirft den
    // vorherigen geplanten Reveal und plant ihn neu — erst wenn QuickLook
    // für 0.1s keine weitere Neupositionierung mehr auslöst, wird die View
    // sichtbar. So verpasst der Nutzer den Sprung unabhängig davon, wie oft
    // QuickLook intern noch nachjustiert.
    private func scheduleReveal() {
        revealWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.12) {
                self.view.alpha = 1
            }
        }
        revealWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}

// Kleiner Wrapper, damit eine beliebige Datei-URL als QLPreviewItem
// durchgereicht werden kann — QuickLook kann so ziemlich jeden
// Dateityp anzeigen (PDF, Bilder, Videos, Office-Dokumente, Text…).
final class QuickLookItem: NSObject, QLPreviewItem, Identifiable {
    let id = UUID()
    let url: URL
    init(url: URL) { self.url = url }
    var previewItemURL: URL? { url }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let item: QuickLookItem

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = StaticQLPreviewController()
        controller.dataSource = context.coordinator
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let item: QuickLookItem
        init(item: QuickLookItem) { self.item = item }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { item }
    }
}
