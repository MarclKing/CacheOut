import SwiftUI
import UniformTypeIdentifiers

// Dünner Wrapper um UIDocumentPickerViewController für die Ordnerauswahl.
// Liefert die gewählte URL über onPick zurück; um das Security-Scoped-
// Bookmark kümmert sich der Aufrufer (FileSwipeViewModel.openFolder).
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                    guard let url = urls.first else { return }
                    // FIX: Zugriff muss HIER gestartet werden, bevor openFolder()
                    // daraus ein Bookmark baut — sonst ist das Bookmark ungültig
                    // bzw. verliert den Scope, sobald dieser Callback endet.
                    // Gestoppt wird er zentral in FileSwipeViewModel bei Ordnerwechsel.
                    guard url.startAccessingSecurityScopedResource() else { return }
                    onPick(url)
                }
    }
}
