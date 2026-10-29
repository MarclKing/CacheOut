import SwiftUI

struct DeleteToolbarModifier: ViewModifier {
    @Binding var showDeleteSheet: Bool
    // Optionaler zweiter Button links vom Löschen-Button. Sichtbar ist er
    // ein Glas-Overlay im Window (DeleteBadgeWindowManager); in der Toolbar
    // sitzt nur ein unsichtbarer Platzhalter, der die Position meldet.
    let leadingIcon: String?
    let leadingAction: (() -> Void)?

    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(FileSwipeViewModel.self) private var fileViewModel
    @State private var buttonFrameInWindow: CGRect = .zero
    @State private var leadingFrameInWindow: CGRect = .zero
    // Nur wenn TRUE darf diese Instanz den globalen Overlay-Singleton beschreiben.
    @State private var isScreenActive = false
    @State private var screenID = UUID()

    private var photoCount: Int {
        swipeStore.deleteQueueIds.count
    }
    private var fileCount: Int {
        fileViewModel.deleteQueue.count
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let leadingIcon {
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: leadingIcon)
                            .font(.system(size: 18, weight: .medium))
                            .opacity(0)
                            .allowsHitTesting(false)
                            .frame(width: 44, height: 44)
                            .background(
                                DeleteButtonFrameReporter { frame in
                                    leadingFrameInWindow = frame
                                    updateBadge(leadingFrame: frame)
                                }
                            )
                    }
                    .sharedBackgroundVisibility(.hidden)

                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 19, weight: .medium))
                        .opacity(0)
                        .allowsHitTesting(false)
                        .frame(width: 44, height: 44)
                        .background(
                            DeleteButtonFrameReporter { frame in
                                buttonFrameInWindow = frame
                                updateBadge(trashFrame: frame)
                            }
                        )
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background(
                ScreenAppearanceReporter(
                    onAppear: {
                        isScreenActive = true
                        DeleteBadgeWindowManager.shared.screenDidAppear(screenID)
                        updateBadge()
                    },
                    onDisappear: {
                        isScreenActive = false
                        DeleteBadgeWindowManager.shared.screenDidDisappear(screenID)
                    }
                )
            )
            .onChange(of: photoCount) { _, _ in updateBadge() }
            .onChange(of: fileCount) { _, _ in updateBadge() }
    }

    private func updateBadge(trashFrame: CGRect? = nil, leadingFrame: CGRect? = nil) {
        guard isScreenActive else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: \.isKeyWindow) else { return }

        var leading: DeleteBadgeWindowManager.LeadingButtonSpec?
        if let leadingIcon, let leadingAction {
            leading = .init(
                icon: leadingIcon,
                frame: leadingFrame ?? leadingFrameInWindow,
                onTap: leadingAction
            )
        }

        DeleteBadgeWindowManager.shared.update(
            photoCount: photoCount,
            fileCount: fileCount,
            buttonFrame: trashFrame ?? buttonFrameInWindow,
            onTap: { showDeleteSheet = true },
            leading: leading,
            in: window
        )
    }
}

extension View {
    /// Löschen-Button, optional mit zweitem Glas-Button links davon.
    func deleteToolbarButton(
        showDeleteSheet: Binding<Bool>,
        leadingIcon: String? = nil,
        leadingAction: (() -> Void)? = nil
    ) -> some View {
        modifier(DeleteToolbarModifier(
            showDeleteSheet: showDeleteSheet,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction
        ))
    }
}
