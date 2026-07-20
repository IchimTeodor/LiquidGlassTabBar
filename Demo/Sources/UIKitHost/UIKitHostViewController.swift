import UIKit
import LiquidGlassTabBar

/// 4-tab mock host built on UITabBarController (system tab bar hidden),
/// using the same bar variants as the SwiftUI host.
///
/// Nothing here attaches scroll tracking: the bar's `minimizesOnScroll`
/// (on by default) finds whichever table view is being dragged, including
/// the tabs that have not been built yet at this point.
final class UIKitHostViewController: UITabBarController {
    var variant: BarVariant = .metal {
        didSet {
            guard variant != oldValue, isViewLoaded else { return }
            installBar()
        }
    }
    private var shrinkBar: (UIView & ShrinkableBar)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        viewControllers = MockData.tabs.indices.map { index in
            MockListViewController(rows: MockData.rows(for: index))
        }

        tabBar.isHidden = true
        installBar()
    }

    /// Builds the bar for the current variant, replacing any previous one
    /// (selection is carried over so switching variants doesn't reset tabs).
    private func installBar() {
        let previousSelection = shrinkBar?.selectedIndex ?? selectedIndex
        shrinkBar?.removeFromSuperview()

        let bar: UIView & ShrinkableBar = switch variant {
        case .pill: PillTabBar(items: MockData.tabs)
        case .metal: ShrinkingTabBar(items: MockData.tabs)
        }
        bar.selectedIndex = previousSelection
        bar.onSelect = { [weak self] index in
            guard let self, self.selectedIndex != index else { return }
            self.selectedIndex = index
        }
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            bar.heightAnchor.constraint(equalToConstant: 64),
        ])
        shrinkBar = bar
    }
}
