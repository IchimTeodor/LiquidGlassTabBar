import Testing
import UIKit
@testable import LiquidGlassTabBar

@MainActor
struct ShrinkCoordinatorTests {
    private func makeCoordinator() -> ShrinkCoordinator {
        ShrinkCoordinator(isShrinkEnabled: true)
    }

    /// offset samples are (offset, time); viewport 800, content 2000.
    private func drag(_ c: ShrinkCoordinator, samples: [(CGFloat, TimeInterval)]) {
        c.dragBegan()
        for (offset, time) in samples {
            c.scrolled(offset: offset, viewportHeight: 800, contentHeight: 2000, time: time)
        }
        c.dragEnded()
    }

    @Test func ignoresScrollsOutsideOfDrag() {
        let c = makeCoordinator()
        c.scrolled(offset: 100, viewportHeight: 800, contentHeight: 2000, time: 0)
        c.scrolled(offset: 180, viewportHeight: 800, contentHeight: 2000, time: 1)
        #expect(c.model.progress == 0)
    }

    @Test func slowDragSettlesToNearest() {
        let c = makeCoordinator()
        // 30pt down over 1s = 30pt/s, below fling threshold; progress 0.375 -> 0
        drag(c, samples: [(100, 0), (130, 1)])
        #expect(c.model.progress == 0)
        // 50pt down over 1s; progress 0.625 -> 1
        drag(c, samples: [(100, 2), (150, 3)])
        #expect(c.model.progress == 1)
    }

    @Test func fastFlingDownShrinksDespiteSmallDistance() {
        let c = makeCoordinator()
        // 30pt in 0.05s = 600pt/s > threshold; progress 0.375 -> 1
        drag(c, samples: [(100, 0), (130, 0.05)])
        #expect(c.model.progress == 1)
    }

    @Test func fastFlingUpRestores() {
        let c = makeCoordinator()
        drag(c, samples: [(100, 0), (180, 1)]) // settle at 1
        // fling up: 30pt in 0.05s upward
        drag(c, samples: [(180, 2), (150, 2.05)])
        #expect(c.model.progress == 0)
    }

    @Test func tabChangedResetsToFullSize() {
        let c = makeCoordinator()
        drag(c, samples: [(100, 0), (180, 1)])
        #expect(c.model.progress == 1)
        c.tabChanged()
        #expect(c.model.progress == 0)
    }

    @Test func drivesAttachedBar() {
        let c = makeCoordinator()
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house")])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        c.bar = bar
        drag(c, samples: [(100, 0), (180, 1)])
        bar.layoutIfNeeded()
        // settled at progress 1 -> glass capsule at 0.8 scale, bottom-anchored
        #expect(abs(bar.glassFrameForTesting.width - 240) < 0.001)
        #expect(abs(bar.glassFrameForTesting.maxY - 64) < 0.001)
    }

    @Test func disabledShrinkKeepsFullSizeOnAnyDrag() {
        let c = ShrinkCoordinator(isShrinkEnabled: false)
        drag(c, samples: [(100, 0), (300, 0.05)]) // hard fling down
        #expect(c.model.progress == 0)
    }
}
