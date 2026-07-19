import Testing
import UIKit
@testable import LiquidGlassTabBar

@MainActor
struct ScrollShrinkObserverTests {
    @Test func kvoFeedsCoordinatorDuringDrag() {
        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        let observer = ScrollShrinkObserver(coordinator: coordinator)
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.contentSize = CGSize(width: 400, height: 2000)
        observer.attach(to: scrollView)

        coordinator.dragBegan() // pan gesture state can't be simulated; drive the gate directly
        scrollView.contentOffset = CGPoint(x: 0, y: 100) // baseline sample
        scrollView.contentOffset = CGPoint(x: 0, y: 180) // +80pt -> full shrink
        #expect(coordinator.model.progress == 1)
    }

    @Test func scrollsOutsideADragAreIgnored() {
        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        let observer = ScrollShrinkObserver(coordinator: coordinator)
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.contentSize = CGSize(width: 400, height: 2000)
        observer.attach(to: scrollView)

        scrollView.contentOffset = CGPoint(x: 0, y: 180) // no dragBegan
        #expect(coordinator.model.progress == 0)
    }
}
