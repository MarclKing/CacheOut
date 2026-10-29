import SwiftUI
import Photos
import UIKit
import AVFoundation

struct SwipeDeckView: View {
    let assets: [PHAsset]
    let photoService: PhotoLibraryService
    let swipeStore: SwipeStateStore

    var title: String? = nil
    var pairDateWithTitle: Bool = false
    var pairedDateStyle: PairedDateStyle = .full
    var embeddedInTabBar: Bool = true

    enum PairedDateStyle {
        case full
        case yearOnly
    }

    @Environment(DeletionStatsStore.self) private var deletionStatsStore
    @Environment(StreakTracker.self) private var streakTracker
    @Environment(AchievementStore.self) private var achievementStore
    @Environment(\.displayScale) private var displayScale

    @State private var loadedImages: [String: UIImage] = [:]
    @State private var currentFileSizeBytes: Int64?
    @State private var nextFileSizeBytes: Int64?
    @State private var currentFileSizeAssetId: String?

    @State private var preloadedVideoItems: [String: AVPlayerItem] = [:]
    @State private var preloadingVideoId: String?

    @State private var sessionSkippedIds: [String] = []
    @State private var remainingAssets: [PHAsset] = []

    @State private var pendingAction: SwipeAction?
    @State private var previewItem: QuickLookItem?
    @State private var previewImage: UIImage?
    @State private var isPreviewImageZoomed = false   // NEU
    @State private var isPreparingPreview = false
    @State private var previewPlaceholderImage: UIImage?
    @State private var topSafeAreaInset: CGFloat = 0
    
    @State private var deckHeight: CGFloat = 0
    @State private var deckSize: CGSize = CGSize(width: 400, height: 900)
    @State private var bottomBarTopY: CGFloat = 0

    @State private var preloadedPreviewURLs: [String: URL] = [:]
    @State private var preloadingPreviewAssetIds: Set<String> = []

    @State private var previewDragOffset: CGSize = .zero
    @State private var previewDragScale: CGFloat = 1

    @State private var cachedPrefetchAssets: [PHAsset] = []
    @State private var cachedPrefetchTargetSize: CGSize = .zero

    private var currentImage: UIImage? {
        remainingAssets.first.flatMap { loadedImages[$0.localIdentifier] }
    }
    private var nextImage: UIImage? {
        nextAsset.flatMap { loadedImages[$0.localIdentifier] }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMMM yyyy"
        return formatter
    }()

    private var cardImageTargetSize: CGSize {
        let scale = min(displayScale, 2)
        return CGSize(width: deckSize.width * scale, height: deckSize.height * scale)
    }

    private func rebuildRemainingAssets() {
        let notSwiped = assets.filter { !swipeStore.hasBeenSwiped($0.localIdentifier) }
        let skippedSet = Set(sessionSkippedIds)
        remainingAssets = notSwiped.filter { !skippedSet.contains($0.localIdentifier) }
             + notSwiped.filter { skippedSet.contains($0.localIdentifier) }
        prefetchUpcoming()
        cleanupPreloadedVideos()
        cleanupPreloadedPreviews()
        cleanupLoadedImages()
        preloadPreviewIfNeeded()
    }

    private var nextAsset: PHAsset? {
        remainingAssets.count > 1 ? remainingAssets[1] : nil
    }

    private func prefetchUpcoming() {
        let targetSize = cardImageTargetSize
        let upcoming = Array(remainingAssets.dropFirst().prefix(3).filter { $0.mediaType != .video })
        let upcomingIds = Set(upcoming.map { $0.localIdentifier })

        let toRemove = cachedPrefetchAssets.filter { !upcomingIds.contains($0.localIdentifier) }
        if !toRemove.isEmpty {
            photoService.stopCaching(assets: toRemove, targetSize: cachedPrefetchTargetSize)
        }

        photoService.startCaching(assets: upcoming, targetSize: targetSize)
        cachedPrefetchAssets = upcoming
        cachedPrefetchTargetSize = targetSize
    }

    private func preloadNextVideoIfNeeded() {
        guard let asset = nextAsset, asset.mediaType == .video else { return }
        let assetId = asset.localIdentifier
        guard preloadedVideoItems[assetId] == nil, preloadingVideoId != assetId else { return }
        preloadingVideoId = assetId

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.version = .current

        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
            DispatchQueue.main.async {
                guard let playerItem else { return }
                guard nextAsset?.localIdentifier == assetId else { return }
                preloadedVideoItems[assetId] = playerItem
            }
        }
    }

    private func cleanupPreloadedVideos() {
        let keepIds = Set(remainingAssets.prefix(2).map { $0.localIdentifier })
        preloadedVideoItems = preloadedVideoItems.filter { keepIds.contains($0.key) }
    }

    private func cleanupLoadedImages() {
        let keepIds = Set(remainingAssets.prefix(2).map { $0.localIdentifier })
        loadedImages = loadedImages.filter { keepIds.contains($0.key) }
    }

    private func preloadPreviewIfNeeded() {
        if let asset = remainingAssets.first {
            preloadPreview(for: asset)
        }
    }

    private func preloadPreview(for asset: PHAsset) {
        let assetId = asset.localIdentifier
        guard preloadedPreviewURLs[assetId] == nil,
              !preloadingPreviewAssetIds.contains(assetId) else { return }
        preloadingPreviewAssetIds.insert(assetId)

        Task {
            let url = await photoService.exportToTemporaryURL(for: asset)
            await MainActor.run {
                preloadingPreviewAssetIds.remove(assetId)
                guard let url else { return }
                guard remainingAssets.prefix(2).map(\.localIdentifier).contains(assetId) else {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                    return
                }
                preloadedPreviewURLs[assetId] = url
            }
        }
    }

    private func cleanupPreloadedPreviews() {
        let keepIds = Set(remainingAssets.prefix(1).map { $0.localIdentifier })
        for (id, url) in preloadedPreviewURLs where !keepIds.contains(id) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        preloadedPreviewURLs = preloadedPreviewURLs.filter { keepIds.contains($0.key) }
    }

    var body: some View {
        ZStack {
            cardLayer
                .ignoresSafeArea(edges: embeddedInTabBar ? .top : .all)
                .padding(.bottom, embeddedInTabBar ? 10 : 0)
                .overlay(alignment: .bottomTrailing) {
                    if remainingAssets.first != nil {
                        expandButton(for: remainingAssets.first)
                            .padding(.trailing, 24)
                            .padding(.bottom, expandButtonBottomInset)
                    }
                }

            if remainingAssets.first != nil {
                VStack(spacing: 0) {
                    Spacer()
                    bottomBar
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        bottomBarTopY = geo.frame(in: .named("swipeDeck")).minY
                                    }
                                    .onChange(of: geo.frame(in: .named("swipeDeck")).minY) { _, newValue in
                                        bottomBarTopY = newValue
                                    }
                            }
                        )
                }
                .ignoresSafeArea(edges: embeddedInTabBar ? [] : .bottom)
            }
        }
        .coordinateSpace(name: "swipeDeck")
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        topSafeAreaInset = geo.safeAreaInsets.top
                        deckHeight = geo.size.height
                        deckSize = geo.size
                    }
                    .onChange(of: geo.safeAreaInsets.top) { _, newValue in
                        topSafeAreaInset = newValue
                    }
                    .onChange(of: geo.size) { _, newValue in
                        deckHeight = newValue.height
                        deckSize = newValue
                    }
            }
        )
        .onChange(of: remainingAssets.first?.localIdentifier) { _, _ in
            loadCurrentImage()
            loadNextImage()
            loadFileSize()
            loadNextFileSize()
            preloadNextVideoIfNeeded()
        }
        .onChange(of: nextAsset?.localIdentifier) { _, _ in
            loadNextImage()
            loadNextFileSize()
            preloadNextVideoIfNeeded()
        }
        .onChange(of: assets.map(\.localIdentifier)) { _, _ in
            rebuildRemainingAssets()
        }
        .onAppear {
            rebuildRemainingAssets()
            loadCurrentImage()
            loadFileSize()
            loadNextFileSize()
        }
        .onDisappear {
            photoService.stopCachingAll()
            for (_, url) in preloadedPreviewURLs {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            preloadedPreviewURLs = [:]
        }
        .fullScreenCover(item: Binding(
            get: { previewImage.map { IdentifiableImage(image: $0) } },
            set: { previewImage = $0?.image }
        )) { wrapped in
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ZoomableImageView(image: wrapped.image, isZoomed: $isPreviewImageZoomed)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") {
                            previewImage = nil
                        }
                    }
                }
            }
            .offset(y: previewDragOffset.height)
            .scaleEffect(previewDragScale)
            .gesture(closeGesture)
            .onTapGesture(count: 2) {
                // schon von ZoomableImageView selbst behandelt (Zoom-Toggle)
            }
        }
        .fullScreenCover(item: $previewItem, onDismiss: {
            cleanupPreviewFile()
            previewPlaceholderImage = nil
        }) { item in
            NavigationStack {
                ZStack {
                    if let placeholder = previewPlaceholderImage {
                        Image(uiImage: placeholder)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                    QuickLookPreview(item: item)
                        .ignoresSafeArea()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fertig") {
                            previewItem = nil
                        }
                    }
                }
            }
            .offset(y: previewDragOffset.height)
            .scaleEffect(previewDragScale)
            .background(
                Color.black
                    .opacity(1 - min(1, previewDragOffset.height / 400) * 0.5)
                    .ignoresSafeArea()
            )
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard value.translation.height > 0 else { return }
                        previewDragOffset = value.translation
                        previewDragScale = 1 - min(1, value.translation.height / 400) * 0.12
                    }
                    .onEnded { value in
                        let shouldDismiss = value.translation.height > 140
                            || value.predictedEndTranslation.height > 300
                        if shouldDismiss {
                            previewItem = nil
                            previewDragOffset = .zero
                            previewDragScale = 1
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                previewDragOffset = .zero
                                previewDragScale = 1
                            }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                previewItem = nil
            }
        }
    }

    // MARK: - Aufräumen der temporären Preview-Datei
    private func cleanupPreviewFile() {
        guard let url = previewItem?.url else { return }
        let folderURL = url.deletingLastPathComponent()
        preloadedPreviewURLs = preloadedPreviewURLs.filter { $0.value != url }
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: folderURL)
        }
    }

    // MARK: - QuickLook-Vorschau öffnen
    private func openPreview(for asset: PHAsset) {
        guard !isPreparingPreview else { return }

        if asset.mediaType != .video, let image = loadedImages[asset.localIdentifier] {
            previewImage = image
            return
        }

        previewPlaceholderImage = loadedImages[asset.localIdentifier]

        if let cachedURL = preloadedPreviewURLs[asset.localIdentifier] {
            previewItem = QuickLookItem(url: cachedURL)
            return
        }

        isPreparingPreview = true
        Task {
            let url = await photoService.exportToTemporaryURL(for: asset)
            await MainActor.run {
                isPreparingPreview = false
                guard let url else { return }
                previewItem = QuickLookItem(url: url)
            }
        }
    }

    // MARK: - Schließen-Geste (immer angehängt, aber nur aktiv wenn nicht gezoomt)
    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isPreviewImageZoomed else { return }
                guard value.translation.height > 0 else { return }
                previewDragOffset = value.translation
                previewDragScale = 1 - min(1, value.translation.height / 400) * 0.12
            }
            .onEnded { value in
                guard !isPreviewImageZoomed else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        previewDragOffset = .zero
                        previewDragScale = 1
                    }
                    return
                }

                let shouldDismiss = value.translation.height > 140
                    || value.predictedEndTranslation.height > 300
                if shouldDismiss {
                    previewImage = nil
                    previewDragOffset = .zero
                    previewDragScale = 1
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        previewDragOffset = .zero
                        previewDragScale = 1
                    }
                }
            }
    }

    // MARK: - Scrim/Icon-Zonen-Geometrie
    private var iconRowHeight: CGFloat { 64 }
    private var progressChipSpacing: CGFloat { 10 }
    private var progressChipHeight: CGFloat { 3 }
    private var bottomBarBottomInset: CGFloat { 28 }
    private var iconZoneHeight: CGFloat {
        iconRowHeight + progressChipSpacing + progressChipHeight + bottomBarBottomInset
    }
    private var bottomScrimBuffer: CGFloat { 12 }
    private var bottomScrimFadeHeight: CGFloat { 150 }
    private var bottomScrimHeight: CGFloat {
        iconZoneHeight + bottomScrimBuffer + bottomScrimFadeHeight
    }
    private var navBarHeight: CGFloat { 44 }
    private var navBarBandFineTuneOffset: CGFloat { -9 }
    private var navBarBandTopPadding: CGFloat {
        max(0, topSafeAreaInset - navBarHeight + navBarBandFineTuneOffset)
    }
    
    private var expandButtonBottomInset: CGFloat {
        let measuredGap: CGFloat
        if bottomBarTopY > 0, deckHeight > 0 {
            measuredGap = max(0, deckHeight - bottomBarTopY + 4)
        } else {
            measuredGap = iconZoneHeight + 4
        }
        return measuredGap + ((remainingAssets.first?.mediaType == .video) ? 34 : 0)
    }

    private var bottomCardScrim: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.0), location: 0),
                            .init(color: .black.opacity(0.02), location: 0.2),
                            .init(color: .black.opacity(0.06), location: 0.4),
                            .init(color: .black.opacity(0.2), location: 0.6),
                            .init(color: .black.opacity(0.45), location: 0.78),
                            .init(color: .black.opacity(0.75), location: 0.9),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            LinearGradient(
                stops: [
                    .init(color: AppTheme.background(.dark).opacity(0.0), location: 0),
                    .init(color: AppTheme.background(.dark).opacity(0.015), location: 0.2),
                    .init(color: AppTheme.background(.dark).opacity(0.05), location: 0.4),
                    .init(color: AppTheme.background(.dark).opacity(0.16), location: 0.6),
                    .init(color: AppTheme.background(.dark).opacity(0.35), location: 0.78),
                    .init(color: AppTheme.background(.dark).opacity(0.6), location: 0.9),
                    .init(color: AppTheme.background(.dark).opacity(0.88), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: bottomScrimHeight)
        .allowsHitTesting(false)
    }

    private var topCardScrim: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 160)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.4), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.55),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 190)
        }
        .allowsHitTesting(false)
    }

    private static let cardShape = UnevenRoundedRectangle(
        topLeadingRadius: 40,
        bottomLeadingRadius: 40,
        bottomTrailingRadius: 40,
        topTrailingRadius: 40,
        style: .continuous
    )

    @ViewBuilder
    private func topOverlayContent(for asset: PHAsset) -> some View {
        if pairDateWithTitle, let title {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                Text(pairedDateText(for: asset))
                    .font(.subheadline).bold()
                    .foregroundStyle(.white.opacity(0.75))
            }
        } else if let title {
            Text(title)
                .font(.subheadline).bold()
                .foregroundStyle(.white)
        } else {
            Text(formattedDate(for: asset))
                .font(.subheadline).bold()
                .foregroundStyle(.white)
        }
    }

    private var cardLayer: some View {
        Group {
            if let asset = remainingAssets.first {
                SwipeCardContainer(
                    externalTrigger: $pendingAction,
                    onKeep: { swipeKeep(asset: asset) },
                    onDelete: { swipeDelete(asset: asset) },
                    onSkip: { swipeSkip(asset: asset) },
                    onSwipeUp: { openPreview(for: asset) },
                    content: {
                        cardView(for: asset)
                            .overlay(alignment: .top) { topCardScrim }
                            .overlay(alignment: .top) {
                                topOverlayContent(for: asset)
                                    .frame(maxWidth: .infinity, minHeight: navBarHeight, maxHeight: navBarHeight)
                                    .padding(.top, navBarBandTopPadding)
                            }
                            .overlay(alignment: .bottom) { bottomCardScrim }
                            .overlay(alignment: .bottomLeading) {
                                if let bytes = currentFileSizeBytes {
                                    sizeChip(bytes: bytes, mediaType: asset.mediaType)
                                        .padding(.leading, 24)
                                        .padding(.bottom, iconZoneHeight + 4 + (asset.mediaType == .video ? 34 : 0))
                                }
                            }
                            .clipShape(Self.cardShape)
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.45)
                                    .onEnded { _ in
                                        openPreview(for: asset)
                                    }
                            )
                            .onTapGesture(count: 2) {
                                openPreview(for: asset)
                            }
                    },
                    nextContent: {
                        nextCardPreview()
                            .clipShape(Self.cardShape)
                    }
                )
            } else {
                emptyStateView
            }
        }
    }

    @ViewBuilder
    private func nextCardPreview() -> some View {
        if let asset = nextAsset {
            GeometryReader { geo in
                Group {
                    if let nextImage {
                        Image(uiImage: nextImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .overlay(Rectangle().fill(.ultraThinMaterial))
                    }
                }
            }
            .overlay(alignment: .top) { topCardScrim }
            .overlay(alignment: .top) {
                topOverlayContent(for: asset)
                    .frame(maxWidth: .infinity, minHeight: navBarHeight, maxHeight: navBarHeight)
                    .padding(.top, navBarBandTopPadding)
            }
            .overlay(alignment: .bottom) { bottomCardScrim }
            .overlay(alignment: .bottomLeading) {
                if let bytes = nextFileSizeBytes {
                    sizeChip(bytes: bytes, mediaType: asset.mediaType)
                        .padding(.leading, 24)
                        .padding(.bottom, iconZoneHeight + 4 + (asset.mediaType == .video ? 34 : 0))
                }
            }
        } else {
            Color.clear
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                smallChromeButton(icon: "arrow.uturn.backward", color: .white.opacity(0.9)) {
                    swipeStore.undoLast()
                    rebuildRemainingAssets()
                }
                .disabled(swipeStore.lastSwipedId == nil)

                Spacer()

                bigChromeButton(icon: "xmark", color: AppTheme.deleteRed) {
                    guard remainingAssets.first != nil else { return }
                    pendingAction = .delete
                }

                Spacer()

                smallChromeButton(icon: "arrow.down", color: AppTheme.skipBlue) {
                    guard remainingAssets.first != nil else { return }
                    pendingAction = .skip
                }

                Spacer()

                bigChromeButton(icon: "heart.fill", color: AppTheme.keepGreen) {
                    guard remainingAssets.first != nil else { return }
                    pendingAction = .keep
                }

                Spacer()

                smallChromeButton(icon: "square.and.arrow.up", color: .white.opacity(0.9)) {
                    guard let asset = remainingAssets.first else { return }
                    shareCurrentImage(asset: asset)
                }
            }
            .padding(.horizontal, 24)

            progressChip
        }
        .padding(.bottom, bottomBarBottomInset)
    }

    private var progressChip: some View {
        let total = assets.count
        let done = max(0, total - remainingAssets.count)
        let fraction = total > 0 ? Double(done) / Double(total) : 0

        return Group {
            if total > 1 {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 60, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.85))
                            .frame(width: max(3, 60 * fraction), height: 3)
                    }
            }
        }
    }

    private func smallChromeButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func bigChromeButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func shareCurrentImage(asset: PHAsset) {
        Task {
            let fullImage = await photoService.loadImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 2200)
            )
            let dateText = shareDateText(for: asset)
            let image = fullImage ?? currentImage

            await MainActor.run {
                guard let image else { return }
                ShareSheetPresenter.present(items: [image, dateText])
            }
        }
    }

    private func shareDateText(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "" }
        return "Vom \(Self.dateFormatter.string(from: date))"
    }

    private func formattedDate(for asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "" }
        return Self.dateFormatter.string(from: date)
    }

    private func pairedDateText(for asset: PHAsset) -> String {
        switch pairedDateStyle {
        case .full:
            return formattedDate(for: asset)
        case .yearOnly:
            guard let date = asset.creationDate else { return "" }
            return String(Calendar.current.component(.year, from: date))
        }
    }

    private enum FileSizeTier {
        case low, medium, high

        var color: Color {
            switch self {
            case .low: return AppTheme.keepGreen
            case .medium: return .yellow
            case .high: return AppTheme.deleteRed
            }
        }
    }

    private func sizeChip(bytes: Int64, mediaType: PHAssetMediaType?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
            Text(formattedFileSize(bytes))
                .font(.caption).bold()
                .foregroundStyle(.white)
            Circle()
                .fill(sizeTier(for: bytes, mediaType: mediaType).color)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func expandButton(for asset: PHAsset?) -> some View {
        Button {
            guard let asset else { return }
            openPreview(for: asset)
        } label: {
            Group {
                if isPreparingPreview {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(isPreparingPreview || asset == nil)
    }

    private func sizeTier(for bytes: Int64, mediaType: PHAssetMediaType?) -> FileSizeTier {
        let mb = Double(bytes) / 1_048_576
        if mediaType == .video {
            if mb < 20 { return .low }
            if mb < 80 { return .medium }
            return .high
        } else {
            if mb < 2 { return .low }
            if mb < 5 { return .medium }
            return .high
        }
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 0.1 {
            let kb = Double(bytes) / 1024
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.1f MB", mb)
    }

    private func loadFileSize() {
        guard let asset = remainingAssets.first else {
            currentFileSizeBytes = nil
            currentFileSizeAssetId = nil
            return
        }
        guard currentFileSizeAssetId != asset.localIdentifier else { return }

        currentFileSizeBytes = nil
        let assetId = asset.localIdentifier
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .video || $0.type == .fullSizeVideo
        }) ?? resources.first else { return }

        Task {
            let sizeBytes = (resource.value(forKey: "fileSize") as? Int64) ?? 0
            await MainActor.run {
                guard remainingAssets.first?.localIdentifier == assetId, sizeBytes > 0 else { return }
                currentFileSizeBytes = sizeBytes
                currentFileSizeAssetId = assetId
            }
        }
    }

    private func loadNextFileSize() {
        nextFileSizeBytes = nil
        guard let asset = nextAsset else { return }
        let assetId = asset.localIdentifier
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: {
            $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .video || $0.type == .fullSizeVideo
        }) ?? resources.first else { return }

        Task {
            let sizeBytes = (resource.value(forKey: "fileSize") as? Int64) ?? 0
            await MainActor.run {
                guard nextAsset?.localIdentifier == assetId, sizeBytes > 0 else { return }
                nextFileSizeBytes = sizeBytes
            }
        }
    }

    private func cardView(for asset: PHAsset) -> some View {
        GeometryReader { geo in
            Group {
                if asset.mediaType == .video {
                    VideoCardView(
                        asset: asset,
                        cornerRadius: 28,
                        bottomInset: 110,
                        preloadedItem: preloadedVideoItems.removeValue(forKey: asset.localIdentifier),
                        preloadedPosterImage: currentImage
                    )
                    .id(asset.localIdentifier)
                    .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    if let image = currentImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .overlay(Rectangle().fill(.ultraThinMaterial))
                            .overlay(ProgressView())
                    }
                }
            }
        }
        .background(Color.black)
    }

    private func swipeDelete(asset: PHAsset) {
        advanceToNextCard {
            swipeStore.markDelete(asset.localIdentifier, isVideo: asset.mediaType == .video)
        }
        checkAchievements()
    }

    private func swipeKeep(asset: PHAsset) {
        advanceToNextCard {
            swipeStore.markKeep(asset.localIdentifier, isVideo: asset.mediaType == .video)
        }
        checkAchievements()
    }

    private func checkAchievements() {
        _ = achievementStore.checkForNewUnlock(
            swipeStore: swipeStore, stats: deletionStatsStore, streak: streakTracker
        )
    }

    private func swipeSkip(asset: PHAsset) {
        advanceToNextCard {
            sessionSkippedIds.append(asset.localIdentifier)
        }
    }

    private func advanceToNextCard(performMark: () -> Void) {
        let upcomingId = nextAsset?.localIdentifier
        if nextFileSizeBytes != nil {
            currentFileSizeBytes = nextFileSizeBytes
            currentFileSizeAssetId = upcomingId
        }
        nextFileSizeBytes = nil
        performMark()
        rebuildRemainingAssets()
    }

    @State private var currentImageRequestID: PHImageRequestID?
    @State private var nextImageRequestID: PHImageRequestID?

    private func loadCurrentImage() {
        guard let asset = remainingAssets.first else { return }
        if let requestID = currentImageRequestID {
            photoService.cancelRequest(requestID)
            currentImageRequestID = nil
        }
        guard loadedImages[asset.localIdentifier] == nil else { return }

        let assetId = asset.localIdentifier
        currentImageRequestID = photoService.loadImageProgressive(
            for: asset,
            targetSize: cardImageTargetSize
        ) { image, isDegraded in
            Task { @MainActor in
                guard remainingAssets.first?.localIdentifier == assetId || nextAsset?.localIdentifier == assetId else { return }
                guard let image else { return }
                if isDegraded && loadedImages[assetId] != nil { return }
                loadedImages[assetId] = image
            }
        }
    }

    private func loadNextImage() {
        guard let asset = nextAsset else { return }
        if let requestID = nextImageRequestID {
            photoService.cancelRequest(requestID)
            nextImageRequestID = nil
        }
        guard loadedImages[asset.localIdentifier] == nil else { return }

        let assetId = asset.localIdentifier
        nextImageRequestID = photoService.loadImageProgressive(
            for: asset,
            targetSize: cardImageTargetSize
        ) { image, isDegraded in
            Task { @MainActor in
                guard remainingAssets.first?.localIdentifier == assetId || nextAsset?.localIdentifier == assetId else { return }
                guard let image else { return }
                if isDegraded && loadedImages[assetId] != nil { return }
                loadedImages[assetId] = image
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.keepGreen)
            Text("Alles durchgesehen!")
                .font(.title2).bold()
            Text("Für diese Auswahl gibt es gerade nichts mehr zu swipen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// Helper für das Identifiable-Binding von UIImage
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
