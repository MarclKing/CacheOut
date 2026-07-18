import SwiftUI

struct UnifiedDeleteConfirmSheet: View {
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(FileSwipeViewModel.self) private var fileViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: DeleteTab = .media
    @State private var mediaRemaining = 0
    @State private var mediaExcluded = 0
    @State private var mediaBytes: Int64 = 0
    @State private var fileRemaining = 0
    @State private var fileExcluded = 0
    @State private var fileBytes: Int64 = 0
    @State private var triggerDelete = false
    @State private var triggerRestore = false
    @Namespace private var glassNamespace

    nonisolated enum DeleteTab: Hashable, Sendable {
        case media
        case files
    }

    private var remainingCount: Int {
        selectedTab == .media ? mediaRemaining : fileRemaining
    }
    private var excludedCount: Int {
        selectedTab == .media ? mediaExcluded : fileExcluded
    }
    private var remainingBytes: Int64 {
        selectedTab == .media ? mediaBytes : fileBytes
    }
    private var remainingSizeText: String? {
        guard remainingBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: remainingBytes, countStyle: .file)
    }

    var body: some View {
        ZStack {
            AppTheme.background(colorScheme).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                tabSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                hintRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                content
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [AppTheme.background(colorScheme), AppTheme.background(colorScheme).opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 16)
                        .allowsHitTesting(false)
                    }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .onChange(of: selectedTab) {
            triggerDelete = false
            triggerRestore = false
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            PhotoDeleteContent(
                onRequestDismiss: { dismiss() },
                triggerDelete: $triggerDelete,
                triggerRestore: $triggerRestore,
                onCountsChange: { remaining, excluded, bytes in
                    withAnimation(.snappy) {
                        mediaRemaining = remaining
                        mediaExcluded = excluded
                        mediaBytes = bytes
                    }
                }
            )
            .opacity(selectedTab == .media ? 1 : 0)
            .allowsHitTesting(selectedTab == .media)

            FileDeleteContent(
                onRequestDismiss: { dismiss() },
                triggerDelete: $triggerDelete,
                triggerRestore: $triggerRestore,
                onCountsChange: { remaining, excluded, bytes in
                    withAnimation(.snappy) {
                        fileRemaining = remaining
                        fileExcluded = excluded
                        fileBytes = bytes
                    }
                }
            )
            .opacity(selectedTab == .files ? 1 : 0)
            .allowsHitTesting(selectedTab == .files)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            Spacer()

            Text("Löschen bestätigen")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
    }

    // MARK: - Tab-Umschalter

    private var tabSelector: some View {
        HStack(spacing: 12) {
            tabTile(
                title: "Medien",
                icon: "photo.on.rectangle.angled",
                count: swipeStore.deleteQueueIds.count,
                tint: AppTheme.deleteRed,
                tab: .media
            )
            tabTile(
                title: "Dateien",
                icon: "doc.fill",
                count: fileViewModel.deleteQueue.count,
                tint: AppTheme.skipBlue,
                tab: .files
            )
        }
    }

    private func tabTile(title: String, icon: String, count: Int, tint: Color, tab: DeleteTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            tabTileLabel(title: title, icon: icon, count: count, tint: tint)
        }
        .buttonStyle(.plain)
        .glassEffect(tabGlassStyle(tint: tint, isSelected: isSelected), in: tabTileShape)
        .overlay {
            tabTileBorder(tint: tint, isSelected: isSelected)
        }
        .glassEffectID(tab, in: glassNamespace)
    }

    private var tabTileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private func tabGlassStyle(tint: Color, isSelected: Bool) -> Glass {
        guard isSelected else { return .regular.interactive() }
        return .regular.tint(tint.opacity(0.16)).interactive()
    }

    @ViewBuilder
    private func tabTileBorder(tint: Color, isSelected: Bool) -> some View {
        if isSelected {
            tabTileShape.stroke(tint.opacity(0.55), lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private func tabTileLabel(title: String, icon: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    private var hintRow: some View {
        HStack {
            Text(hintText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var hintText: String {
        if remainingCount == 0 {
            return "Alles ausgeschlossen – nichts zu löschen"
        } else if excludedCount > 0 {
            return "Tippe zum Ausschließen · \(excludedCount) ausgenommen"
        } else {
            return "Tippe zum Ausschließen"
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if excludedCount > 0 {
                    restoreButton
                }
                deleteButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var restoreButton: some View {
        Button {
            triggerRestore = true
        } label: {
            Label("\(excludedCount) behalten", systemImage: "arrow.uturn.backward")
                .font(.subheadline).bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .tint(AppTheme.keepGreen)
        .controlSize(.large)
        .glassEffectID("restore", in: glassNamespace)
        .transition(.scale.combined(with: .opacity))
    }

    private var deleteButton: some View {
        Button {
            triggerDelete = true
        } label: {
            VStack(spacing: 1) {
                Label("\(remainingCount) löschen", systemImage: "trash.fill")
                    .font(.subheadline.weight(.medium))
                if let sizeText = remainingSizeText {
                    Text(sizeText)
                        .font(.caption2)
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .padding(.vertical, 2)
        }
        .buttonStyle(.glass)
        .tint(AppTheme.deleteRed)
        .controlSize(.regular)
        .disabled(remainingCount == 0)
        .glassEffectID("delete", in: glassNamespace)
    }
}
