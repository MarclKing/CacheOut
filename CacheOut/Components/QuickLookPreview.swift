import SwiftUI
import QuickLook

// NEU: Subclass, die dem internen ScrollView von QLPreviewController
// Zoom/Pan wegnimmt — dadurch reagiert das Bild NICHT mehr auf Gesten
// direkt drüber, und unsere externe Drag-to-Close-Geste bekommt sie
// zuverlässig immer als einzige.
final class StaticQLPreviewController: QLPreviewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // NEU: QuickLook bekommt komplett KEINE Touches mehr. Dadurch kann
        // nichts mehr am Bild selbst gezogen/gezoomt werden, und unsere
        // eigene Drag-to-Close-Geste (liegt auf der SwiftUI-Ebene darüber)
        // bekommt ausnahmslos jede Berührung ohne Konkurrenz.
        view.isUserInteractionEnabled = false
    }

    // ENTFERNT: viewDidLayoutSubviews + disableZoomAndPan(in:) werden nicht
    // mehr gebraucht — isUserInteractionEnabled = false deckt das komplett ab.
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
        let controller = StaticQLPreviewController()   // GEÄNDERT (war: QLPreviewController())
        controller.dataSource = context.coordinator
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
