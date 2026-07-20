import UIKit

/// Drives the shared ShrinkCoordinator from any UIScrollView without the
/// scroll view's owner knowing about the tab bar: contentOffset is observed
/// via KVO, drag begin/end via the scroll view's own pan gesture recognizer.
/// One instance per host; attach each tab's scroll view once.
@MainActor
public final class ScrollShrinkObserver: NSObject {
    private let coordinator: ShrinkCoordinator
    private var observations: [NSKeyValueObservation] = []

    public init(coordinator: ShrinkCoordinator) {
        self.coordinator = coordinator
    }

    public func attach(to scrollView: UIScrollView) {
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        observations.append(scrollView.observe(\.contentOffset, options: [.new]) { [coordinator] scrollView, _ in
            let inset = scrollView.adjustedContentInset
            // NOTE: SwiftUI's .shrinksTabBar() feeds containerSize.height
            // (not inset-reduced). The shrink is delta-driven so behavior is
            // identical in practice; only the maxOffset clamp near the scroll
            // extremes differs by the inset total. Keep in mind if normalizing.
            coordinator.scrolled(offset: scrollView.contentOffset.y + inset.top,
                                 viewportHeight: scrollView.bounds.height - inset.top - inset.bottom,
                                 contentHeight: scrollView.contentSize.height)
        })
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            coordinator.dragBegan()
        case .ended, .cancelled, .failed:
            coordinator.dragEnded()
        default:
            break
        }
    }
}
