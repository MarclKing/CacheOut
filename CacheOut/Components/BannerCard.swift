import SwiftUI

// MARK: - Banner Konfiguration
// Ein Config-Objekt pro Banner-Instanz -> beliebig oft wiederverwendbar,
// z.B. Speicher-Fortschritt in "Mein Leben", freigegebener Speicherplatz
// im Dateien-Tab, tägliche Zusammenfassung etc.
struct BannerConfig {
    enum Style {
        case hero          // großes Banner mit Verlaufshintergrund + Icon-Stack
        case progressRow   // schmales Banner mit Fortschrittsbalken
        case statusRow      // schmales Banner mit Haken/Status
    }

    var style: Style
    var iconTopGradient: [Color]
    var iconBottomGradient: [Color]
    var title: String
    var highlight: String?      // z.B. "75%"
    var subtitle: String?
    var footnote: String?       // z.B. "15.870 von 21.000 Elementen"
    var progress: Double?       // 0...1, nil = kein Balken
    var heroGradient: [Color] = [Color(hex: "5B3FE0"), Color(hex: "1A1454")]
}

// MARK: - Universelle Banner-View
struct BannerCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let config: BannerConfig

    var body: some View {
        switch config.style {
        case .hero: heroBanner
        case .progressRow: progressRowBanner
        case .statusRow: statusRowBanner
        }
    }

    // MARK: Hero — bewusst immer dunkler Verlauf, deshalb fest weißer Text
    // (unabhängig vom System-Farbschema, wie Apples eigene Promo-Banner)
    private var heroBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(config.title)
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)

                if let highlight = config.highlight {
                    Text(highlight)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                }

                if let subtitle = config.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let footnote = config.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 4)
                }
            }
            Spacer()
            heroProgressRing
        }
        .padding(20)
        .background(
            LinearGradient(colors: config.heroGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Ring ersetzt den linearen Balken im Hero-Banner — Fortschritt
    // und Icon-Stack sitzen jetzt kombiniert an derselben Stelle.
    private var heroProgressRing: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 6)
            if let progress = config.progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AppTheme.keepGreen, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            iconStack(scale: 1.0)
        }
        .frame(width: 70, height: 70)
    }

    // MARK: Progress Row — sitzt auf .ultraThinMaterial, darum adaptiver Text
    // (Color.primary/.secondary statt .white -> bleibt in Light Mode lesbar)
    private var progressRowBanner: some View {
        HStack(spacing: 14) {
            iconStack(scale: 0.62)

            VStack(alignment: .leading, spacing: 6) {
                Text(config.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)

                if let progress = config.progress {
                    gradientProgressBar(progress: progress)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Status Row — z.B. "X GB freigemacht" mit Haken
    private var statusRowBanner: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "trash")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.keepGreen)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(config.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)

                if let progress = config.progress {
                    gradientProgressBar(progress: progress)
                }
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption).bold()
                .foregroundStyle(AppTheme.keepGreen)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Verlauf statt einfarbigem Tint — nutzt dieselben Farben wie
    // der Icon-Stack, damit Balken & Icon zusammenpassen.
    private func gradientProgressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(
                        colors: config.iconTopGradient + config.iconBottomGradient,
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: max(3, geo.size.width * progress))
            }
        }
        .frame(height: 4)
    }

    // MARK: Icon-Stack (die zwei versetzten Karten aus dem Logo-Motiv)
    private func iconStack(scale: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(LinearGradient(colors: config.iconTopGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 44 * scale, height: 56 * scale)
                .rotationEffect(.degrees(-8))
                .offset(x: -8 * scale, y: 4 * scale)
                .shadow(color: (config.iconTopGradient.first ?? .clear).opacity(0.5), radius: 8 * scale)

            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(LinearGradient(colors: config.iconBottomGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 44 * scale, height: 56 * scale)
                .rotationEffect(.degrees(6))
                .shadow(color: (config.iconBottomGradient.first ?? .clear).opacity(0.5), radius: 8 * scale)
        }
        .frame(width: 70 * scale, height: 70 * scale)
    }
}

// MARK: - Beispiel-Instanzen (einfach nach Bedarf ergänzen)
extension BannerConfig {
    static let scanProgress = BannerConfig(
        style: .hero,
        iconTopGradient: [Color(hex: "9B87F5"), Color(hex: "5B3FE0")],
        iconBottomGradient: [Color(hex: "22D3B6"), Color(hex: "0FA98F")],
        title: "Großartige Arbeit!",
        highlight: "75%",
        subtitle: "deines Speichers überprüft",
        footnote: "15.870 von 21.000 Elementen",
        progress: 0.75
    )

    static let todayScanned = BannerConfig(
        style: .progressRow,
        iconTopGradient: [Color(hex: "9B87F5"), Color(hex: "5B3FE0")],
        iconBottomGradient: [Color(hex: "22D3B6"), Color(hex: "0FA98F")],
        title: "Heute: 245 Elemente überprüft",
        highlight: nil,
        subtitle: nil,
        footnote: nil,
        progress: 0.4
    )

    static let freedSpace = BannerConfig(
        style: .statusRow,
        iconTopGradient: [Color(hex: "5DCAA5"), Color(hex: "0FA98F")],
        iconBottomGradient: [Color(hex: "22D3B6"), Color(hex: "0FA98F")],
        title: "3,12 GB freigemacht",
        highlight: nil,
        subtitle: nil,
        footnote: nil,
        progress: 0.8
    )
}

#Preview {
    VStack(spacing: 16) {
        BannerCard(config: .scanProgress)
        BannerCard(config: .todayScanned)
        BannerCard(config: .freedSpace)
    }
    .padding()
    .background(AppTheme.background(.dark))
}
