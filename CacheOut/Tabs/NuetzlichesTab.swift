import SwiftUI
import Photos

struct DayMemory: Identifiable, Hashable {
    let offset: Int
    let referenceDate: Date
    let day: Int
    let month: Int
    var id: Int { offset }
}

struct SmartFilterSelection: Identifiable, Hashable {
    let title: String
    let filter: PhotoFilter
    var id: String { title }
}

struct NuetzlichesTab: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(NuetzlichesPreviewCache.self) private var previewCache

    @State private var showDeleteSheet = false
    @State private var selectedDayOffset = 0
    @State private var selectedFilter: SmartFilterSelection?
    @State private var selectedDayMemory: DayMemory?

    // Beide Listen kommen jetzt aus dem Cache, damit App-Start-Preload
    // und Anzeige garantiert dieselben Einträge/Keys verwenden.
    private var dayMemories: [DayMemory] { NuetzlichesPreviewCache.dayMemories }
    private var smartFilters: [SmartFilterSelection] { NuetzlichesPreviewCache.smartFilters }

    private let smartFilterIcons: [String: String] = [
        "Videos": "video.fill",
        "Screenshots": "camera.viewfinder",
        "Letzte 7 Tage": "calendar.badge.clock",
        "Letzte 31 Tage": "calendar",
        "Favoriten": "star.fill",
        "Fotos": "photo.fill",
        "Live Fotos": "livephoto",
        "Porträts": "person.crop.rectangle"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    memoriesSection
                    todayBanner
                    smartFilterSection
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .navigationTitle("Nützliches")
            .navigationBarTitleDisplayMode(.inline)
            .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
            .navigationDestination(item: $selectedFilter) { selection in
                FilterSwipeScreen(title: selection.title, filter: selection.filter)
            }
            .navigationDestination(item: $selectedDayMemory) { memory in
                FilterSwipeScreen(
                    title: dayLabel(for: memory),
                    filter: .dayAcrossYears(day: memory.day, month: memory.month),
                    pairedDateStyle: .yearOnly   // NEU — Titel enthält schon Tag+Monat, hier nur die Jahreszahl
                )
            }
        }
        .sheet(isPresented: $showDeleteSheet) {
            UnifiedDeleteConfirmSheet()
        }
    }

    // MARK: - Kompaktes Banner: heute überprüfte Elemente
    private var todayBanner: some View {
        BannerCard(config: BannerConfig(
            style: .progressRow,
            iconTopGradient: [Color(hex: "9B87F5"), Color(hex: "5B3FE0")],
            iconBottomGradient: [Color(hex: "22D3B6"), Color(hex: "0FA98F")],
            title: "Heute schon \(swipeStore.todayCount) Elemente überprüft",
            highlight: nil,
            subtitle: nil,
            footnote: nil,
            progress: todayProgressFraction
        ))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private var todayProgressFraction: Double {
        min(1, Double(swipeStore.todayCount) / 300)
    }

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Erinnerungen")
                .font(.title2).bold()
                .padding(.horizontal)

            TabView(selection: $selectedDayOffset) {
                ForEach(dayMemories) { memory in
                    DayCollageCard(
                        memory: memory,
                        photoService: photoService,
                        previewCache: previewCache,
                        dayLabel: dayLabel(for: memory)
                    ) {
                        selectedDayMemory = memory
                    }
                    .tag(memory.offset)
                    .padding(.horizontal)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 230)
        }
    }

    private func dayLabel(for memory: DayMemory) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        let monthName = formatter.monthSymbols[memory.month - 1]
        return "\(memory.day). \(monthName)"
    }

    private var smartFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart-Filter")
                .font(.title2).bold()
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(smartFilters) { filter in
                    SmartFilterTile(
                        title: filter.title,
                        icon: smartFilterIcons[filter.title] ?? "square.grid.2x2",
                        filter: filter.filter,
                        photoService: photoService,
                        previewCache: previewCache
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 20))
                    .onTapGesture {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Tages-Collage-Karte
private struct DayCollageCard: View {
    let memory: DayMemory
    let photoService: PhotoLibraryService
    let previewCache: NuetzlichesPreviewCache
    let dayLabel: String
    let onTap: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var thumbnails: [UIImage] = []

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "12142B"))

                if !thumbnails.isEmpty {
                    collageStack
                } else {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                }

                // NEU: weicher Verlauf statt harter schwarzer Textbox — wächst
                // organisch aus dem unteren Drittel der Karte, kein Kasten-Look mehr.
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color(hex: "05060F").opacity(0.94)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 120)
                }
                .allowsHitTesting(false)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Marken-Akzentstrich über dem Datum
                            Capsule()
                                .fill(AppTheme.linearGradient(AppTheme.brandGradient, .leading, .trailing))
                                .frame(width: 32, height: 2)

                            Text(dayLabel)
                                .font(.title3).bold()
                                .foregroundStyle(.white)

                            Text(assets.isEmpty ? "Keine Erinnerungen" : "\(assets.count) \(assets.count == 1 ? "Bild" : "Bilder")")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                    }
                    .padding(16)
                }

                // NEU: dezenter Affordance-Indikator statt implizitem Tap
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .padding(12)
                    Spacer()
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(assets.isEmpty)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .task {
            // Erst Cache checken — beim Normalfall (Preload beim App-Start
            // war rechtzeitig fertig) ist das sofort da, kein eigener Ladepfad.
            if let cachedThumbs = previewCache.dayMemoryThumbnails[memory.offset], !cachedThumbs.isEmpty {
                thumbnails = cachedThumbs
                assets = previewCache.dayMemoryAssets[memory.offset] ?? []
            } else {
                loadAssets()
            }
        }
    }

    private var collageStack: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(thumbnails.prefix(4).enumerated()), id: \.offset) { index, image in
                    let angle = collageAngle(for: index)
                    let offsetPoint = collageOffset(for: index, in: geo.size)

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width * 0.55, height: geo.size.height * 0.85)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.6), lineWidth: 3))
                        .rotationEffect(.degrees(angle))
                        .offset(x: offsetPoint.x, y: offsetPoint.y)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func collageAngle(for index: Int) -> Double {
        [-8, 6, -4, 10][index % 4]
    }

    private func collageOffset(for index: Int, in size: CGSize) -> CGPoint {
        let positions: [CGPoint] = [
            CGPoint(x: -size.width * 0.14, y: 6),
            CGPoint(x: size.width * 0.16, y: -10),
            CGPoint(x: -size.width * 0.04, y: -18),
            CGPoint(x: size.width * 0.05, y: 14)
        ]
        return positions[index % positions.count]
    }

    private func loadAssets() {
        Task {
            let fetched = photoService.fetchAssets(filter: .dayAcrossYears(day: memory.day, month: memory.month))
            var collected: [UIImage] = []
            for asset in fetched.prefix(4) {
                if let image = await photoService.loadImage(for: asset, targetSize: CGSize(width: 300, height: 400)) {
                    collected.append(image)
                }
            }
            assets = fetched
            thumbnails = collected
        }
    }
}

// MARK: - Smart Filter Tile mit Vorschaubild, Icon & Anzahl
private struct SmartFilterTile: View {
    let title: String
    let icon: String
    let filter: PhotoFilter
    let photoService: PhotoLibraryService
    let previewCache: NuetzlichesPreviewCache

    @State private var previewImage: UIImage?
    @State private var matchCount: Int = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)

            if let previewImage {
                GeometryReader { geo in
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                LinearGradient(
                    colors: [.black.opacity(0.7), .black.opacity(0.0)],
                    startPoint: .bottom,
                    endPoint: .center
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                        .padding(8)
                        .background(
                            Circle().fill(previewImage == nil ? AppTheme.accent.opacity(0.15) : .white.opacity(0.2))
                        )
                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline).bold()
                        .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                        .lineLimit(1)
                    Text(matchCount > 0 ? "\(matchCount)" : "—")
                        .font(.caption)
                        .foregroundStyle(previewImage == nil ? Color.secondary : Color.white.opacity(0.8))
                }
            }
            .padding(12)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            if let cachedImage = previewCache.smartFilterPreviews[title] {
                previewImage = cachedImage
                matchCount = previewCache.smartFilterCounts[title] ?? 0
            } else {
                loadPreviewAndCount()
            }
        }
    }

    private func loadPreviewAndCount() {
        Task {
            let assets = photoService.fetchAssets(filter: filter)
            matchCount = assets.count

            // "Letzte 7 Tage" -> neuestes Bild (assets ist bereits neu->alt sortiert)
            // "Letzte 31 Tage" -> bewusst ein zufälliges Bild aus dem Zeitraum
            let chosenAsset: PHAsset?
            if case .lastDays(let days) = filter, days > 7 {
                chosenAsset = assets.randomElement()
            } else {
                chosenAsset = assets.first
            }

            guard let chosenAsset else { return }
            let image = await photoService.loadImage(for: chosenAsset, targetSize: CGSize(width: 300, height: 300))
            previewImage = image
        }
    }
}

// MARK: - Generischer Swipe-Screen für alle Smart-Filter & Tages-Erinnerungen
struct FilterSwipeScreen: View {
    let title: String
    let filter: PhotoFilter
    var pairedDateStyle: SwipeDeckView.PairedDateStyle = .full   // NEU

    @Environment(\.colorScheme) private var colorScheme
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @State private var assets: [PHAsset] = []
    @State private var showDeleteSheet = false

    var body: some View {
        ZStack {
            AppTheme.background(colorScheme).ignoresSafeArea()
            SwipeDeckView(
                assets: assets,
                photoService: photoService,
                swipeStore: swipeStore,
                title: title,
                pairDateWithTitle: true,
                pairedDateStyle: pairedDateStyle,
                embeddedInTabBar: false
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
        .sheet(isPresented: $showDeleteSheet) {
            UnifiedDeleteConfirmSheet()
        }
        .onAppear {
            Task {
                let loaded = photoService.fetchAssets(filter: filter).shuffled()
                assets = loaded
            }
        }
    }
}

#Preview {
    NuetzlichesTab()
        .environment(PhotoLibraryService())
        .environment(SwipeStateStore())
        .environment(NuetzlichesPreviewCache())
}
