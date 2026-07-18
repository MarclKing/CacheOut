import SwiftUI
import UniformTypeIdentifiers

// Reiner Anzeige-Baustein, jetzt full-bleed wie die Foto-Karte —
// keine eigene Metadaten-Leiste mehr, die läuft als Chip-Overlay
// zentral über FileSwipeTab (identisch zum sizeChip beim Foto-Swipe).
struct FileCardView: View {
    let item: FileItem
    let thumbnail: UIImage?
    var onRetryDownload: (() -> Void)? = nil   // NEU: nil auf der nicht-interaktiven "next"-Karte
    var isAutoDownloadEnabled: Bool = true   // NEU: steuert, ob .needsDownload als "lädt" oder "antippen" angezeigt wird
    var onOpenPreview: (() -> Void)? = nil   // NEU: nil auf der nicht-interaktiven "next"-Karte, wie onRetryDownload

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {   // NEU: Doppeltipp öffnet die Preview, analog zu SwipeDeckView
                            onOpenPreview?()
                        }
                } else {
                    // NEU: solide Basis statt nur transluzentem Material —
                    // verhindert Durchscheinen der nextContent-Karte dahinter.
                    Rectangle()
                        .fill(Color.black)
                        .overlay(Rectangle().fill(.ultraThinMaterial))
                        .overlay(fallbackIcon)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                // NEU: bei .needsDownload unterscheiden, ob automatisch geladen wird
                // (Spinner) oder der Nutzer selbst antippen muss (Download-Prompt)
                if item.iCloudStatus == .needsDownload {
                    if isAutoDownloadEnabled {
                        downloadOverlay
                    } else {
                        manualDownloadOverlay
                    }
                } else if item.iCloudStatus == .downloadFailed {
                    downloadFailedOverlay
                }
            }
        }
    }

    private var fallbackIcon: some View {
        VStack(spacing: 12) {
            Image(systemName: systemIcon(for: item.contentType))
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var downloadOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text("Wird heruntergeladen…")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
    }

    // NEU: aktiv antippbarer Hinweis statt Endlos-Spinner, wenn Auto-Download
    // in den Settings deaktiviert ist — Datei liegt noch in iCloud, wartet
    // auf bewusste Nutzer-Aktion statt automatisch zu laden
    private var manualDownloadOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                Text("In iCloud — zum Herunterladen antippen")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onRetryDownload?() }
    }

    private var downloadFailedOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise.icloud")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                Text("Download fehlgeschlagen — antippen zum Wiederholen")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onRetryDownload?() }
    }

    private func systemIcon(for type: UTType?) -> String {
        guard let type else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .movie) { return "play.rectangle" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .zip) || type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
