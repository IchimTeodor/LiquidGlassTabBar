import SwiftUI

/// Embeds the UIKit host in the SwiftUI root.
struct UIKitHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIKitHostViewController {
        UIKitHostViewController()
    }

    func updateUIViewController(_ controller: UIKitHostViewController, context: Context) {}
}
