import Foundation
import UniformTypeIdentifiers

// Ein Eintrag im Wisch-Deck. Bewusst als struct + Equatable, damit
// SwiftUI-Diffing (onChange, ForEach) günstig bleibt.
struct FileItem: Identifiable, Equatable {
    let id: URL           // die URL ist innerhalb eines Ordners eindeutig
    let url: URL          // WICHTIG: immer standardizedFileURL, siehe FileScanner —
                          // sonst matchen /var- und /private/var-Varianten derselben
                          // Datei nicht als gleich (URL-Vergleich, nicht Equatable-Bug)
    let name: String
    let size: Int64
    let modifiedDate: Date?
    let contentType: UTType?
    let iCloudStatus: ICloudStatus

    enum ICloudStatus: Equatable {
        case localOnly
        case downloaded
        case needsDownload
        case downloadFailed
    }
}
