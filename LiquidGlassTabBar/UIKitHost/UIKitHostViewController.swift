import UIKit

/// 4-tab mock host built on UITabBarController (system tab bar hidden),
/// using the same ShrinkingTabBar and ShrinkCoordinator as the SwiftUI host.
/// Scroll tracking is attached per scroll view by ScrollShrinkObserver;
/// the content controllers know nothing about the bar.
final class UIKitHostViewController: UITabBarController {
    private let coordinator = ShrinkCoordinator()
    private lazy var scrollObserver = ScrollShrinkObserver(coordinator: coordinator)
    private let shrinkBar = ShrinkingTabBar(items: MockData.tabs)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        viewControllers = MockData.tabs.indices.map { index in
            let controller = MockListViewController(rows: MockData.rows(for: index))
            scrollObserver.attach(to: controller.tableView)
            return controller
        }

        tabBar.isHidden = true

        coordinator.bar = shrinkBar
        shrinkBar.onSelect = { [weak self] index in
            guard let self, self.selectedIndex != index else { return }
            self.selectedIndex = index
            self.coordinator.tabChanged()
        }
        shrinkBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shrinkBar)
        NSLayoutConstraint.activate([
            shrinkBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            shrinkBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            shrinkBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
            shrinkBar.heightAnchor.constraint(equalToConstant: 64),
        ])
    }
}
