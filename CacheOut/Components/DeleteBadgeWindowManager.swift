import SwiftUI
import UIKit

@MainActor
final class DeleteBadgeWindowManager {
    static let shared = DeleteBadgeWindowManager()

    private var photoHostingController: UIHostingController<DeleteBadgeOverlayContent>?
    private var fileHostingController: UIHostingController<DeleteBadgeOverlayContent>?
    private var buttonHostingController: UIHostingController<DeleteButtonOverlayContent>?
    private var currentOnTap: (() -> Void)?

    // Rot, oben-links vom Button = Fotos. Blau, oben-rechts = Dateien.
    private let photoColor = Color(red: 1, green: 0.27, blue: 0.23)
    private let fileColor = Color(red: 0.15, green: 0.47, blue: 1.0)

    // Letzte bekannte Button-Position — überbrückt die kurze Lücke zwischen
    // "neuer Screen ist da" und "FrameReporter hat die ECHTE Position
    // gemeldet". Der Button sitzt layoutmäßig fast immer an derselben
    // Stelle, daher verschwindet das Badge dadurch nicht mehr kurz.
    private(set) var lastKnownButtonFrame: CGRect = .zero

    // KERNFIX: statt sofort zu verstecken, wird das Verstecken verzögert
    // angestoßen. Meldet sich innerhalb dieser Zeitspanne ein anderer Screen
    // (z. B. das neue Tab nach dem Wechsel) über update(...), wird der
    // geplante Hide gecancelt, BEVOR er ausgeführt wird — das Badge bleibt
    // die ganze Zeit sichtbar, kein Entfernen+Neueinfügen in getrennten
    // Frames mehr, also kein Flackern.
    private var pendingHideWorkItem: DispatchWorkItem?
    private var updateToken: Int = 0

    // NEU: Set aktiver Screens statt reinem Zeit-Token — löst die
    // Appear/Disappear-Race unabhängig von der Reihenfolge der Events.
    private var activeScreens: Set<UUID> = []

    func screenDidAppear(_ id: UUID) {
        activeScreens.insert(id)
        cancelPendingHide()
    }

    func screenDidDisappear(_ id: UUID) {
        activeScreens.remove(id)
        guard activeScreens.isEmpty else { return }
        requestHide()
    }

    func requestHide() {
        updateToken &+= 1
        let tokenAtRequest = updateToken
        pendingHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            // Zusätzlich zum Token nochmal live prüfen: falls zwischenzeitlich
            // doch ein Screen aktiv wurde, NICHT verstecken.
            guard let self, self.updateToken == tokenAtRequest, self.activeScreens.isEmpty else { return }
            self.hide()
        }
        pendingHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func cancelPendingHide() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
    }

    // NEU: für Screens, die den Button NIE zeigen (z. B. Profil-Tab) — sofortiges
    // Verstecken statt über den 0.3s-Delay-Pfad. Verhindert, dass beim Wechsel
    // auf so einen Screen der alte Button noch kurz sichtbar ist und sich mit
    // einem eigenen Toolbar-Button des neuen Screens überlagert.
    func forceHideNow() {
        pendingHideWorkItem?.cancel()
        pendingHideWorkItem = nil
        updateToken &+= 1
        hide()
    }

    func update(photoCount: Int, fileCount: Int, buttonFrame: CGRect, onTap: @escaping () -> Void, in window: UIWindow) {
        // Jeder erfolgreiche update()-Aufruf heißt: irgendein Screen will das
        // Badge JETZT zeigen — ein evtl. geplantes Verstecken ist dann obsolet.
        updateToken &+= 1
        cancelPendingHide()

        let frame = buttonFrame == .zero ? lastKnownButtonFrame : buttonFrame
        guard frame != .zero else {
            hide()
            return
        }
        lastKnownButtonFrame = frame
        currentOnTap = onTap

        // NEU: der eigentliche sichtbare Button lebt jetzt hier — genau wie
        // die Badges nie neu erzeugt, nur positioniert/aktualisiert. Muss VOR
        // den Badges liegen, damit updateBadge() sie via bringSubviewToFront
        // korrekt darüber legt.
        updateButtonOverlay(buttonFrame: frame, in: window)

        updateBadge(
            count: photoCount,
            color: photoColor,
            controller: &photoHostingController,
            anchor: .topLeading,
            buttonFrame: frame,
            in: window
        )
        updateBadge(
            count: fileCount,
            color: fileColor,
            controller: &fileHostingController,
            anchor: .topTrailing,
            buttonFrame: frame,
            in: window
        )
    }

    private enum Anchor {
        case topLeading
        case topTrailing
    }

    private func updateBadge(
        count: Int,
        color: Color,
        controller: inout UIHostingController<DeleteBadgeOverlayContent>?,
        anchor: Anchor,
        buttonFrame: CGRect,
        in window: UIWindow
    ) {
        guard count > 0 else {
            controller?.view.isHidden = true
            return
        }

        let badgeSize: CGFloat = count > 99 ? 30 : (count > 9 ? 22 : 18)
        let x: CGFloat
        switch anchor {
        case .topLeading:
            x = buttonFrame.minX - badgeSize * 0.6
        case .topTrailing:
            x = buttonFrame.maxX - badgeSize * 0.4
        }
        let frame = CGRect(x: x, y: buttonFrame.minY - badgeSize * 0.4, width: badgeSize, height: badgeSize)
        let content = DeleteBadgeOverlayContent(count: count, color: color)

        if let existing = controller {
            // Wiederverwenden statt neu bauen — dadurch kein sichtbares
            // "Nachladen" mehr beim Screen-Wechsel.
            existing.rootView = content
            existing.view.frame = frame
            existing.view.isHidden = false
            if existing.view.superview !== window {
                window.addSubview(existing.view)
            }
        } else {
            let newController = UIHostingController(rootView: content)
            newController.view.backgroundColor = .clear
            newController.view.isUserInteractionEnabled = false
            newController.view.frame = frame
            window.addSubview(newController.view)
            newController.view.layoutIfNeeded()
            controller = newController
        }

        window.bringSubviewToFront(controller!.view)
    }

    // NEU: analog zu updateBadge(), aber für den Löschen-Button selbst.
    // rootView wird bewusst nur EINMAL bei Erstellung gesetzt (Inhalt ändert
    // sich nie) — onTap wird über currentOnTap indirekt zur Laufzeit
    // aufgelöst, dadurch ist kein SwiftUI-Rerender bei jedem update() nötig,
    // nur Frame + isHidden werden angepasst.
    private func updateButtonOverlay(buttonFrame: CGRect, in window: UIWindow) {
        if let existing = buttonHostingController {
            existing.view.frame = buttonFrame
            existing.view.isHidden = false
            if existing.view.superview !== window {
                window.addSubview(existing.view)
            }
        } else {
            let content = DeleteButtonOverlayContent(onTap: { [weak self] in self?.currentOnTap?() })
            let newController = UIHostingController(rootView: content)
            newController.view.backgroundColor = .clear
            newController.view.frame = buttonFrame
            window.addSubview(newController.view)
            newController.view.layoutIfNeeded()
            buttonHostingController = newController
        }
        window.bringSubviewToFront(buttonHostingController!.view)
    }

    // NEU: nur verstecken statt zerstören — Wiedereinblenden ist dann
    // ein reines isHidden-Toggle, ohne neuen UIHostingController + SwiftUI-Renderpass.
    func hide() {
        photoHostingController?.view.isHidden = true
        fileHostingController?.view.isHidden = true
        buttonHostingController?.view.isHidden = true
    }
}

struct DeleteBadgeOverlayContent: View {
    let count: Int
    let color: Color

    // NEU: ab 100 wird "99+" angezeigt statt der vollen (dreistelligen) Zahl —
    // verhindert, dass das Badge bei großen Lösch-Mengen abgeschnitten oder
    // gequetscht dargestellt wird.
    private var displayText: String {
        count > 99 ? "99+" : "\(count)"
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, count > 9 ? 3 : 0)
            .background(color, in: Capsule())
    }
}

// NEU: der tatsächlich sichtbare/antippbare Löschen-Button, jetzt als
// persistentes Fenster-Overlay statt natives ToolbarItem — dadurch beim
// Tab-Wechsel nie mehr zerstört/neu erzeugt, also kein Flackern mehr.
struct DeleteButtonOverlayContent: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "trash.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Circle())
    }
}
