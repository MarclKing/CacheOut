import SwiftUI
import UIKit

// Unsichtbare Hilfsview, die bei jedem Layout-Pass die ECHTE Bildschirmposition
// (Fenster-Koordinaten) des Buttons meldet — per reinem UIKit-convert(),
// nicht über SwiftUI-PreferenceKeys (die aus dem Toolbar-Kontext nicht
// zuverlässig nach außen propagieren).
final class FrameReporterUIView: UIView {
    var onFrameChange: ((CGRect) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let window else { return }
        onFrameChange?(convert(bounds, to: window))
    }
}

struct DeleteButtonFrameReporter: UIViewRepresentable {
    var onFrameChange: (CGRect) -> Void

    func makeUIView(context: Context) -> FrameReporterUIView {
        let view = FrameReporterUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onFrameChange = onFrameChange
        return view
    }

    func updateUIView(_ uiView: FrameReporterUIView, context: Context) {
        uiView.onFrameChange = onFrameChange
        // Zusätzlicher Trigger, falls sich die Frame ändert ohne dass
        // layoutSubviews von selbst neu feuert (z. B. bei Badge-Zahlwechsel)
        DispatchQueue.main.async {
            if let window = uiView.window {
                onFrameChange(uiView.convert(uiView.bounds, to: window))
            }
        }
    }
}
