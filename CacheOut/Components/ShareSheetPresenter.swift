import UIKit

enum ShareSheetPresenter {
    static func present(items: [Any]) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // Für iPad nötig, auf iPhone schadet es nicht
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        }

        topVC.present(activityVC, animated: true)
    }
}
