import UIKit

/// Finds the scroll views that should drive the shrink, so the host never
/// has to wire them up one by one.
///
/// A probe gesture recognizer rides the bar's WINDOW. Recognizers attached
/// to an ancestor are offered every touch that lands in a descendant, so the
/// probe's `shouldReceive` callback sees each touch-down anywhere in the
/// app; walking up from the touched view finds the scroll view containing
/// it, which is attached the first time it is seen. The probe always answers
/// `false`, so it never tracks a touch, never begins, and cannot delay,
/// cancel, or compete with anything — it exists purely to be asked.
///
/// Why discovery-on-touch rather than scanning the hierarchy at install
/// time: scroll views appear lazily. An unselected tab, a sheet, or a lazily
/// built list has no scroll view yet when the bar is installed, so a scan
/// would see only what happened to exist at that instant, and UIKit offers
/// no general "a scroll view was added" hook to re-scan on. A scroll view
/// the user is touching, by contrast, definitely exists — and that touch is
/// exactly when the shrink is about to need it.
///
/// This is also what lets one mechanism serve both hosts: a SwiftUI
/// `ScrollView` is backed by a `UIScrollView`, so it is discovered the same
/// way a `UITableView` is, with no SwiftUI-side modifier.
/// Owns the coordinator and probe backing a bar's `minimizesOnScroll`, so
/// each bar variant needs only a stored instance and one call to refresh it.
/// Nothing is built until the switch is actually on and the bar has a
/// window, and turning it off tears the probe back down.
@MainActor
final class AutomaticShrink {
    private var coordinator: ShrinkCoordinator?
    private var autoAttach: ScrollShrinkAutoAttach?

    func refresh(isEnabled: Bool, bar: any ShrinkableBar, window: UIWindow?) {
        guard isEnabled else {
            autoAttach?.install(in: nil)
            autoAttach = nil
            coordinator = nil
            return
        }
        if coordinator == nil {
            let coordinator = ShrinkCoordinator()
            coordinator.drive(bar)
            self.coordinator = coordinator
            autoAttach = ScrollShrinkAutoAttach(coordinator: coordinator)
        }
        autoAttach?.install(in: window)
    }
}

@MainActor
final class ScrollShrinkAutoAttach: NSObject, UIGestureRecognizerDelegate {
    private let observer: ScrollShrinkObserver
    private let probe = UIPanGestureRecognizer()
    /// Weak so a scroll view that goes away is not kept alive, and so a
    /// later scroll view reusing the address is still attached correctly.
    private let seen = NSHashTable<UIScrollView>.weakObjects()

    init(coordinator: ShrinkCoordinator) {
        observer = ScrollShrinkObserver(coordinator: coordinator)
        super.init()
        probe.delegate = self
        // Belt and braces: the probe should be inert by virtue of never
        // receiving a touch, but if any of these defaulted the other way a
        // stray recognizer on the window would interfere with content.
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
    }

    /// Moves the probe to `window`. Safe to call repeatedly; a bar that
    /// changes windows (or is removed) re-hosts or drops the probe.
    func install(in window: UIWindow?) {
        guard probe.view !== window else { return }
        probe.view?.removeGestureRecognizer(probe)
        window?.addGestureRecognizer(probe)
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Never actually takes the touch — returning false both keeps the probe
    /// completely out of the way and gives us the touched view.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        noteTouch(on: touch.view)
        return false
    }

    /// The delegate callback's body, split out because a `UITouch` cannot be
    /// constructed in a test — this is the part worth testing.
    /// - Returns: the scroll view discovered, if any.
    @discardableResult
    func noteTouch(on view: UIView?) -> UIScrollView? {
        guard let scrollView = Self.enclosingScrollView(of: view) else { return nil }
        // Attaching twice would install a second KVO observer on the same
        // scroll view and count every offset change twice.
        guard !seen.contains(scrollView) else { return scrollView }
        seen.add(scrollView)
        observer.attach(to: scrollView)
        return scrollView
    }

    /// The innermost scroll view containing `view`. Innermost rather than
    /// every ancestor: with nested scroll views it is the inner one the
    /// touch actually scrolls, and feeding an outer horizontal pager's
    /// geometry into the vertical shrink model would be noise.
    private static func enclosingScrollView(of view: UIView?) -> UIScrollView? {
        var candidate = view
        while let current = candidate {
            if let scrollView = current as? UIScrollView { return scrollView }
            candidate = current.superview
        }
        return nil
    }
}
