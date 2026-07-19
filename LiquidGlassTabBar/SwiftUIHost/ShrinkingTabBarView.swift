import SwiftUI

/// SwiftUI wrapper around the shared UIKit `ShrinkingTabBar`.
struct ShrinkingTabBarView: UIViewRepresentable {
    let items: [TabItem]
    @Binding var selectedIndex: Int
    let coordinator: ShrinkCoordinator

    func makeUIView(context: Context) -> ShrinkingTabBar {
        let bar = ShrinkingTabBar(items: items)
        bar.onSelect = { selectedIndex = $0 }
        coordinator.bar = bar
        return bar
    }

    func updateUIView(_ bar: ShrinkingTabBar, context: Context) {
        bar.selectedIndex = selectedIndex
    }
}
