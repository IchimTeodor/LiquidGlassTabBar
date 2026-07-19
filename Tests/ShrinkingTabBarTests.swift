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
    @Test func lensDragSelectsNearestItemOnRelease() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        var selected: Int?
        bar.onSelect = { selected = $0 }
        bar.simulateLensDrag(toX: 250, ended: false)
        bar.simulateLensDrag(toX: 250, ended: true)
        #expect(selected == 1)
        #expect(bar.selectedIndex == 1)
    }

    @MainActor
    @Test func lensDragOnSameItemStillFiresOnSelect() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        var selected: Int?
        bar.onSelect = { selected = $0 }
        bar.simulateLensDrag(toX: 40, ended: false) // over item 0, already selected
        bar.simulateLensDrag(toX: 40, ended: true)
        #expect(selected == 0)
        #expect(bar.selectedIndex == 0)
    }

    @MainActor
    @Test func lensSizesToSlotProportionallyWhileDragging() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.simulateLensDrag(toX: 40, ended: false)
        // bounds, not frame: the elastic stretch transform is active while
        // dragging, and frame would report the stretched bounding box.
        // Slot frame 138 wide, expanded by the metal bubble treatment
        // (dx: -12% of width) -> 138 * 1.24 = 171.1.
        #expect(abs(bar.lensBoundsForTesting.width - 171.1) < 1.0)
        bar.simulateLensDrag(toX: 40, ended: true)
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        bar.simulateLensDrag(toX: 40, ended: false)
        // Shrunk slot frame 108 wide -> 108 * 1.24 = 133.9.
        #expect(abs(bar.lensBoundsForTesting.width - 133.9) < 1.0)
    }

    @MainActor
    @Test func lensHiddenAtRestVisibleOnlyWhileDragging() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        #expect(bar.lensAlphaForTesting == 0)
        bar.simulateLensDrag(toX: 40, ended: false)
        #expect(bar.lensAlphaForTesting == 1)
        bar.simulateLensDrag(toX: 40, ended: true)
        #expect(bar.lensAlphaForTesting == 0)
    }

    @MainActor
    @Test func tintMaskParksOnSelectedSlotAtRest() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        // stack is 284 wide -> slot 0 = (0, 0, 142, 64) in stack coords
        #expect(abs(bar.tintMaskFrameForTesting.minX - 0) < 1.0)
        #expect(abs(bar.tintMaskFrameForTesting.width - 142) < 1.0)
        bar.simulateTap(at: 1)
        bar.layoutIfNeeded()
        #expect(abs(bar.tintMaskFrameForTesting.minX - 142) < 1.0)
    }

    @MainActor
    @Test func tintMaskFollowsLensAndCommitsOnRelease() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.simulateLensDrag(toX: 250, ended: false)
        #expect(bar.selectedIndex == 0) // not committed until release
        #expect(bar.tintMaskFrameForTesting.midX > 142) // mask riding over item 1 region
        bar.simulateLensDrag(toX: 250, ended: true)
        #expect(bar.selectedIndex == 1)
        #expect(abs(bar.tintMaskFrameForTesting.minX - 142) < 1.0)
    }

    @MainActor
    @Test func externalSelectionChangeMidDragDoesNotYankTheMask() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.simulateLensDrag(toX: 250, ended: false) // lens riding over item 1
        let ridingMidX = bar.tintMaskFrameForTesting.midX
        bar.selectedIndex = 1 // external write mid-drag (e.g. SwiftUI updateUIView re-render)
        #expect(abs(bar.tintMaskFrameForTesting.midX - ridingMidX) < 0.001) // mask untouched
        bar.simulateLensDrag(toX: 250, ended: true)
        #expect(bar.selectedIndex == 1)
        #expect(abs(bar.tintMaskFrameForTesting.minX - 142) < 1.0) // parked after release
    }

    @MainActor
    @Test func tintMaskParksProportionallyWhenShrunk() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        // capsule 240 wide -> stack 224 -> slot 112
        #expect(abs(bar.tintMaskFrameForTesting.width - 112) < 1.0)
        #expect(abs(bar.tintMaskFrameForTesting.minX - 0) < 1.0)
    }

    @MainActor
    @Test func titlesStaySingleLineWhenShrunk() {
        // Regression: at full shrink the slots narrow via real layout while
        // the font stays full-size in layout (the 0.8 is a transform applied
        // after), so "Favorites" wrapped onto two hyphenated lines even
        // though the transformed result had room. App-realistic geometry:
        // 393pt screen minus 16pt side padding.
        let bar = ShrinkingTabBar(items: MockData.tabs)
        bar.frame = CGRect(x: 0, y: 0, width: 361, height: 64)
        bar.layoutIfNeeded()
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        for label in bar.itemTitleLabelsForTesting {
            let lineHeight = label.font.lineHeight
            // Single line: anything near 2x line height means it wrapped.
            #expect(label.bounds.height < lineHeight * 1.5,
                    "\(label.text ?? "?") wrapped: height \(label.bounds.height) vs line \(lineHeight)")
            // And the full text fits — no truncation smuggled in either.
            #expect(label.intrinsicContentSize.width <= label.bounds.width + 0.5,
                    "\(label.text ?? "?") truncated: needs \(label.intrinsicContentSize.width), has \(label.bounds.width)")
        }
    }

    @MainActor
    @Test func tintMaskRidesLensWhileShrunk() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        bar.simulateLensDrag(toX: 40, ended: false)
        // dragging at full shrink: mask sized to the (expanded) lens
        // (slot 112 inset 4 -> 108, expanded -> 133.9). frame reports the
        // TRANSFORMED box and the elastic lag stretch is active mid-drag
        // (up to a few percent), so the tolerance covers the stretch too.
        #expect(abs(bar.tintMaskFrameForTesting.width - 133.9) < 4.0)
        bar.simulateLensDrag(toX: 40, ended: true)
        // released: parked on the shrunk slot (112)
        #expect(abs(bar.tintMaskFrameForTesting.width - 112) < 2.0)
    }
}

/// The v1 pill bar, kept verbatim (see PillTabBar) — these are the original
/// pill tests from commit 7ef4e84, retargeted at the renamed class.
struct PillTabBarTests {
    @Test func staticGeometryMatchesTheMetalBar() {
        // Both variants share the same shrink math by construction.
        #expect(PillTabBar.scale(for: 0.5) == ShrinkingTabBar.scale(for: 0.5))
        #expect(PillTabBar.glassFrame(progress: 1, in: CGSize(width: 300, height: 64))
                == ShrinkingTabBar.glassFrame(progress: 1, in: CGSize(width: 300, height: 64)))
        #expect(PillTabBar.nearestIndex(forX: 150, stripWidth: 400, count: 4) == 1)
    }

    @MainActor
    @Test func setProgressResizesGlassCapsule() {
        let bar = PillTabBar(items: [TabItem(title: "A", systemImage: "house")])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        #expect(abs(bar.glassFrameForTesting.width - 240) < 0.001)
        #expect(abs(bar.glassFrameForTesting.height - 51.2) < 0.5)
        #expect(abs(bar.glassFrameForTesting.maxY - 64) < 0.001)
    }

    @MainActor
    @Test func tappingItemUpdatesSelectionAndFiresCallback() {
        let bar = PillTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
        var selected: Int?
        bar.onSelect = { selected = $0 }
        bar.simulateTap(at: 1)
        #expect(selected == 1)
        #expect(bar.selectedIndex == 1)
    }

    @MainActor
    @Test func pillDragSelectsNearestItemOnRelease() {
        let bar = PillTabBar(items: [
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
        let bar = PillTabBar(items: [
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
        let bar = PillTabBar(items: [
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
        let bar = PillTabBar(items: [
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
