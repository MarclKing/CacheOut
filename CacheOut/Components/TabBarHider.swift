import SwiftUI
import UIKit

final class TabBarHiderViewController: UIViewController {
    var isHidden: Bool = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabBarController?.tabBar.isHidden = isHidden
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // WICHTIG: Navbar beim Verlassen dieses Screens immer wieder einblenden
        tabBarController?.tabBar.isHidden = false
    }
}

struct TabBarHider: UIViewControllerRepresentable {
    let isHidden: Bool

    func makeUIViewController(context: Context) -> TabBarHiderViewController {
        let vc = TabBarHiderViewController()
        vc.isHidden = isHidden
        return vc
    }

    func updateUIViewController(_ uiViewController: TabBarHiderViewController, context: Context) {
        uiViewController.isHidden = isHidden
        DispatchQueue.main.async {
            uiViewController.tabBarController?.tabBar.isHidden = isHidden
        }
    }
}

extension View {
    func hidesTabBar(_ hidden: Bool = true) -> some View {
        background(TabBarHider(isHidden: hidden))
    }
}
