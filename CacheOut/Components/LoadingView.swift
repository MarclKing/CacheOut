import SwiftUI

struct LoadingView: View {
    var onFinished: () -> Void

    @State private var isFanned = false
    @State private var glowPulse = false
    @State private var contentAppear = false

    private let minimumDisplayDuration: TimeInterval = 1.8
    private let cardCount = 4

    // Logo-Look: Verlaufsflächen aus deinen bestehenden AppTheme-Gradients
    // statt einzelner Farben — genau wie die Karten im App-Icon.
    private let cardGradients: [[Color]] = [
        AppTheme.imageGradient,
        AppTheme.keepGradient,
        AppTheme.brandGradient,
        AppTheme.heroGradient
    ]
    private let cardIcons = ["photo.fill", "checkmark", "photo.fill", "checkmark"]

    var body: some View {
        ZStack {
            AppTheme.background(.dark).ignoresSafeArea()

            RadialGradient(
                colors: [AppTheme.accent.opacity(glowPulse ? 0.30 : 0.13), .clear],
                center: .center,
                startRadius: 20,
                endRadius: glowPulse ? 250 : 170
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glowPulse)

            VStack(spacing: 44) {
                fanStack
                    .frame(height: 150)

                VStack(spacing: 8) {
                    Text("CacheOut")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Fotos werden vorbereitet …")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .opacity(contentAppear ? 1 : 0)
                .offset(y: contentAppear ? 0 : 8)
                .animation(.easeOut(duration: 0.7).delay(0.15), value: contentAppear)
            }
        }
        .onAppear {
            glowPulse = true
            contentAppear = true
            isFanned = true
        }
        .task {
            try? await Task.sleep(for: .seconds(minimumDisplayDuration))
            onFinished()
        }
    }

    // Unveränderte Fächer-Mechanik: gleiche Rotation, gleicher Offset,
    // gleiches Timing und Delay-Versatz wie in der ursprünglichen Version.
    private var fanStack: some View {
        ZStack {
            ForEach(0..<cardCount, id: \.self) { index in
                card(gradient: cardGradients[index], icon: cardIcons[index])
                    .rotationEffect(.degrees(fanAngle(for: index)))
                    .offset(y: isFanned ? -14 : 0)
                    .animation(
                        .easeInOut(duration: 1.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.07),
                        value: isFanned
                    )
            }
        }
    }

    private func fanAngle(for index: Int) -> Double {
        let centeredIndex = Double(index) - Double(cardCount - 1) / 2
        return centeredIndex * (isFanned ? 24 : 4)
    }

    // Logo-Stil: solide Verlaufsfläche + weißes Icon + Schatten,
    // statt Glass-Karte mit farbigem Rand und farbigem Icon.
    private func card(gradient: [Color], icon: String) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.linearGradient(gradient))
            .frame(width: 82, height: 110)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
    }
}

#Preview {
    LoadingView(onFinished: {})
}
