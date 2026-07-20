import UIKit

/// The two tab-bar implementations the demo keeps, after pruning the
/// intermediate lens experiments:
/// - `.pill`: the original v1 bar (verbatim from commit 7ef4e84) whose drag
///   indicator is an interactive `UIGlassEffect` pill.
/// - `.metal`: the final bar whose drag indicator is the Metal-shader
///   Liquid Glass lens (SDF refraction, droplet inertia).
/// The Native reference host is untouched by this choice — it always shows
/// the real system tab bar for comparison.
public enum BarVariant {
    case pill
    case metal
}

/// The common surface both bar variants expose to the hosts and the shrink
/// coordinator (tab wiring plus scroll-driven shrink progress). Main-actor
/// isolated, matching the UIView conformers it is constrained to: the
/// coordinator that drives it is main-actor too, so the isolation is stated
/// rather than assumed (this is what the package's Swift 6 mode requires,
/// and it was already true in practice).
public protocol ShrinkableBar: UIView {
    var onSelect: ((Int) -> Void)? { get set }
    var selectedIndex: Int { get set }
    /// Shrink in response to any scroll view the user drags, with no
    /// per-scroll-view wiring — see the property on the concrete bars.
    var minimizesOnScroll: Bool { get set }
    func setProgress(_ newProgress: CGFloat, animated: Bool)
}
