import SwiftUI
import Photos
import AVFoundation
import UIKit

struct VideoCardView: View {
    let asset: PHAsset
    let cornerRadius: CGFloat
    var bottomInset: CGFloat = 152   // Erhöht für Abstand zur Chip-Oberkante
    var preloadedItem: AVPlayerItem? = nil   // NEU: von SwipeDeckView vorab angefragtes Item

    @Environment(\.displayScale) private var displayScale   // NEU
    @Environment(AppSettingsStore.self) private var settings   // NEU

    @State private var manager = VideoPlayerManager()

    // NEU: Standbild (Poster) statt Schwarz/Blur während des Ladens — bleibt
    // dauerhaft im ZStack UNTER dem Player liegen (auch nachdem player != nil
    // ist), damit der kurze Moment zwischen "AVPlayer existiert" und "erster
    // Frame ist tatsächlich decodiert" ebenfalls überbrückt wird, statt kurz
    // schwarz durchzuscheinen.
    @State private var posterImage: UIImage?

    // NEU: init seedet posterImage SOFORT aus dem in SwipeDeckView bereits
    // vorab geladenen Thumbnail (currentImage/nextImage — die werden dort für
    // JEDEN Asset-Typ geladen, auch Videos). Dadurch ist beim allerersten
    // Render bereits ein Bild da — keine eigene Async-Anfrage mehr nötig, die
    // (egal wie schnell) immer eine kurze schwarze Lücke verursacht.
    init(asset: PHAsset, cornerRadius: CGFloat, bottomInset: CGFloat = 152,
         preloadedItem: AVPlayerItem? = nil, preloadedPosterImage: UIImage? = nil) {
        self.asset = asset
        self.cornerRadius = cornerRadius
        self.bottomInset = bottomInset
        self.preloadedItem = preloadedItem
        _posterImage = State(initialValue: preloadedPosterImage)
    }

    // Nur unten rund, wie bei den Fotos — oben bleibt eckig (passend zu
    // SwipeDeckView.cardShape). Muss HIER intern schon so passieren, nicht
    // nur über den äußeren .clipShape() in SwipeDeckView — sonst rundet dieser
    // RoundedRectangle-Clip hier alle 4 Ecken ab, und an den oberen Ecken
    // entstehen Lücken, weil zwei überlappende Clip-Formen mit
    // unterschiedlicher Eckenlogik aufeinandertreffen.
    private var videoShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0
        )
    }

    // Steuert Ein-/Ausblenden des Play/Pause- + Mute-Overlays
    @State private var showControls = false
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // NEU: Poster liegt permanent im Hintergrund — solange er da ist,
                // deckt er sowohl die Ladephase als auch den kurzen
                // Player-Aufwärm-Moment blickdicht ab, ohne dass zwischendurch
                // Schwarz aufblitzt.
                if let posterImage {
                    Image(uiImage: posterImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .clipShape(videoShape)
                }

                if let player = manager.player {
                    VideoLayerView(player: player)
                        .clipShape(videoShape)
                        .contentShape(Rectangle())
                        .onTapGesture { handleTap() }
                } else if posterImage == nil {
                    // NEU: keine eigene Schwarz+Blur-Dimmung mehr — die
                    // Karte hat in SwipeDeckView (cardView) bereits einen
                    // schwarzen Hintergrund. Eine zusätzliche Dimmschicht
                    // hier, die nur für den kurzen Ladeaugenblick auftaucht
                    // und dann wieder verschwindet, war genau das
                    // Flackern. Jetzt nur noch der reine Ladekreis.
                    ProgressView()
                        .tint(.white)
                }

                if manager.player != nil {
                    // Mittiges Overlay wie bei Instagram — kleiner Mute-Button
                    // oben, darunter der große Play/Pause-Button. Blendet sich beim
                    // Tippen kurz ein (bleibt sichtbar, solange pausiert ist).
                    centerOverlay

                    // Hauchdünne Fortschrittsleiste über der Icon-Leiste,
                    // statt der alten Bedienleiste mit Slider/Speed-Menü.
                    VStack {
                        Spacer()
                        progressBar
                            .padding(.horizontal, 14)
                            .padding(.bottom, bottomInset)
                    }
                }
            }
            .task {
                // NEU: loadPosterIfNeeded() greift nur noch als Fallback — wenn
                // preloadedPosterImage im init schon gesetzt wurde, ist
                // posterImage bereits ab dem allerersten Render da, und der
                // guard (posterImage == nil) in loadPosterIfNeeded überspringt
                // die eigene Anfrage komplett. Poster wird mit der ECHTEN
                // Kartengröße angefragt (statt einer geratenen Zielgröße) —
                // damit PHImageManager beim .aspectFill-Zuschnitt exakt
                // denselben Bildausschnitt wählt, den AVPlayerLayer später mit
                // .resizeAspectFill für dieselbe Framegröße verwendet.
                loadPosterIfNeeded(cardSize: geo.size)
                await loadVideo()
            }
            .onDisappear { manager.cleanup() }
            .onChange(of: manager.didFinishPlaying) { _, finished in
                if finished { revealControls() }
            }
        }
    }

    private var centerOverlay: some View {
        VStack(spacing: 14) {
            if !manager.didFinishPlaying {
                Button {
                    manager.toggleMute()
                    revealControls()
                } label: {
                    Image(systemName: manager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.42), in: Circle())
                }
            }

            Button {
                handleTap()
            } label: {
                Image(systemName: manager.didFinishPlaying ? "arrow.clockwise" : (manager.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.42), in: Circle())
            }
        }
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: showControls)
    }

    // Sehr dünne Leiste im Instagram-Stil: heller Grundstrich + weißer
    // Fortschrittsbalken, der proportional zur Abspielzeit wächst.
    // Mit Drag-to-Seek: größere Trefferzone (20pt) für bessere Bedienbarkeit
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * progressFraction, height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        manager.isScrubbing = true
                        let fraction = min(max(0, value.location.x / geo.size.width), 1)
                        manager.seek(to: fraction * manager.duration)
                    }
                    .onEnded { value in
                        let fraction = min(max(0, value.location.x / geo.size.width), 1)
                        manager.seek(to: fraction * manager.duration)
                        manager.isScrubbing = false
                    }
            )
        }
        .frame(height: 20)   // größere Wisch-Fläche statt 2pt Trefferzone
    }

    private var progressFraction: CGFloat {
        guard manager.duration > 0 else { return 0 }
        return CGFloat(manager.currentTime / manager.duration)
    }

    private func handleTap() {
        if manager.didFinishPlaying {
            manager.replay()
        } else {
            manager.togglePlayPause()
        }
        revealControls()
    }

    // Blendet Play/Pause + Mute kurz ein. Bei laufendem Video nach ~0,6s
    // wieder ausblenden; bei Pause sichtbar lassen, bis erneut getippt wird.
    private func revealControls() {
        hideWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { showControls = true }

        guard manager.isPlaying else { return }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) { showControls = false }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    // NEU: schnelles Vorschaubild (repräsentiert i.d.R. den ersten/einen
    // frühen Frame) via PHImageManager — läuft parallel zu loadVideo() und
    // ist normalerweise deutlich schneller da (auch aus dem Photos-Cache),
    // damit sofort etwas Sinnvolles zu sehen ist statt Schwarz.
    // cardSize = echte Kartengröße (Points), damit der .aspectFill-Zuschnitt
    // von PHImageManager zum späteren .resizeAspectFill von AVPlayerLayer passt.
    private func loadPosterIfNeeded(cardSize: CGSize) {
        guard posterImage == nil, cardSize.width > 0, cardSize.height > 0 else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let scale = displayScale
        let targetSize = CGSize(width: cardSize.width * scale, height: cardSize.height * scale)

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                posterImage = image
            }
        }
    }

    private func loadVideo() async {
        // NEU: falls SwipeDeckView das Item schon vorbereitet hat, direkt
        // verwenden — kein erneuter requestPlayerItem-Roundtrip, kein Warten.
        if let preloadedItem {
            await MainActor.run {
                manager.load(playerItem: preloadedItem, autoplay: settings.videoAutoplayEnabled)
                if !settings.videoAutoplayEnabled { revealControls() }
            }
            return
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.version = .current

        // requestPlayerItem statt requestAVAsset: funktioniert zuverlässig auch bei
        // Zeitlupe/Live-Photo-Videos & iCloud-Assets, die kein AVURLAsset liefern
        // (genau das führte vorher zum kaputten Platzhalter)
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                continuation.resume(returning: playerItem)
            }
        }

        guard let item else { return }
        await MainActor.run {
            manager.load(playerItem: item, autoplay: settings.videoAutoplayEnabled)
            if !settings.videoAutoplayEnabled { revealControls() }
        }
    }
}
