import Testing
import CoreGraphics
@testable import LiquidGlassTabBar

struct TabBarShrinkModelTests {
    /// Tall content (2000pt) in an 800pt viewport unless stated otherwise.
    private func makeModel() -> TabBarShrinkModel { TabBarShrinkModel() }

    private func scroll(_ model: inout TabBarShrinkModel, to offset: CGFloat,
                        viewport: CGFloat = 800, content: CGFloat = 2000) {
        model.update(offset: offset, viewportHeight: viewport, contentHeight: content)
    }

    @Test func startsAtFullSize() {
        let model = makeModel()
        #expect(model.progress == 0)
    }

    @Test func firstSampleOnlySetsBaseline() {
        var model = makeModel()
        scroll(&model, to: 100)
        #expect(model.progress == 0)
    }

    @Test func fullShrinkAfterShrinkDistance() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 100 + TabBarShrinkModel.shrinkDistance)
        #expect(model.progress == 1)
    }

    @Test func partialShrinkIsProportional() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 140) // 40pt of 80pt distance
        #expect(model.progress == 0.5)
    }

    @Test func scrollingUpReversesProgressively() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 180) // progress 1
        scroll(&model, to: 140) // back up 40pt
        #expect(model.progress == 0.5)
    }

    @Test func topOfContentForcesFullSize() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 180)
        #expect(model.progress == 1)
        scroll(&model, to: 0)
        #expect(model.progress == 0)
    }

    @Test func bounceBelowTopIsIgnored() {
        var model = makeModel()
        scroll(&model, to: -50) // rubber-band above top
        scroll(&model, to: -10)
        #expect(model.progress == 0)
    }

    @Test func bouncePastBottomIsClamped() {
        var model = makeModel()
        // content 1000, viewport 800 -> maxOffset 200
        scroll(&model, to: 100, content: 1000)
        scroll(&model, to: 180, content: 1000) // progress 1
        scroll(&model, to: 260, content: 1000) // past max, clamped to 200
        scroll(&model, to: 160, content: 1000) // delta from 200, not 260
        #expect(model.progress == 0.5)
    }

    @Test func shortContentNeverShrinks() {
        var model = makeModel()
        scroll(&model, to: 100, content: 500) // content fits viewport
        scroll(&model, to: 300, content: 500)
        #expect(model.progress == 0)
        model.settle(velocity: 1000) // even a fling settles at 0
        #expect(model.progress == 0)
    }

    @Test func settleSnapsToNearestWithoutFling() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 130) // progress 0.375
        #expect(model.settle(velocity: 0) == 0)

        scroll(&model, to: 100)
        scroll(&model, to: 150) // progress 0.625
        #expect(model.settle(velocity: 0) == 1)
    }

    @Test func flingOverridesNearest() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 120) // progress 0.25
        #expect(model.settle(velocity: 300) == 1)  // fling down -> shrink

        scroll(&model, to: 180) // progress high again
        #expect(model.settle(velocity: -300) == 0) // fling up -> restore
    }

    @Test func beginDragClearsBaselineButKeepsProgress() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 140) // progress 0.5
        model.beginDrag()
        scroll(&model, to: 600) // new baseline only, no jump
        #expect(model.progress == 0.5)
        scroll(&model, to: 620)
        #expect(model.progress == 0.75)
    }

    @Test func resetReturnsToFullSize() {
        var model = makeModel()
        scroll(&model, to: 100)
        scroll(&model, to: 180)
        model.reset()
        #expect(model.progress == 0)
    }
}
