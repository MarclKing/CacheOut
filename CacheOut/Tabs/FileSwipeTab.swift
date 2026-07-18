import SwiftUI
import UniformTypeIdentifiers

struct FileSwipeTab: View {
    @Environment(FileSwipeViewModel.self) private var viewModel
    @State private var showDocumentPicker = false
    @State private var showFilterSheet = false
    @State private var hasStarted = false
    @State private var showDeleteSheet = false
    @State private var showResumeFailedAlert = false
    @State private var pendingAction: SwipeAction?

    private var isOnDeckScreen: Bool {
        hasStarted && !(viewModel.remainingFiles.isEmpty && !viewModel.isScanning)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasStarted {
                    startScreen
                } else if viewModel.remainingFiles.isEmpty && !viewModel.isScanning {
                    FileSwipeSummaryView(viewModel: viewModel) {
                        hasStarted = false
                    }
                } else {
                    deckScreen
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isOnDeckScreen {
                        ProgressTitleView()
                    } else {
                        Text("Dateien")
                            .font(.subheadline).bold()
                    }
                }
            }
            .deleteToolbarButton(showDeleteSheet: $showDeleteSheet) {
                changeFolderButton
            }
            .sheet(isPresented: $showDeleteSheet) {
                UnifiedDeleteConfirmSheet()
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            FolderPicker { url in
                viewModel.openFolder(url: url)
                hasStarted = true
                showFilterSheet = true
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSelectionView(viewModel: viewModel)
        }
    }

    // MARK: - Start

    private var startScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Ordner auswählen und aufräumen")
                .font(.title3).bold()

            Button("Ordner auswählen") {
                showDocumentPicker = true
            }
            .buttonStyle(.borderedProminent)

            Button("Letzten Ordner fortsetzen") {
                if viewModel.resumeLastFolder() {
                    hasStarted = true
                    showFilterSheet = true
                } else {
                    showResumeFailedAlert = true
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .alert("Ordner nicht erreichbar", isPresented: $showResumeFailedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Der zuletzt genutzte Ordner ist nicht mehr zugänglich. Bitte wähle ihn erneut aus.")
        }
    }

    private var changeFolderButton: some View {
        Button {
            showDocumentPicker = true
        } label: {
            Image(systemName: "folder.badge.gearshape")
        }
    }

    // MARK: - Deck-Screen
    // WICHTIG: wieder wie beim Foto-Swipe — Karte ignoriert oben die
    // Safe-Area (geht bis unter die Navbar, die dadurch automatisch
    // transparent/verblasst wird), unten bleibt die Safe-Area erhalten
    // (Tab-Bar bekommt ihren Platz, dadurch entsteht der Abstand
    // zwischen Icons und Tab-Bar).

    private var deckScreen: some View {
        ZStack {
            FileDeckCardLayer(pendingAction: $pendingAction)

            VStack(spacing: 0) {
                Spacer()
                bottomBar
            }
        }
    }

    private var bottomBarBottomInset: CGFloat { 28 }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                smallChromeButton(icon: "arrow.uturn.backward", color: .white.opacity(0.9)) {
                    viewModel.undoLast()
                }
                .disabled(!viewModel.canUndo)

                Spacer()

                bigChromeButton(icon: "xmark", color: AppTheme.deleteRed) {
                    guard viewModel.currentFile != nil else { return }
                    pendingAction = .delete
                }

                Spacer()

                smallChromeButton(icon: "arrow.down", color: AppTheme.skipBlue) {
                    guard viewModel.currentFile != nil else { return }
                    pendingAction = .skip
                }

                Spacer()

                bigChromeButton(icon: "heart.fill", color: AppTheme.keepGreen) {
                    guard viewModel.currentFile != nil else { return }
                    pendingAction = .keep
                }

                Spacer()

                smallChromeButton(icon: "square.and.arrow.up", color: .white.opacity(0.9)) {
                    guard let current = viewModel.currentFile else { return }
                    ShareSheetPresenter.present(items: [current.url])
                }
            }
            .padding(.horizontal, 24)

            progressChip
        }
        .padding(.bottom, bottomBarBottomInset)
    }

    private var progressChip: some View {
        let total = viewModel.remainingFiles.count + viewModel.keptCount + viewModel.deletedCount + viewModel.deleteQueue.count
        let done = viewModel.keptCount + viewModel.deletedCount + viewModel.deleteQueue.count
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
}

// MARK: - Titel mittig: "Datei X von Y" — GLEICHE Schriftgröße wie der
// restliche Titel-Text, nur die Zahlen ändern sich (keine eigene größere
// Schrift mehr für die vordere Zahl).

private struct ProgressTitleView: View {
    @Environment(FileSwipeViewModel.self) private var viewModel

    var body: some View {
        let total = viewModel.remainingFiles.count + viewModel.keptCount + viewModel.deletedCount + viewModel.deleteQueue.count
        let done = viewModel.keptCount + viewModel.deletedCount + viewModel.deleteQueue.count
        let current = min(done + 1, max(total, 1))

        Text("Datei \(current) von \(max(total, 1))")
            .font(.subheadline).bold()
            .foregroundStyle(.white)
    }
}

// MARK: - Karte + Scrims + Metadaten-Chips — eigene View, damit
// Thumbnail-Updates (Prefetch der nächsten Karten) NICHT den gesamten
// FileSwipeTab-Body (Bottom-Bar, Icons, Toolbar) neu zeichnen.

private struct FileDeckCardLayer: View {
    @Environment(FileSwipeViewModel.self) private var viewModel
    @Binding var pendingAction: SwipeAction?

    // NEU: Long-Press auf die aktuelle Karte öffnet die Vollansicht via
    // QuickLook — nur hier bei Dateien, nicht beim Foto-Swipe.
    @State private var previewItem: QuickLookItem?

    private static let cardShape = UnevenRoundedRectangle(
        topLeadingRadius: 40,
        bottomLeadingRadius: 40,
        bottomTrailingRadius: 40,
        topTrailingRadius: 40,
        style: .continuous
    )

    private let iconRowHeight: CGFloat = 64
    private let progressChipSpacing: CGFloat = 10
    private let progressChipHeight: CGFloat = 3
    private let bottomBarBottomInset: CGFloat = 28
    private var iconZoneHeight: CGFloat {
        iconRowHeight + progressChipSpacing + progressChipHeight + bottomBarBottomInset
    }
    private let bottomScrimBuffer: CGFloat = 12
    private let bottomScrimFadeHeight: CGFloat = 150
    private var bottomScrimHeight: CGFloat {
        iconZoneHeight + bottomScrimBuffer + bottomScrimFadeHeight
    }

        // NEU: Drag-to-Dismiss-State für die QuickLook-Vollansicht — 1:1 wie in
        // SwipeDeckView, damit sich Dateien und Fotos identisch verhalten.
        @State private var previewDragOffset: CGSize = .zero
        @State private var previewDragScale: CGFloat = 1

        var body: some View {
            GeometryReader { geo in
                let topGap = geo.safeAreaInsets.top + 20

                Group {
                    if let current = viewModel.currentFile {
                        SwipeCardContainer(
                            externalTrigger: $pendingAction,
                            onKeep: { viewModel.keep() },
                            onDelete: { viewModel.delete() },
                            onSkip: { viewModel.skipForNow() },
                            onSwipeUp: {   // NEU: Swipe nach oben öffnet dieselbe QuickLook-Vollansicht wie Long-Press
                                guard let current = viewModel.currentFile else { return }
                                previewItem = QuickLookItem(url: current.url)
                            },
                            content: {
                                fullCardView(for: current, topGap: topGap, interactive: true)
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.45)
                                            .onEnded { _ in
                                                previewItem = QuickLookItem(url: current.url)
                                            }
                                    )
                            },
                            nextContent: {
                                nextCardPreview(topGap: topGap)
                            }
                        )
                    } else if viewModel.isScanning {
                        scanningPlaceholder
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .padding(.bottom, 10)
            .fullScreenCover(item: $previewItem, onDismiss: {
                // NEU: Drag-State zurücksetzen, damit die nächste Preview nicht
                // versetzt/verkleinert startet
                previewDragOffset = .zero
                previewDragScale = 1
            }) { item in
                NavigationStack {
                    QuickLookPreview(item: item)
                        .ignoresSafeArea()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Fertig") { previewItem = nil }
                            }
                        }
                }
                // NEU: identisches Drag-to-Dismiss-Verhalten wie beim Foto-Swipe
                .offset(y: previewDragOffset.height)
                .scaleEffect(previewDragScale)
                .background(
                    Color.black
                        .opacity(1 - min(1, previewDragOffset.height / 400) * 0.5)
                        .ignoresSafeArea()
                )
                .gesture(
                    // minimumDistance: 20 lässt kleine vertikale Scroll-Bewegungen
                    // innerhalb der Preview (z.B. PDF-Scrollen) unangetastet —
                    // erst ab 20pt eindeutiger Zug greift die Dismiss-Geste.
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

        @ViewBuilder
        private func fullCardView(for item: FileItem, topGap: CGFloat, interactive: Bool) -> some View {
            FileCardView(
                item: item,
                thumbnail: viewModel.thumbnails[item.url],
                onRetryDownload: interactive ? { viewModel.retryDownload(for: item) } : nil,
                isAutoDownloadEnabled: viewModel.autoDownloadICloudEnabled,   // NEU
                // NEU: Doppeltipp öffnet die QuickLook-Vollansicht, analog zu Long-Press/Swipe-up.
                // Nur auf der interaktiven ("current") Karte, wie bei onRetryDownload.
                onOpenPreview: interactive ? { previewItem = QuickLookItem(url: item.url) } : nil
            )
            .padding(.top, topGap)
            .overlay(alignment: .top) { topCardScrim }
            .overlay(alignment: .bottom) { bottomCardScrim }
            .overlay(alignment: .bottomLeading) { metadataChips(for: item) }
            .clipShape(Self.cardShape)
        }

    @ViewBuilder
    private func nextCardPreview(topGap: CGFloat) -> some View {
        if let next = viewModel.nextFile {
            fullCardView(for: next, topGap: topGap, interactive: false)
        } else {
            Color.clear
        }
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Durchsuche Ordner… (\(viewModel.scannedCount))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Scrims (1:1 wie beim Foto-Swipe)

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

    // MARK: - Metadaten-Chips: MB + Datum NEBENEINANDER, Name-Chip darunter
    // in gleicher Optik (keine größere Schrift mehr).

    private func metadataChips(for item: FileItem) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    sizeChip(item)
                    if let date = item.modifiedDate {
                        dateChip(date)
                    }
                }
                nameChip(item)
            }

            Spacer(minLength: 0)

            // Öffnet dieselbe QuickLook-Vollansicht wie der Long-Press —
            // nur als expliziter Button, analog zum Tinder-Pfeil oben
            // rechts neben den Profil-Infos. Nur bei Dateien, nicht bei Fotos.
            expandButton(for: item)
        }
        .padding(.leading, 24)
        .padding(.trailing, 24)
        .padding(.bottom, iconZoneHeight + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandButton(for item: FileItem) -> some View {
        Button {
            previewItem = QuickLookItem(url: item.url)
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func sizeChip(_ item: FileItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive.fill")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
            Text(formattedFileSize(item.size))
                .font(.caption).bold()
                .foregroundStyle(.white)
            Circle()
                .fill(sizeTier(for: item.size).color)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func dateChip(_ date: Date) -> some View {
        Text(date, style: .date)
            .font(.caption).bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // Gleiche Optik wie die anderen Chips — keine größere Schrift/Kachel mehr.
    private func nameChip(_ item: FileItem) -> some View {
        Text(item.name)
            .font(.caption).bold()
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
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

    private func sizeTier(for bytes: Int64) -> FileSizeTier {
        let mb = Double(bytes) / 1_048_576
        if mb < 5 { return .low }
        if mb < 100 { return .medium }
        return .high
    }

    private func formattedFileSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 0.1 {
            let kb = Double(bytes) / 1024
            return String(format: "%.0f KB", kb)
        }
        return String(format: "%.1f MB", mb)
    }
}
