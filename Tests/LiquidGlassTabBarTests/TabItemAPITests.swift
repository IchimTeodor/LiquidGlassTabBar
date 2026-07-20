import Testing
import UIKit
@testable import LiquidGlassTabBar

/// A 1x1 image in a known color, so "which artwork ended up where" is
/// checkable without bundling assets.
@MainActor
private func swatch(_ color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
        color.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

@MainActor
struct TabItemIconTests {
    @Test func customArtworkUsesTheSelectedImageForTheSelectedRow() {
        let normal = swatch(.green)
        let selected = swatch(.purple)
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", image: normal, selectedImage: selected),
        ])

        let images = bar.itemImagesForTesting
        // The base row is the unselected look; the replica the lens reveals
        // carries the selected artwork. That split is how a dragged bubble
        // can show one item selected and the next not.
        //
        // Compared by backing CGImage, not by size or instance: both swatches
        // are 1x1, and withRenderingMode always returns a fresh UIImage, so
        // either of those would still pass if BOTH rows used the same
        // artwork — exactly the bug worth catching here.
        #expect(images.unselected.first??.cgImage === normal.cgImage)
        #expect(images.selected.first??.cgImage === selected.cgImage)
    }

    @Test func templateIsTheDefaultSoArtworkPicksUpTheTints() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A", image: swatch(.green), selectedImage: swatch(.purple)),
        ])
        let images = bar.itemImagesForTesting
        #expect(images.unselected.first??.renderingMode == .alwaysTemplate)
        #expect(images.selected.first??.renderingMode == .alwaysTemplate)
    }

    /// `.original` is the escape hatch for multicolor artwork that tinting
    /// would flatten to a single color.
    @Test func originalRenderingKeepsArtworkUntinted() {
        let bar = ShrinkingTabBar(items: [
            TabItem(title: "A",
                    image: swatch(.green),
                    selectedImage: swatch(.purple),
                    renderingMode: .original),
        ])
        let images = bar.itemImagesForTesting
        #expect(images.unselected.first??.renderingMode == .alwaysOriginal)
        #expect(images.selected.first??.renderingMode == .alwaysOriginal)
    }

    /// SF Symbols must stay template regardless — tinting them per row is
    /// the entire mechanism by which they show selection.
    @Test func symbolsAreAlwaysTemplate() {
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house.fill")])
        let images = bar.itemImagesForTesting
        #expect(images.unselected.first??.renderingMode == .alwaysTemplate)
        #expect(images.selected.first??.renderingMode == .alwaysTemplate)
    }
}

@MainActor
struct TabBarTintTests {
    private func makeBar() -> ShrinkingTabBar {
        ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house"),
            TabItem(title: "B", systemImage: "heart"),
        ])
    }

    @Test func defaultsMatchThePreviousHardcodedColors() {
        let tints = makeBar().itemTintsForTesting
        #expect(tints.unselected.allSatisfy { $0 == .secondaryLabel })
        #expect(tints.selected.allSatisfy { $0 == .systemBlue })
    }

    @Test func settingTintsRetintsEveryItemInPlace() {
        let bar = makeBar()
        bar.unselectedTintColor = .darkGray
        bar.selectedTintColor = .systemPink

        let tints = bar.itemTintsForTesting
        #expect(tints.unselected.allSatisfy { $0 == .darkGray })
        #expect(tints.selected.allSatisfy { $0 == .systemPink })
    }
}

@MainActor
struct TabBarBadgeTests {
    private func makeBar(badge: TabBadge = .none) -> ShrinkingTabBar {
        ShrinkingTabBar(items: [
            TabItem(title: "A", systemImage: "house", badge: badge),
            TabItem(title: "B", systemImage: "heart"),
        ])
    }

    @Test func itemsStartWithNoBadgeUnlessGivenOne() {
        let bar = makeBar()
        #expect(bar.badge(at: 0) == .none)
        #expect(bar.badgeVisibilityForTesting.base == [false, false])
    }

    @Test func badgesRenderInBothRowsSoTheLensCannotHideThem() {
        let bar = makeBar(badge: .count(3))
        // The lens reveals the replica row; a badge present in only one row
        // would blink out as the bubble passed over it.
        #expect(bar.badgeVisibilityForTesting.base == [true, false])
        #expect(bar.badgeVisibilityForTesting.tinted == [true, false])
    }

    @Test func badgesChangeAtRuntime() {
        let bar = makeBar()
        bar.setBadge(.dot, at: 1)
        #expect(bar.badge(at: 1) == .dot)
        #expect(bar.badgeVisibilityForTesting.base == [false, true])

        bar.setBadge(.none, at: 1)
        #expect(bar.badge(at: 1) == .none)
        #expect(bar.badgeVisibilityForTesting.base == [false, false])
    }

    /// Badge updates usually arrive from async work, so a stale index must
    /// not crash.
    @Test func outOfRangeBadgeUpdatesAreIgnored() {
        let bar = makeBar()
        bar.setBadge(.dot, at: 99)
        bar.setBadge(.dot, at: -1)
        #expect(bar.badge(at: 99) == .none)
        #expect(bar.badgeVisibilityForTesting.base == [false, false])
    }

    /// A zero count collapses to `.none`, so callers can bind an unread
    /// count straight through without special-casing empty.
    @Test func zeroCountIsNoBadgeAtAll() {
        #expect(TabBadge.count(0) == .none)
        #expect(TabBadge.count(-1) == .none)
        #expect(TabBadge.text("").isVisible == false)
    }

    /// `count` is a factory over the three cases rather than a case of its
    /// own, so it resolves to plain text once clamped.
    @Test func countsClampToTheirMaximum() {
        #expect(TabBadge.count(5) == .text("5"))
        #expect(TabBadge.count(99) == .text("99"))
        #expect(TabBadge.count(100) == .text("99+"))
        #expect(TabBadge.count(1000, maximum: 999) == .text("999+"))
    }

    /// A dot is a badge with no text — visible, but nothing to render inside.
    @Test func dotIsVisibleWithoutText() {
        #expect(TabBadge.dot.isVisible)
        #expect(TabBadge.dot.displayText == nil)
    }
}

@MainActor
struct ShrinkProgressCallbackTests {
    private func makeBar() -> ShrinkingTabBar {
        let bar = ShrinkingTabBar(items: [TabItem(title: "A", systemImage: "house")])
        bar.frame = CGRect(x: 0, y: 0, width: 300, height: 64)
        bar.layoutIfNeeded()
        return bar
    }

    @Test func reportsProgressAsItChanges() {
        let bar = makeBar()
        var reported: [CGFloat] = []
        bar.onShrinkProgress = { reported.append($0) }

        bar.setProgress(0.5, animated: false)
        bar.setProgress(1, animated: false)
        bar.setProgress(0, animated: false)
        #expect(reported == [0.5, 1, 0])
    }

    /// The scroll stream re-sends the same value constantly; republishing it
    /// would make the callback useless for driving anything.
    @Test func repeatedValuesDoNotFire() {
        let bar = makeBar()
        var count = 0
        bar.onShrinkProgress = { _ in count += 1 }

        bar.setProgress(1, animated: false)
        bar.setProgress(1, animated: false)
        bar.setProgress(1, animated: false)
        #expect(count == 1)
    }

    @Test func reportsClampedValuesNotRawInput() {
        let bar = makeBar()
        var reported: [CGFloat] = []
        bar.onShrinkProgress = { reported.append($0) }

        bar.setProgress(5, animated: false)
        bar.setProgress(-3, animated: false)
        #expect(reported == [1, 0])
    }

    @Test func theBarHasActuallyShrunkWhenTheCallbackFires() {
        let bar = makeBar()
        var widthAtCallback: CGFloat?
        bar.onShrinkProgress = { _ in widthAtCallback = bar.glassFrameForTesting.width }

        bar.setProgress(1, animated: false)
        bar.layoutIfNeeded()
        // Fires with the target of the change, so a caller reading the bar
        // sees the new progress rather than the previous one.
        #expect(widthAtCallback != nil)
        #expect(abs(bar.glassFrameForTesting.width - 240) < 0.5)
    }
}
