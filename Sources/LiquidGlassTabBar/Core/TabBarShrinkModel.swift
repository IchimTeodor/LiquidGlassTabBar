import CoreGraphics

/// Pure scroll-to-shrink logic. Feed it scroll samples; read `progress`.
/// 0 = bar at full size, 1 = fully shrunk.
public struct TabBarShrinkModel {
    /// Downward scroll distance (pt) that maps to full shrink.
    public static let shrinkDistance: CGFloat = 80
    /// Velocity (pt/s) above which a fling decides the settle direction.
    public static let flingThreshold: CGFloat = 200

    public private(set) var progress: CGFloat = 0
    private var lastOffset: CGFloat?
    private var canShrink = false

    /// - Parameters:
    ///   - offset: content offset normalized so 0 == top of content
    ///     (UIKit: `contentOffset.y + adjustedContentInset.top`).
    ///   - viewportHeight: visible scroll area height.
    ///   - contentHeight: total content height.
    public mutating func update(offset: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) {
        let maxOffset = contentHeight - viewportHeight
        canShrink = maxOffset > 0
        guard canShrink else {              // content fits on screen: never shrink
            progress = 0
            lastOffset = nil
            return
        }
        let clamped = min(max(offset, 0), maxOffset)  // ignore bounce regions
        defer { lastOffset = clamped }
        guard clamped > 0 else {            // at top: always full size
            progress = 0
            return
        }
        guard let last = lastOffset else { return }   // first sample: baseline only
        progress = min(max(progress + (clamped - last) / Self.shrinkDistance, 0), 1)
    }

    /// Settle to an endpoint when the drag ends.
    /// - Parameter velocity: d(offset)/dt in pt/s; positive = scrolling down.
    @discardableResult
    public mutating func settle(velocity: CGFloat) -> CGFloat {
        guard canShrink else {
            progress = 0
            return progress
        }
        if velocity > Self.flingThreshold {
            progress = 1
        } else if velocity < -Self.flingThreshold {
            progress = 0
        } else {
            progress = progress >= 0.5 ? 1 : 0
        }
        return progress
    }

    /// Call when a new drag begins: the offset baseline is stale after a
    /// deceleration, so clear it without touching progress.
    public mutating func beginDrag() {
        lastOffset = nil
    }

    /// Reset when switching tabs (new scroll view starts at top).
    public mutating func reset() {
        progress = 0
        lastOffset = nil
        canShrink = false
    }
}
