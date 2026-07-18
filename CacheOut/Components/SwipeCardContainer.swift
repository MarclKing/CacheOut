import SwiftUI

struct SwipeCardContainer<Content: View, NextContent: View>: View {
    let content: Content
    let nextContent: NextContent
    let onKeep: () -> Void
    let onDelete: () -> Void
    let onSkip: () -> Void
    let onSwipeUp: () -> Void   // NEU

    @Binding var externalTrigger: SwipeAction?
    // isZoomed raus

    @State private var dragOffset: CGSize = .zero
    @State private var hapticFired = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    @Environment(AppSettingsStore.self) private var settings   // NEU

    init(
        externalTrigger: Binding<SwipeAction?> = .constant(nil),
        onKeep: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onSwipeUp: @escaping () -> Void,   // NEU
        @ViewBuilder content: () -> Content,
        @ViewBuilder nextContent: () -> NextContent = { EmptyView() }
    ) {
        self._externalTrigger = externalTrigger
        self.onKeep = onKeep
        self.onDelete = onDelete
        self.onSkip = onSkip
        self.onSwipeUp = onSwipeUp   // NEU
        self.content = content()
        self.nextContent = nextContent()
    }

    private var dragProgressX: Double {
        Double(max(-1, min(1, dragOffset.width / 140)))
    }
    private var dragProgressY: Double {
        Double(max(0, min(1, dragOffset.height / 140)))
    }

    // NEU: 0...1 — wie weit die obere Karte gerade gezogen wird. Steuert,
    // wie stark die darunterliegende (nächste) Karte schon "aufgedeckt" wird.
    // Divisor 160 bewusst kleiner als bei den Feedback-Icons (140-Schwelle),
    // damit die nächste Karte ungefähr dann voll sichtbar ist, wenn der
    // Swipe kurz vorm Auslösen steht.
    private var dragMagnitude: Double {
        let x = Double(dragOffset.width / 160)
        let y = Double(dragOffset.height / 160)
        return min(1, (x * x + y * y).squareRoot())
    }
    private var nextCardScale: CGFloat { 0.92 + 0.08 * dragMagnitude }
    private var nextCardOpacity: Double { 0.55 + 0.45 * dragMagnitude }

    var body: some View {
        ZStack {
            // NEU: garantiert blickdichte Basis GANZ unten im Stack — unabhängig
            // von jeglichem Layout-/Async-Timing sofort da (kein GeometryReader,
            // kein State nötig). Verhindert, dass beim Karten-Wechsel für einen
            // Frame die neu gemountete nextContent (Vorschau der übernächsten
            // Karte) sichtbar wird, bevor die neue content-Karte (v.a. Video,
            // die einen GeometryReader-Layoutpass braucht) gerendert hat.
            Color.black

            // NEU: nächste Karte liegt fix darunter, leicht kleiner/dezenter.
            // Wird nicht angefasst (allowsHitTesting false), reagiert nur
            // passiv auf den Drag der oberen Karte.
            nextContent
                .scaleEffect(nextCardScale)
                .opacity(nextCardOpacity)
                .allowsHitTesting(false)

            content
                .overlay(feedbackOverlay)
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if settings.reducedSwipeMotionEnabled {
                                // NEU: Karte bleibt liegen, kein Live-Follow —
                                // dadurch auch kein laufendes Neuskalieren/
                                // Blurren der nächsten Karte während des Ziehens.
                                handleThresholdHaptic(translation: value.translation)
                            } else {
                                dragOffset = value.translation
                                handleThresholdHaptic(translation: dragOffset)
                            }
                        }
                        .onEnded(handleDragEnd)
                )
        }
        .onChange(of: externalTrigger) { _, newValue in
            guard let action = newValue else { return }
            trigger(action)
        }
    }

    private var feedbackOverlay: some View {
        let progressX = dragProgressX
        let keepIntensity = max(0, progressX)
        let deleteIntensity = max(0, -progressX)
        let horizontalDominance = max(keepIntensity, deleteIntensity)

        let rawSkip = dragProgressY
        let skipIntensity: Double = {
            guard rawSkip > 0.12 else { return 0 }
            guard rawSkip > horizontalDominance * 1.4 else { return 0 }
            return rawSkip
        }()

        return GeometryReader { geo in
            ZStack {
                feedbackIcon(systemName: "heart.fill", color: AppTheme.keepGreen, intensity: keepIntensity)
                    .position(x: geo.size.width * 0.22, y: geo.size.height * 0.22)

                feedbackIcon(systemName: "xmark", color: AppTheme.deleteRed, intensity: deleteIntensity)
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.22)

                feedbackIcon(systemName: "arrow.down.circle.fill", color: AppTheme.skipBlue, intensity: skipIntensity)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.22)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func feedbackIcon(systemName: String, color: Color, intensity: Double) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 84, weight: .bold))
            .foregroundStyle(color)
            .scaleEffect(0.4 + intensity * 0.8)
            .opacity(min(1, intensity * 1.7))
            .shadow(color: .black.opacity(0.25), radius: 8)
    }

    private func handleThresholdHaptic(translation: CGSize) {
        guard settings.hapticsEnabled else { return }
        let crossed = abs(translation.width) > 120 || (translation.height > 120 && translation.height > abs(translation.width))
        if crossed && !hapticFired {
            feedbackGenerator.impactOccurred()
            hapticFired = true
        } else if !crossed {
            hapticFired = false
        }
    }

    private func handleDragEnd(value: DragGesture.Value) {
        let threshold: CGFloat = 120
        let swipeUpThreshold: CGFloat = 60            // NEU: eigene, kleinere Schwelle nur für "nach oben"
        hapticFired = false
        let h = value.translation.width
        let v = value.translation.height
        let predictedV = value.predictedEndTranslation.height   // NEU: schneller Flick zählt auch ohne volle Strecke

        // NEU: löst schon bei 60pt aus ODER bei einem schnellen Flick
        // (Schwung nach oben über die normale Schwelle hinaus vorhergesagt)
        let isSwipeUp = (v < -swipeUpThreshold || predictedV < -threshold) && abs(v) > abs(h)

        if v > threshold && v > abs(h) {
            animateOut(CGSize(width: 0, height: 700), then: onSkip)
        } else if h < -threshold {
            animateOut(CGSize(width: -600, height: 0), then: onDelete)
        } else if h > threshold {
            animateOut(CGSize(width: 600, height: 0), then: onKeep)
        } else if isSwipeUp {                          // GEÄNDERT (war: v < -threshold && abs(v) > abs(h))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = .zero }
            onSwipeUp()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = .zero }
        }
    }

    private func trigger(_ action: SwipeAction) {
        switch action {
        case .delete:
            animateOut(CGSize(width: -600, height: 0), then: onDelete)
        case .keep:
            animateOut(CGSize(width: 600, height: 0), then: onKeep)
        case .skip:
            animateOut(CGSize(width: 0, height: 700), then: onSkip)
        }
        externalTrigger = nil
    }

    private func animateOut(_ target: CGSize, then action: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.35)) { dragOffset = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                action()
                dragOffset = .zero
            }
        }
    }
}
