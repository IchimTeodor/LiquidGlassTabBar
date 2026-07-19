import Testing
import UIKit
@testable import LiquidGlassTabBar

struct ShrinkingTabBarTests {
    @Test func scaleMapsProgressLinearly() {
        #expect(ShrinkingTabBar.scale(for: 0) == 1.0)
        #expect(ShrinkingTabBar.scale(for: 1) == 0.8)
        #expect(abs(ShrinkingTabBar.scale(for: 0.5) - 0.9) < 0.0001)
    }

    @Test func scaleClampsOutOfRangeProgress() {
        #expect(ShrinkingTabBar.scale(for: -1) == 1.0)
        #expect(ShrinkingTabBar.scale(for: 2) == 0.8)
    }

    @Test func glassFrameFullSizeAtZeroProgress() {
        let frame = ShrinkingTabBar.glassFrame(progress: 0, in: CGSize(width: 300, height: 64))
        #expect(frame == CGRect(x: 0, y: 0, width: 300, height: 64))
    }

    @Test func glassFrameShrinksAnchoredBottomCenter() {
        let frame = ShrinkingTabBar.glassFrame(progress: 1, in: CGSize(width: 300, height: 64))
        #expect(abs(frame.width - 240) < 0.0001)
        #expect(abs(frame.height - 51.2) < 0.0001)
        #expect(abs(frame.minX - 30) < 0.0001)   // centered horizontally
        #expect(abs(frame.maxY - 64) < 0.0001)   // bottom edge fixed
    }

    @MainActor
    @Test func setProgressResizesGlassCapsule() {
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house")])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        #expect(abs(bar.glassFrameForTesting.width - 240) < 0.001)
        // Auto Layout snaps resolved frames to the device's pixel grid; 51.2pt
        // isn't pixel-aligned at 3x scale (51.2 * 3 = 153.6), so the live view
        // settles at the nearest pixel (~51.33pt). The static glassFrame(...)
        // math above is exact — only this live-view measurement needs the
        // wider tolerance to account for real device pixel snapping.
        #expect(abs(bar.glassFrameForTesting.height - 51.2) < 0.5)
        #expect(abs(bar.glassFrameForTesting.maxY - 64) < 0.001)
    }

    @MainActor
    @Test func tappingItemUpdatesSelectionAndFiresCallback() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        var selected: Int?
        bar.onSelect = { selected = $0 }
        bar.simulateTap(at: 1)
        #expect(selected == 1)
        #expect(bar.selectedIndex == 1)
    }

    @Test func nearestIndexMapsPositionsToSlots() {
        #expect(ShrinkingTabBar.nearestIndex(forX: 10, stripWidth: 400, count: 4) == 0)
        #expect(ShrinkingTabBar.nearestIndex(forX: 150, stripWidth: 400, count: 4) == 1)
        #expect(ShrinkingTabBar.nearestIndex(forX: 399, stripWidth: 400, count: 4) == 3)
    }

    @Test func nearestIndexClampsOutOfRange() {
        #expect(ShrinkingTabBar.nearestIndex(forX: -50, stripWidth: 400, count: 4) == 0)
        #expect(ShrinkingTabBar.nearestIndex(forX: 500, stripWidth: 400, count: 4) == 3)
        #expect(ShrinkingTabBar.nearestIndex(forX: 100, stripWidth: 0, count: 4) == 0)
    }

    @MainActor
    @Test func pillDragSelectsNearestItemOnRelease() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        var selected: Int?
        bar.onSelect = { selected = $0 }
        bar.simulatePillDrag(toX: 250, ended: false)
        bar.simulatePillDrag(toX: 250, ended: true)
        #expect(selected == 1)
        #expect(bar.selectedIndex == 1)
    }

    @MainActor
    @Test func pillDragOnSameItemStillFiresOnSelect() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        var selected: Int?
        bar.onSelect = { selected = $0 }
        bar.simulatePillDrag(toX: 40, ended: false) // over item 0, already selected
        bar.simulatePillDrag(toX: 40, ended: true)
        #expect(selected == 0)
        #expect(bar.selectedIndex == 0)
    }

    @MainActor
    @Test func pillSizesToSlotProportionallyWhileDragging() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.simulatePillDrag(toX: 40, ended: false)
        #expect(abs(bar.pillFrameForTesting.width - 138) < 1.0)
        bar.simulatePillDrag(toX: 40, ended: true)
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        bar.simulatePillDrag(toX: 40, ended: false)
        #expect(abs(bar.pillFrameForTesting.width - 108) < 1.0)
    }

    @MainActor
    @Test func pillHiddenAtRestVisibleOnlyWhileDragging() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        #expect(bar.pillAlphaForTesting == 0)
        bar.simulatePillDrag(toX: 40, ended: false)
        #expect(bar.pillAlphaForTesting == 1)
        bar.simulatePillDrag(toX: 40, ended: true)
        #expect(bar.pillAlphaForTesting == 0)
    }
}
