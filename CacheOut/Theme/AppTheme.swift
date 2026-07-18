import SwiftUI

enum AppTheme {
    // MARK: - Basisfarben
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "05060F") : Color(hex: "F5F5F7")
    }

    static let deleteRed = Color(hex: "FF453A")           // bleibt Systemrot (iOS-Konvention für destruktiv)
    static let keepGreen = Color(hex: "22D3B6")           // NEU: Logo-Türkis statt Systemgrün
    static let accent = Color(hex: "7C5CFF")              // NEU: Logo-Violett statt Blau
    static let skipBlue = Color(hex: "3D7FE0")            // NEU: alter Blauton, jetzt für "Überspringen" reserviert

    // MARK: - Markenverläufe (aus dem App-Icon abgeleitet)
    // Violett: für alles rund um Fotos/Bild-Inhalte (Karten, Icon-Stacks, Progress-Ringe)
    static let imageGradient: [Color] = [Color(hex: "9B87F5"), Color(hex: "7C5CFF"), Color(hex: "5B3FE0")]
    
    // Türkis: für "erledigt/behalten/befreiter Speicher" — der Haken aus dem Icon
    static let keepGradient: [Color] = [Color(hex: "5DCAA5"), Color(hex: "0FA98F")]
    
    // Kombiniert: für Ringe, Progress-Balken, alles was beide Markenfarben verbinden soll
    static let brandGradient: [Color] = [Color(hex: "7C5CFF"), Color(hex: "22D3B6")]
    
    // Hintergrund für Hero-Banner (dunkler Verlauf, unabhängig vom Farbschema)
    static let heroGradient: [Color] = [Color(hex: "5B3FE0"), Color(hex: "1A1454")]

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "12142B") : Color.white   // leicht violett statt neutralem Grau
    }

    // Kuratierte Verläufe für die Jahres-Banner in "Mein Leben" — deterministisch
    // pro Jahr gewählt (kein Zufall bei jedem Render), bleibt aber innerhalb der Markenfarben.
    private static let yearGradients: [[Color]] = [
        [Color(hex: "5B3FE0"), Color(hex: "9B87F5")],
        [Color(hex: "0F6E56"), Color(hex: "22D3B6")],
        [Color(hex: "3C3489"), Color(hex: "7C5CFF")],
        [Color(hex: "085041"), Color(hex: "5DCAA5")],
        [Color(hex: "26215C"), Color(hex: "534AB7")]
    ]

    static func yearGradient(for year: Int) -> [Color] {
        yearGradients[abs(year) % yearGradients.count]
    }

    static func linearGradient(_ colors: [Color], _ start: UnitPoint = .topLeading, _ end: UnitPoint = .bottomTrailing) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: start, endPoint: end)
    }

    // MARK: - Glass Helper (zentral, damit überall der gleiche Look)
    static func glassCard() -> some ViewModifier {
        GlassCardModifier()
    }
}

private struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// Zentraler Store für App-weites Theme (hell/dunkel, Standard = dunkel)
@Observable
class ThemeManager {
    let isDarkMode = true
}

