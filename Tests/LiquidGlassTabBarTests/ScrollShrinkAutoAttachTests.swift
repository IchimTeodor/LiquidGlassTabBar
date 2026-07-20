import Testing
import UIKit
@testable import LiquidGlassTabBar

/// Covers the "say it once" path: the bar finds the scroll view being
/// touched instead of the host attaching each one.
@MainActor
struct ScrollShrinkAutoAttachTests {
    /// A scroll view nested a few levels down, as in a real cell hierarchy.
    private func makeScrollView() -> (UIScrollView, UIView) {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.contentSize = CGSize(width: 400, height: 2000)
        let row = UIView()
        let label = UILabel()
        row.addSubview(label)
        scrollView.addSubview(row)
        return (scrollView, label)
    }

    @Test func touchingContentDiscoversItsScrollViewAndDrivesTheShrink() {
        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        let auto = ScrollShrinkAutoAttach(coordinator: coordinator)
        let (scrollView, deepSubview) = makeScrollView()

        // A touch on content buried inside the scroll view, not the scroll
        // view itself — the walk up the superview chain is the point.
        #expect(auto.noteTouch(on: deepSubview) === scrollView)

        coordinator.dragBegan() // pan state can't be simulated; drive the gate
        scrollView.contentOffset = CGPoint(x: 0, y: 100) // baseline sample
        scrollView.contentOffset = CGPoint(x: 0, y: 180) // +80pt -> full shrink
        #expect(coordinator.model.progress == 1)
    }

    @Test func touchOutsideAnyScrollViewDiscoversNothing() {
        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        let auto = ScrollShrinkAutoAttach(coordinator: coordinator)
        #expect(auto.noteTouch(on: UIView()) == nil)
        #expect(auto.noteTouch(on: nil) == nil)
    }

    /// Re-touching an already-known scroll view must not attach it again: a
    /// second KVO observer would count every offset change twice and shrink
    /// at double speed.
    @Test func repeatedTouchesDoNotDoubleCountScrolling() {
        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        let auto = ScrollShrinkAutoAttach(coordinator: coordinator)
        let (scrollView, deepSubview) = makeScrollView()

        for _ in 0..<3 { auto.noteTouch(on: deepSubview) }

        coordinator.dragBegan()
        scrollView.contentOffset = CGPoint(x: 0, y: 100) // baseline
        scrollView.contentOffset = CGPoint(x: 0, y: 140) // +40pt -> half shrink
        #expect(abs(coordinator.model.progress - 0.5) < 0.0001)
    }

    /// Each tab's scroll view is discovered on its own first touch, which is
    /// the case a one-shot hierarchy scan at install time would miss.
    @Test func scrollViewsAppearingLaterAreStillDiscovered() {
        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        let auto = ScrollShrinkAutoAttach(coordinator: coordinator)
        let (first, firstContent) = makeScrollView()
        auto.noteTouch(on: firstContent)

        // A second tab's scroll view, created only now.
        let (second, secondContent) = makeScrollView()
        #expect(auto.noteTouch(on: secondContent) === second)

        coordinator.dragBegan()
        second.contentOffset = CGPoint(x: 0, y: 100)
        second.contentOffset = CGPoint(x: 0, y: 180)
        #expect(coordinator.model.progress == 1)
        #expect(first.contentOffset.y == 0) // untouched
    }
}

@MainActor
struct AutomaticShrinkWiringTests {
    @Test func barInstallsAnInertProbeOnItsWindowWhenEnabled() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house")])
        #expect(bar.minimizesOnScroll) // on by default: the headline behaviour
        let before = window.gestureRecognizers?.count ?? 0
        window.addSubview(bar)

        let probes = (window.gestureRecognizers?.count ?? 0) - before
        #expect(probes == 1)
        // Inert: it must never swallow or delay a touch meant for content.
        let probe = try! #require(window.gestureRecognizers?.last)
        #expect(probe.cancelsTouchesInView == false)
        #expect(probe.delaysTouchesBegan == false)
        #expect(probe.delaysTouchesEnded == false)
    }

    @Test func turningItOffRemovesTheProbe() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house")])
        window.addSubview(bar)
        let withProbe = window.gestureRecognizers?.count ?? 0

        bar.minimizesOnScroll = false
        #expect((window.gestureRecognizers?.count ?? 0) == withProbe - 1)
    }

    /// Driving the bar from your own coordinator has to switch the automatic
    /// path off, or both would push progress into the same bar.
    @Test func assigningACoordinatorTakesOverFromTheAutomaticPath() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house")])
        window.addSubview(bar)
        #expect(bar.minimizesOnScroll)

        let coordinator = ShrinkCoordinator(isShrinkEnabled: true)
        coordinator.bar = bar

        #expect(bar.minimizesOnScroll == false)
        #expect(coordinator.bar === bar)
    }
}
