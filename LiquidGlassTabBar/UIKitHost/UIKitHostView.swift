import SwiftUI

/// Embeds the UIKit host in the SwiftUI root.
struct UIKitHostView: UIViewControllerRepresentable {
    var variant: BarVariant = .metal

    func makeUIViewController(context: Context) -> UIKitHostViewController {
        let controller = UIKitHostViewController()
        controller.variant = variant
        return controller
    }

    func updateUIViewController(_ controller: UIKitHostViewController, context: Context) {
        controller.variant = variant
    }
}
