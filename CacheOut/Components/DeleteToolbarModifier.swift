import SwiftUI

struct DeleteToolbarModifier<Leading: View>: ViewModifier {
    @Binding var showDeleteSheet: Bool
    @Environment(SwipeStateStore.self) private var swipeStore
    @Environment(FileSwipeViewModel.self) private var fileViewModel
    @State private var buttonFrameInWindow: CGRect = .zero
    // Nur wenn TRUE darf diese Instanz den globalen Badge-Singleton
    // beschreiben — verhindert, dass Hintergrund-Tabs sich gegenseitig
    // die Badge-Position/Sichtbarkeit "klauen".
    @State private var isScreenActive = false
    // NEU: stabile ID pro Modifier-Instanz
    @State private var screenID = UUID()
    // Zusätzlicher Button links vom Löschen-Button (z. B. Ordner wechseln).
    // Bewusst als eigene Button-Instanz, NICHT zusammengefügt — beide bleiben
    // separat antippbar, nur die Reihenfolge in der ToolbarItemGroup ist fix.
    @ViewBuilder var leadingButton: () -> Leading

    private var photoCount: Int {
        swipeStore.deleteQueueIds.count
    }
    private var fileCount: Int {
        fileViewModel.deleteQueue.count
    }

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    leadingButton()
                }

                // ToolbarSpacer erzwingt eine sichtbare Lücke UND zwei
                // getrennte Glass-Container — ohne ihn fasst Liquid Glass
                // benachbarte .topBarTrailing-Items zu einer Kachel zusammen,
                // selbst wenn es zwei eigene Button-Instanzen sind.
                ToolbarSpacer(.fixed, placement: .topBarTrailing)

                ToolbarItem(placement: .topBarTrailing) {
                    // Bewusst KEIN Button mehr — nur ein reines Image als
                    // Platzhalter. Ein Button hätte automatisch sein eigenes
                    // Liquid-Glass-Chrome (inkl. Akzentfarben-Tönung), auch
                    // bei opacity(0) auf dem Inhalt. Der sichtbare, antippbare
                    // Button lebt jetzt komplett in DeleteBadgeWindowManager.
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .medium))
                        .opacity(0)
                        .allowsHitTesting(false)
                    .background(
                        DeleteButtonFrameReporter { frame in
                            buttonFrameInWindow = frame
                            updateBadge(frame: frame)
                        }
                    )
                }
            }
            .background(
                ScreenAppearanceReporter(
                    onAppear: {
                        isScreenActive = true
                        DeleteBadgeWindowManager.shared.screenDidAppear(screenID)
                        updateBadge(frame: buttonFrameInWindow)
                    },
                    onDisappear: {
                        isScreenActive = false
                        DeleteBadgeWindowManager.shared.screenDidDisappear(screenID)
                    }
                )
            )
            .onChange(of: photoCount) { _, _ in
                updateBadge(frame: buttonFrameInWindow)
            }
            .onChange(of: fileCount) { _, _ in
                updateBadge(frame: buttonFrameInWindow)
            }
    }

    private func updateBadge(frame: CGRect) {
        // Kernfix: nur der wirklich sichtbare Screen darf schreiben.
        guard isScreenActive else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: \.isKeyWindow) else { return }
        DeleteBadgeWindowManager.shared.update(
            photoCount: photoCount,
            fileCount: fileCount,
            buttonFrame: frame,
            onTap: { showDeleteSheet = true },
            in: window
        )
    }
}

extension View {
    /// Variante mit zusätzlichem Button links vom Löschen-Button.
    func deleteToolbarButton<Leading: View>(
        showDeleteSheet: Binding<Bool>,
        @ViewBuilder leading: @escaping () -> Leading
    ) -> some View {
        modifier(DeleteToolbarModifier(showDeleteSheet: showDeleteSheet, leadingButton: leading))
    }

    /// Bestehende Call-Sites (z. B. Foto-Tab) ohne linken Button bleiben unverändert lauffähig.
    func deleteToolbarButton(showDeleteSheet: Binding<Bool>) -> some View {
        modifier(DeleteToolbarModifier(showDeleteSheet: showDeleteSheet, leadingButton: { EmptyView() }))
    }
}
