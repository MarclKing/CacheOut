import SwiftUI
import Photos
import AVKit

// MARK: - Große Vorschau beim langen Drücken (Peek)

struct AssetPeekView: View {
    let asset: PHAsset
    let photoService: PhotoLibraryService
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    private var size: CGSize {
        let ratio: CGFloat = asset.pixelHeight > 0 ? CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight) : 1
        let maxW: CGFloat = 340
        let maxH: CGFloat = 520
        var w = maxW
        var h = maxW / ratio
        if h > maxH { h = maxH; w = maxH * ratio }
        return CGSize(width: w, height: h)
    }

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            if let player {
                VideoPlayer(player: player)
            } else if image == nil {
                ProgressView().tint(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        image = await photoService.loadImage(for: asset, targetSize: CGSize(width: 1200, height: 1200))
        guard asset.mediaType == .video else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                guard player == nil else { return }
                let p = AVPlayer(playerItem: item)
                p.isMuted = true
                p.play()
                player = p
            }
        }
    }
}

extension View {
    /// Langes Drücken zeigt das Medium groß (Foto oder Video) plus ein kleines Menü.
    func assetPeek<M: View>(asset: PHAsset, photoService: PhotoLibraryService, @ViewBuilder menu: () -> M) -> some View {
        contextMenu(menuItems: menu, preview: {
            AssetPeekView(asset: asset, photoService: photoService)
        })
    }
}

// MARK: - Glas-Kachel (Umschalter wie im Löschen-Sheet)

struct GlassSegmentTile<ID: Hashable & Sendable>: View {
    let title: String
    let icon: String
    let count: Int
    let tint: Color
    let isSelected: Bool
    let tileID: ID
    let namespace: Namespace.ID
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var glass: Glass {
        isSelected ? .regular.tint(tint.opacity(0.16)).interactive() : .regular.interactive()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: shape)
        .overlay {
            if isSelected {
                shape.stroke(tint.opacity(0.55), lineWidth: 1.5)
            }
        }
        .glassEffectID(tileID, in: namespace)
    }
}

// MARK: - Mehrstufiger Fortschritt (Bearbeiten → Fertig → Originale löschen)

nonisolated enum WorkStage: Int, Sendable {
    case processing   // Dateien werden bearbeitet
    case processed    // fertig, nächster Schritt wird erklärt
    case deleting     // Originale löschen / iOS-Abfrage
}

struct WorkProgressOverlay: View {
    let stage: WorkStage
    let fraction: Double
    let text: String
    let processingTitle: String
    let processedTitle: String
    let deleteTitle: String
    let note: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    stepIcon(done: stage != .processing, active: stage == .processing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stage == .processing ? processingTitle : processedTitle)
                            .font(.headline)
                        if stage == .processing {
                            ProgressView(value: fraction)
                                .tint(.white)
                            Text(text)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Divider().overlay(.white.opacity(0.2))

                HStack(alignment: .top, spacing: 12) {
                    stepIcon(done: false, active: stage == .deleting)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deleteTitle)
                            .font(.headline)
                            .opacity(stage == .processing ? 0.5 : 1)
                        if stage != .processing {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(stage == .deleting ? "Bestätige gleich die iOS-Abfrage" : "Bitte die App geöffnet lassen")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: 330)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, .dark)
            .animation(.snappy, value: stage)
        }
    }

    @ViewBuilder
    private func stepIcon(done: Bool, active: Bool) -> some View {
        ZStack {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if active {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "circle").foregroundStyle(.white.opacity(0.4))
            }
        }
        .font(.system(size: 22))
        .frame(width: 28, height: 28)
    }
}
