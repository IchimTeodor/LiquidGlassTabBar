import SwiftUI
import UIKit
import LiquidGlassTabBar

/// Reference host: a plain UITabBarController with its NATIVE tab bar
/// visible and untouched — no custom bar, no lens overrides. Same four
/// tabs and mock rows as the other hosts, so side-by-side screenshots
/// compare ONLY the bars: the real iOS 26 Liquid Glass tab bar (drag a
/// finger across it to see the system lens) versus the custom
/// ShrinkingTabBar's lens implementations. The native minimize-on-scroll
/// behavior is enabled too (the UIKit counterpart of SwiftUI's
/// `.tabBarMinimizeBehavior(.onScrollDown)`), so the system's shrink can
/// be compared directly against ShrinkingTabBar's scroll-driven shrink.
struct NativeHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        if #available(iOS 26.0, *) {
            controller.tabBarMinimizeBehavior = .onScrollDown
        }
        controller.viewControllers = MockData.tabs.enumerated().map { index, item in
            let content = MockListViewController(rows: MockData.rows(for: index),
                                                 bottomInset: 0)
            content.tabBarItem = UITabBarItem(title: item.title,
                                              image: item.image(selected: false),
                                              tag: index)
            return content
        }
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {}
}
