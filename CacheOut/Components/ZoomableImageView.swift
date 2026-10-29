import SwiftUI
import UIKit

// Ersetzt die reine SwiftUI-Lösung durch eine UIScrollView-basierte —
// UIScrollView zoomt nativ exakt um den Pinch-Punkt (wie Fotos-App/
// QuickLook), statt immer nur um die Mitte zu skalieren. isZoomed wird nach
// außen gemeldet, damit die äußere Schließen-Geste NUR aktiv ist, solange
// nicht gezoomt ist.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    @Binding var isZoomed: Bool

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 1
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isZoomed: $isZoomed)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        @Binding var isZoomed: Bool

        init(isZoomed: Binding<Bool>) {
            self._isZoomed = isZoomed
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        // NEU: feuert bereits beim ANSETZEN der zwei Finger, noch bevor sich
        // zoomScale überhaupt verändert. scrollViewDidZoom kam bisher zu spät —
        // in der kurzen Zeit dazwischen hatte SwiftUIs DragGesture (die JEDE
        // Touch-Bewegung mitbekommt, nicht nur Ein-Finger-Drags) schon genug
        // Bewegung registriert, um die Schließen-Geste auszulösen. Dadurch
        // gewann die Schließen-Geste das Rennen gegen die Zoom-Erkennung.
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZoomed = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // NEU: meldet nach außen, ob gerade gezoomt ist — die äußere
            // Schließen-Geste im fullScreenCover wird darüber gesteuert.
            isZoomed = scrollView.zoomScale > 1.01
        }

        // NEU: erst nach Ende der Zoom-Geste final entscheiden, ob wieder auf
        // zoomScale 1 zurückgesprungen wurde — verhindert ein zu frühes
        // Zurücksetzen von isZoomed noch während die Finger sich lösen.
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isZoomed = scale > 1.01
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let targetScale: CGFloat = 2.5
                let size = CGSize(
                    width: scrollView.bounds.width / targetScale,
                    height: scrollView.bounds.height / targetScale
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
