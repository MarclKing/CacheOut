import SwiftUI
import Photos

struct MonthSelection: Identifiable, Hashable {
    let year: Int
    let month: Int
    var id: String { "\(year)-\(month)" }
}

// NEU: Jahres-Auswahl für den Banner-Tap (ganzes Jahr swipen)
struct YearSelection: Identifiable, Hashable {
    let year: Int
    var id: Int { year }
}

struct StoryDay: Identifiable, Hashable {
    let year: Int
    let month: Int
    let day: Int
    var id: String { "\(year)-\(month)-\(day)" }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init?(idString: String) {
        let parts = idString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        year = parts[0]
        month = parts[1]
        day = parts[2]
    }
}

struct StoryPhotoItem: Identifiable, Hashable {
    let id: String   // asset.localIdentifier
    let asset: PHAsset
    let dayLabel: String
    let dayId: String   // NEU — welchem Story-Tag dieses Item zugehört

    static func == (lhs: StoryPhotoItem, rhs: StoryPhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MeinLebenTab: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(MeinLebenPreviewCache.self) private var previewCache

    @State private var yearsData: [Int: Set<Int>] = [:]
    @State private var yearItemCounts: [Int: Int] = [:]
    @State private var showDeleteSheet = false
    @State private var selectedMonth: MonthSelection?
    @State private var selectedYear: YearSelection?

    @State private var storyDays: [StoryDay] = []
    @State private var storyItems: [StoryPhotoItem] = []
    @State private var startIdByDay: [String: String] = [:]
    @State private var assetIdsByDay: [String: [String]] = [:]   // NEU — für "Tag komplett geswiped"-Check
    @State private var showStoryViewer = false
    @State private var storyViewerItems: [StoryPhotoItem] = []

    private let storyDaysKey = "storyDaysSelection"
    private let storyDaysDateKey = "storyDaysSelectionDate"

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longDayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMMM yyyy"
        return f
    }()

    private var sortedYears: [Int] {
        yearsData.keys.sorted(by: >)
    }

    private var currentMonthNumber: Int {
        Calendar.current.component(.month, from: Date())
    }

    private var currentYearForCache: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func monthsToShow(for year: Int) -> [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return year == currentYear ? Array(1...currentMonthNumber) : Array(1...12)
    }

    // NEU — Tag gilt als fertig, wenn alle seine Assets bereits geswiped sind
    private func isDayCompleted(_ day: StoryDay) -> Bool {
        guard let ids = assetIdsByDay[day.id], !ids.isEmpty else { return false }
        return ids.allSatisfy { swipeStore.hasBeenSwiped($0) }
    }

    // NEU — offene Tage zuerst (Originalreihenfolge), fertige Tage ans Ende
    private var sortedStoryDays: [StoryDay] {
        let incomplete = storyDays.filter { !isDayCompleted($0) }
        let completed = storyDays.filter { isDayCompleted($0) }
        return incomplete + completed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {                                              // NEU
                    if yearsData.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            if !storyDays.isEmpty {
                                storiesSection
                            }

                            LazyVStack(spacing: 32, pinnedViews: []) {
                                ForEach(sortedYears, id: \.self) { year in
                                    yearSection(year: year)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
    
            .navigationTitle("Mein Leben")
            .navigationBarTitleDisplayMode(.inline)
            .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
            .navigationDestination(item: $selectedMonth) { selection in
                MonthSwipeScreen(year: selection.year, month: selection.month)
            }
            .navigationDestination(item: $selectedYear) { selection in
                YearSwipeScreen(year: selection.year)
            }
            .navigationDestination(isPresented: $showStoryViewer) {
                StoryViewerScreen(items: storyViewerItems, photoService: photoService, swipeStore: swipeStore)
            }
        }
        .sheet(isPresented: $showDeleteSheet) {
            UnifiedDeleteConfirmSheet()
        }
        .onAppear {
            if previewCache.isPreloaded {
                yearsData = previewCache.yearsData
                storyDays = previewCache.storyDays
                storyItems = previewCache.storyItems
                startIdByDay = previewCache.startIdByDay
                assetIdsByDay = previewCache.assetIdsByDay
            } else {
                loadYears()
                loadStoryDays()
            }
            // yearItemCounts() ist jetzt durch assetsGroupedByYear() im
            // PhotoLibraryService intern gecacht — der Aufruf bleibt hier bewusst
            // immer bestehen (er ist nach Fix #3 quasi kostenlos), aber ohne den
            // PhotoLibraryService-Fix wäre das hier weiterhin ein Vollscan pro Besuch gewesen.
            loadYearItemCounts()
        }
    }

    // MARK: - Story-Leiste direkt unter der Überschrift
    private var storiesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(sortedStoryDays) { day in
                    StoryCircle(
                        day: day,
                        photoService: photoService,
                        cachedPreview: previewCache.storyPreviewImages[day.id],
                        isCompleted: isDayCompleted(day)
                    )
                    .onTapGesture {
                        // FIX: vorher wurde storyItems[index...] genommen — das ist
                        // die KOMPLETTE verkettete Liste aller Story-Tage, also liefen
                        // automatisch alle nachfolgenden Tage (andere Jahre/Monate) mit.
                        // Jetzt strikt nur Items DIESES Tages.
                        let dayItems = storyItems.filter { $0.dayId == day.id }
                        guard !dayItems.isEmpty else { return }
                        storyViewerItems = dayItems
                        showStoryViewer = true
                    }
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.35), value: sortedStoryDays)
        }
    }

    // NEU: Jahres-Banner statt reiner Text-Überschrift — tappbar, öffnet
    // YearSwipeScreen für das komplette Jahr. Monats-Grid darunter unverändert.
    private func yearSection(year: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            YearBanner(year: year, count: yearItemCounts[year] ?? 0)
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedYear = YearSelection(year: year)
                }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                ForEach(monthsToShow(for: year), id: \.self) { month in
                    MonthTile(
                        year: year,
                        month: month,
                        hasContent: yearsData[year]?.contains(month) ?? false,
                        photoService: photoService,
                        swipeStore: swipeStore,
                        cachedPreview: year == currentYearForCache ? previewCache.currentYearMonthPreviews[month] : nil
                    )
                    .onTapGesture {
                        if yearsData[year]?.contains(month) == true {
                            selectedMonth = MonthSelection(year: year, month: month)
                        }
                    }
                }
            }
            .padding(.horizontal)

            Divider().padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("Keine Fotos gefunden")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 100)
    }

    private func loadYears() {
        yearsData = photoService.availableYearsAndMonths()
    }

    private func loadYearItemCounts() {
        yearItemCounts = photoService.yearItemCounts()
    }

    private func todayDateKey() -> String {
        Self.dayKeyFormatter.string(from: Date())
    }

    private func loadStoryDays() {
        let todayKey = todayDateKey()

        if UserDefaults.standard.string(forKey: storyDaysDateKey) == todayKey,
           let saved = UserDefaults.standard.array(forKey: storyDaysKey) as? [String] {
            let days = saved.compactMap { StoryDay(idString: $0) }
            if !days.isEmpty {
                storyDays = days
                Task { await buildStoryItems(for: days) }
                return
            }
        }

        Task {
            let richDays = photoService.topPhotoRichDays(limit: 40)
            let picked = Array(richDays.shuffled().prefix(12))
                .map { StoryDay(year: $0.year, month: $0.month, day: $0.day) }
            await MainActor.run {
                storyDays = picked
                UserDefaults.standard.set(picked.map { $0.id }, forKey: storyDaysKey)
                UserDefaults.standard.set(todayKey, forKey: storyDaysDateKey)
            }
            await buildStoryItems(for: picked)
        }
    }

    private func buildStoryItems(for days: [StoryDay]) async {
        var items: [StoryPhotoItem] = []
        var startIds: [String: String] = [:]
        var idsByDay: [String: [String]] = [:]
        var qualifyingDays: [StoryDay] = []   // NEU

        for day in days {
            let dayAssets = photoService.fetchAssets(filter: .month(year: day.year, month: day.month))
                .filter { asset in
                    guard let date = asset.creationDate else { return false }
                    return Calendar.current.component(.day, from: date) == day.day
                }

            guard dayAssets.count > 7 else { continue }   // NEU: Tage mit ≤7 Fotos werden ausgeblendet

            let limited = dayAssets.prefix(15)             // GEÄNDERT: erst filtern, dann erst begrenzen
            guard let first = limited.first else { continue }
            let label = shortDayLabel(day)
            startIds[day.id] = first.localIdentifier
            idsByDay[day.id] = limited.map { $0.localIdentifier }
            qualifyingDays.append(day)                     // NEU
            items.append(contentsOf: limited.map {
                StoryPhotoItem(id: $0.localIdentifier, asset: $0, dayLabel: label, dayId: day.id)
            })
        }

        await MainActor.run {
            storyDays = qualifyingDays                      // NEU: nur qualifizierte Tage werden angezeigt/gecached
            storyItems = items
            startIdByDay = startIds
            assetIdsByDay = idsByDay
        }
    }

    private func shortDayLabel(_ day: StoryDay) -> String {
        var comps = DateComponents()
        comps.year = day.year
        comps.month = day.month
        comps.day = day.day
        let date = Calendar.current.date(from: comps) ?? Date()
        return Self.longDayLabelFormatter.string(from: date)
    }
}

// MARK: - Jahres-Banner: Gradient nach Jahr (deterministisch, aus AppTheme),
// zeigt Jahr + Elementanzahl, dient als Überschrift UND Tap-Ziel fürs ganze Jahr.
private struct YearBanner: View {
    let year: Int
    let count: Int

    var body: some View {
        HStack {
            Text(String(year))
                .font(.title2).bold()
                .foregroundStyle(.white)

            Spacer()

            Text("\(count) Elemente")
                .font(.caption).bold()
                .foregroundStyle(.white.opacity(0.85))

            Image(systemName: "chevron.right")
                .font(.caption).bold()
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: AppTheme.yearGradient(for: year), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Story-Kreis mit blauem Verlaufsring
private struct StoryCircle: View {
    let day: StoryDay
    let photoService: PhotoLibraryService
    let cachedPreview: UIImage?
    let isCompleted: Bool   // NEU

    @State private var previewImage: UIImage?

    private static let shortLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM yy"
        return f
    }()

    private var shortLabel: String {
        var comps = DateComponents()
        comps.year = day.year
        comps.month = day.month
        comps.day = day.day
        let date = Calendar.current.date(from: comps) ?? Date()
        return Self.shortLabelFormatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // NEU: grauer statt bunter Ring, wenn der Tag komplett geswiped ist
                Circle()
                    .fill(
                        isCompleted
                        ? AnyShapeStyle(Color.gray.opacity(0.35))
                        : AnyShapeStyle(LinearGradient(colors: AppTheme.brandGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .frame(width: 80, height: 80)

                Circle()
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: 72, height: 72)

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 66, height: 66)
                        .clipShape(Circle())
                } else {
                    ProgressView()
                        .frame(width: 66, height: 66)
                }
            }

            Text(shortLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .task {
            if let cachedPreview {
                previewImage = cachedPreview
            } else {
                loadPreview()
            }
        }
    }

    private func loadPreview() {
        Task {
            let assets = photoService.fetchAssets(filter: .month(year: day.year, month: day.month))
                .filter { asset in
                    guard let date = asset.creationDate else { return false }
                    return Calendar.current.component(.day, from: date) == day.day
                }
            if let first = assets.first {
                let image = await photoService.loadImage(for: first, targetSize: CGSize(width: 150, height: 150))
                await MainActor.run { previewImage = image }
            }
        }
    }
}

// MARK: - Story-Viewer mit SwipeDeckView
struct StoryViewerScreen: View {
    let items: [StoryPhotoItem]
    let photoService: PhotoLibraryService
    let swipeStore: SwipeStateStore

    @State private var showDeleteSheet = false

    private var assets: [PHAsset] { items.map { $0.asset } }

    var body: some View {
        ZStack {
            AppTheme.background(.dark).ignoresSafeArea()
            SwipeDeckView(
                assets: assets,
                photoService: photoService,
                swipeStore: swipeStore,
                title: items.first?.dayLabel,
                embeddedInTabBar: false
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
        .hidesTabBar()
        .sheet(isPresented: $showDeleteSheet) {
            UnifiedDeleteConfirmSheet()
        }
    }
}

// MARK: - Month Tile — garantiert quadratisch & einheitlich
private struct MonthTile: View {
    let year: Int
    let month: Int
    let hasContent: Bool
    let photoService: PhotoLibraryService
    let swipeStore: SwipeStateStore
    let cachedPreview: UIImage?

    @State private var previewImage: UIImage?
    @State private var isSorted = false
    private static let previewMemory = NSCache<NSString, UIImage>()

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.shortMonthSymbols[month - 1]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(hasContent ? 0.08 : 0.06))

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    LinearGradient(
                        colors: [.black.opacity(0.65), .black.opacity(0.0)],
                        startPoint: .bottom, endPoint: .center
                    )
                } else if !hasContent {
                    VStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 18, weight: .medium))
                        Text("Keine Fotos")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.45))
                }

                if hasContent {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(monthName)
                            .font(.subheadline).bold()
                            .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                        if isSorted {
                            Text("Sorted")
                                .font(.caption2).bold()
                                .foregroundStyle(AppTheme.keepGreen)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .aspectRatio(1, contentMode: .fit)
        .task {
            guard hasContent else { return }
            let key = "\(year)-\(month)" as NSString
            if previewImage == nil, let mem = Self.previewMemory.object(forKey: key) { previewImage = mem }
            if previewImage == nil, let cachedPreview { previewImage = cachedPreview }
            let assets = photoService.fetchAssets(filter: .month(year: year, month: month))
            isSorted = !assets.isEmpty && assets.allSatisfy { swipeStore.hasBeenSwiped($0.localIdentifier) }
            if previewImage == nil, let first = assets.first {
                let image = await photoService.loadImage(for: first, targetSize: CGSize(width: 150, height: 150))
                if let image { Self.previewMemory.setObject(image, forKey: key) }
                previewImage = image
            }
        }
    }
}

// MARK: - Month Swipe Screen (nutzt SwipeDeckView wieder!)
struct MonthSwipeScreen: View {
    let year: Int
    let month: Int

    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @State private var assets: [PHAsset] = []
    @State private var showDeleteSheet = false

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        let name = formatter.monthSymbols[month - 1]
        return "\(name) \(year)"
    }

    var body: some View {
        ZStack {
            AppTheme.background(.dark).ignoresSafeArea()
            SwipeDeckView(
                assets: assets,
                photoService: photoService,
                swipeStore: swipeStore,
                title: monthTitle,
                embeddedInTabBar: false
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
        .hidesTabBar()
        .sheet(isPresented: $showDeleteSheet) {
            UnifiedDeleteConfirmSheet()
        }
        .onAppear {
            assets = photoService.fetchAssets(filter: .month(year: year, month: month))
        }
    }
}

// MARK: - NEU: Year Swipe Screen — komplettes Jahr über den Jahres-Banner-Tap
struct YearSwipeScreen: View {
    let year: Int

    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(SwipeStateStore.self) private var swipeStore
    @State private var assets: [PHAsset] = []
    @State private var showDeleteSheet = false
    @State private var isLoadingAssets = false

    var body: some View {
        ZStack {
            AppTheme.background(.dark).ignoresSafeArea()
            if isLoadingAssets {
                ProgressView().tint(.white)
            } else {
                SwipeDeckView(
                    assets: assets,
                    photoService: photoService,
                    swipeStore: swipeStore,
                    title: String(year),
                    embeddedInTabBar: false
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .deleteToolbarButton(showDeleteSheet: $showDeleteSheet)
        .hidesTabBar()
        .sheet(isPresented: $showDeleteSheet) {
            UnifiedDeleteConfirmSheet()
        }
        .onAppear {
            guard assets.isEmpty else { return }
            isLoadingAssets = true
            Task.detached(priority: .userInitiated) {
                let loaded = await photoService.fetchAssets(filter: .yearAll(year))
                await MainActor.run {
                    assets = loaded
                    isLoadingAssets = false
                }
            }
        }
    }
}

#Preview {
    MeinLebenTab()
        .environment(PhotoLibraryService())
        .environment(SwipeStateStore())
        .environment(MeinLebenPreviewCache())
}
