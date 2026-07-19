import UIKit

/// Bridges scroll events from either UIKit or SwiftUI into the shared
/// `TabBarShrinkModel` and drives a `ShrinkingTabBar`. One instance per host.
/// Velocity is computed here from consecutive samples so both frameworks get
/// identical fling semantics.
final class ShrinkCoordinator {
    /// Shrink-on-scroll accompanies the Liquid Glass appearance, which is
    /// iOS 26+. On iOS 18–25 the bar keeps its material background and
    /// stays at full size.
    static var systemSupportsShrink: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private let isShrinkEnabled: Bool
    private(set) var model = TabBarShrinkModel()
    weak var bar: (any ShrinkableBar)?

    private var isDragging = false
    private var lastSample: (offset: CGFloat, time: TimeInterval)?
    private var velocity: CGFloat = 0

    init(isShrinkEnabled: Bool = ShrinkCoordinator.systemSupportsShrink) {
        self.isShrinkEnabled = isShrinkEnabled
    }

    func dragBegan() {
        guard isShrinkEnabled else { return }
        isDragging = true
        model.beginDrag()
        lastSample = nil
        velocity = 0
    }

    func scrolled(offset: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat,
                  time: TimeInterval = CACurrentMediaTime()) {
        guard isShrinkEnabled, isDragging else { return }
        if let last = lastSample, time > last.time {
            velocity = (offset - last.offset) / (time - last.time)
        }
        lastSample = (offset, time)
        model.update(offset: offset, viewportHeight: viewportHeight, contentHeight: contentHeight)
        bar?.setProgress(model.progress, animated: false)
    }

    func dragEnded() {
        guard isShrinkEnabled, isDragging else { return }
        isDragging = false
        model.settle(velocity: velocity)
        bar?.setProgress(model.progress, animated: true)
    }

    func tabChanged() {
        isDragging = false
        model.reset()
        bar?.setProgress(0, animated: true)
    }
}
