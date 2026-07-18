import Foundation
import AVFoundation
import Observation

@Observable
class VideoPlayerManager {
    var player: AVPlayer?
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying: Bool = true
    var isMuted: Bool = false
    var rate: Float = 1.0
    var isScrubbing: Bool = false   // verhindert Konflikt zwischen Slider-Drag und Zeit-Observer
    var didFinishPlaying: Bool = false   // NEU: Signal für Videoende

    private var timeObserver: Any?
    private var didFinishObserver: NSObjectProtocol?   // NEU: Observer für Videoende

    // NEU: Instagram-artiges Verhalten — Standard richtet sich nach dem
    // Stumm-Schalter des Geräts (AVAudioSession-Kategorie .ambient respektiert
    // ihn automatisch, ganz ohne dass wir den Schalter selbst auslesen müssen).
    // Sobald der Nutzer die Hardware-Lautstärke-Taste drückt, wird auf
    // .playback umgeschaltet, was den Stumm-Schalter ignoriert -> Ton an.
    private var volumeObserver: NSKeyValueObservation?
    private var didOverrideSilentSwitch = false

    // NEU: verhindert, dass Callbacks aus einem alten load()-Zyklus
    // (Seek-Completion, Duration-Task, Time-Observer) auf einen inzwischen
    // ersetzten Player/Item einwirken.
    private var generation = 0

    // NEU: Sicherheitsnetz, falls die View verschwindet, ohne dass
    // onDisappear/cleanup() rechtzeitig ausgeführt wird.
    deinit {
        cleanup()
    }

    private var durationTask: Task<Void, Never>?

    func load(playerItem item: AVPlayerItem, autoplay: Bool = true) {
        // NEU: PHImageManager kann bei schnell aufeinanderfolgenden Requests für
        // dasselbe Video DASSELBE AVPlayerItem-Objekt zurückgeben. Vergleich daher
        // über das zugrundeliegende Asset, nicht über die Item-Instanz.
        if player?.currentItem?.asset === item.asset {
            isPlaying = true
            player?.play()
            return
        }

        cleanup()
        generation += 1
        let currentGeneration = generation

        if !didOverrideSilentSwitch {
            configureAudioSession(respectingSilentSwitch: true)
        }
        startObservingHardwareVolume()

        // NEU: Niemals das übergebene Item direkt verwenden — es könnte bereits
        // (oder gleichzeitig) einem anderen AVPlayer zugewiesen sein/werden, weil
        // PhotoKit dasselbe Objekt für wiederholte Requests zwischenspeichert.
        // Ein frisches AVPlayerItem auf Basis desselben Assets zu erzeugen ist
        // billig und macht die Instanz eindeutig diesem einen Player zuordenbar.
        let safeItem = AVPlayerItem(asset: item.asset)

        let newPlayer = AVPlayer(playerItem: safeItem)
        player = newPlayer
        rate = 1.0
        isPlaying = autoplay
        isMuted = false
        didFinishPlaying = false
        newPlayer.isMuted = false

        didFinishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: safeItem,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isPlaying = false
            self.didFinishPlaying = true
        }

        durationTask?.cancel()
        durationTask = Task {
            if let loadedDuration = try? await safeItem.asset.load(.duration) {
                await MainActor.run {
                    guard self.generation == currentGeneration else { return }
                    self.duration = loadedDuration.seconds
                }
            }
        }

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            self.currentTime = time.seconds
        }

        if autoplay {
            newPlayer.play()
        }
    }

    // NEU: Replay-Funktion — springt zum Anfang und spielt ab
    func replay() {
        didFinishPlaying = false
        isPlaying = true
        player?.seek(to: .zero)
        player?.play()
    }

    // NEU: .ambient = Ton folgt dem Hardware-Stumm-Schalter automatisch.
    // .playback = ignoriert den Stumm-Schalter (wird nach Lautstärke-Tastendruck gesetzt).
    private func configureAudioSession(respectingSilentSwitch: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if respectingSilentSwitch {
                try session.setCategory(.ambient, options: [.mixWithOthers])
            } else {
                try session.setCategory(.playback, options: [])
            }
            try session.setActive(true)
        } catch {
            print("VideoPlayerManager: AudioSession-Fehler: \(error)")
        }
    }

    // NEU: beobachtet die System-Lautstärke (ändert sich nur, wenn der Nutzer
    // die physischen Lautstärke-Tasten drückt).
    private func startObservingHardwareVolume() {
        guard volumeObserver == nil else { return }
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleHardwareVolumeButtonPressed()
            }
        }
    }

    // NEU: Lautstärke-Taste gedrückt -> Stumm-Schalter ab jetzt ignorieren,
    // Ton fest einschalten (bleibt so für die Rest der Session).
    private func handleHardwareVolumeButtonPressed() {
        guard !didOverrideSilentSwitch else { return }
        didOverrideSilentSwitch = true
        configureAudioSession(respectingSilentSwitch: false)
        isMuted = false
        player?.isMuted = false
    }

    func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            player?.rate = rate
        } else {
            player?.pause()
        }
    }

    private var pendingSeekTime: CMTime?
    private var isSeekInProgress = false

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        // Direktes Feedback im UI, auch während der Seek noch läuft
        currentTime = seconds

        pendingSeekTime = time
        guard !isSeekInProgress else { return }   // läuft schon einer, dieser übernimmt den neuesten Wert
        performPendingSeek()
    }

    private func performPendingSeek() {
        guard let time = pendingSeekTime else { return }
        pendingSeekTime = nil
        isSeekInProgress = true

        // Toleranz .zero = exaktes Frame statt Sprung zum nächsten Keyframe
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.isSeekInProgress = false
            // Falls währenddessen weiter gezogen wurde, direkt den nächsten Seek nachschieben
            if self.pendingSeekTime != nil {
                self.performPendingSeek()
            }
        }
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player?.rate = newRate }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func cleanup() {
        generation += 1   // NEU: veraltete Callbacks stumm schalten
        durationTask?.cancel()   // NEU
        durationTask = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        // NEU: Volume-Observer mit aufräumen, sonst hängt er über die
        // Lebenszeit der Karte hinaus weiter am AVAudioSession-KVO.
        volumeObserver?.invalidate()
        volumeObserver = nil

        // NEU: DidFinish-Observer entfernen
        if let didFinishObserver {
            NotificationCenter.default.removeObserver(didFinishObserver)
            self.didFinishObserver = nil
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentTime = 0
        duration = 0
        didFinishPlaying = false   // NEU: Reset
    }
}
