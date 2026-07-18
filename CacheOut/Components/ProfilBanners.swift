import SwiftUI
import Photos

// MARK: - Smart-Todo-Banner (Modelle/Engine unverändert)

struct SmartSuggestion: Identifiable {
    let id = UUID()
    let count: Int
    let title: String
    let subtitle: String
    let filter: PhotoFilter?
}

enum SmartSuggestionEngine {
    static func compute(photoService: PhotoLibraryService, swipeStore: SwipeStateStore, fileViewModel: FileSwipeViewModel) async -> SmartSuggestion? {
        // Nutzt jetzt den gecachten, einmalig gruppierten Bestand statt pro Jahr
        // einen eigenen fetchAssets(.yearAll(year))-Fetch auszulösen.
        let assetsByYear = photoService.assetsGroupedByYear()
        var bestYear: (year: Int, unswiped: Int)?

        for (year, assets) in assetsByYear {
            let unswiped = assets.filter { !swipeStore.hasBeenSwiped($0.localIdentifier) }.count
            if unswiped > 0, unswiped > (bestYear?.unswiped ?? 0) {
                bestYear = (year, unswiped)
            }
        }

        if let bestYear, bestYear.unswiped > 20 {
            return SmartSuggestion(
                count: bestYear.unswiped,
                title: "Fotos aus \(bestYear.year)",
                subtitle: "noch nicht sortiert",
                filter: .yearAll(bestYear.year)
            )
        }

        if fileViewModel.remainingFiles.count > 0 {
            return SmartSuggestion(
                count: fileViewModel.remainingFiles.count,
                title: "Dateien im letzten Ordner",
                subtitle: "warten noch",
                filter: nil
            )
        }

        return nil
    }
}

// NEU: Redesign — feste Kreis-Badge für die Zahl statt riesiger, abschneidender
// Zahl. minimumScaleFactor sorgt dafür, dass auch 4-stellige Zahlen nie mehr
// abgeschnitten werden. Neuer Verlauf (Teal -> Navy), damit sich das Banner
// klar vom violetten Hero-Banner absetzt.
struct SmartTodoBanner: View {
    let suggestion: SmartSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Text("\(suggestion.count)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.subheadline).bold()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(suggestion.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color(hex: "0FA98F"), Color(hex: "1B2A6B")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streak: kleine quadratische Kacheln statt Balken

// NEU: Ersetzt StreakRibbonBanner komplett. Zeigt 7 kleine Kacheln für die
// letzten 7 Tage, mit echtem Wochentags-Buchstaben (aus dem Kalender berechnet,
// nicht mehr "Mo Di Mi..." fix ab Montag). Aktive Tage sind gefüllt/farbig,
// inaktive nur ein dezenter Rahmen. Heute wird zusätzlich umrandet.
struct StreakTileRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let currentStreak: Int
    let dailyActivity: [Int]   // 7 Werte, ältester zuerst, letzter = heute

    private var last7Dates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { calendar.date(byAdding: .day, value: -(6 - $0), to: today)! }
    }

    private func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(currentStreak) Tage Streak")
                    .font(.subheadline).bold()
                    .foregroundStyle(Color.primary)
            }

            HStack(spacing: 10) {
                ForEach(Array(last7Dates.enumerated()), id: \.offset) { index, date in
                    let isActive = index < dailyActivity.count ? dailyActivity[index] > 0 : false
                    let isToday = Calendar.current.isDateInToday(date)

                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                isActive
                                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "FF9142"), Color(hex: "FF5F6D")], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                            )
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(isActive ? .white : Color.primary.opacity(0.2))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(isToday ? 0.6 : 0), lineWidth: 1.5)
                            )

                        Text(weekdayLetter(for: date))
                            .font(.caption2)
                            .foregroundStyle(isToday ? Color.primary.opacity(0.9) : Color.secondary.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 24))
    }
}

// NEU: ersetzt StorageTrendBanner als letzten Banner
struct TotalStorageFreedBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let totalBytes: Int64
    let totalCount: Int

    private var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: AppTheme.keepGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedTotal)
                    .font(.title3).bold()
                    .foregroundStyle(Color.primary)
                Text("insgesamt freigemacht · \(totalCount) Elemente")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(AppTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 24))
    }
}
