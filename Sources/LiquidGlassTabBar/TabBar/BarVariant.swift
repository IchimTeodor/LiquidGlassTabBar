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
/// coordinator (tab wiring plus scroll-driven shrink progress). Deliberately
/// not @MainActor-annotated: the conformers are UIView subclasses (already
/// main-actor in practice) and the pre-variant code called the concrete
/// class from the nonisolated ShrinkCoordinator under the project's Swift 5
/// concurrency mode — an isolated protocol would tighten that retroactively.
public protocol ShrinkableBar: UIView {
    var onSelect: ((Int) -> Void)? { get set }
    var selectedIndex: Int { get set }
    func setProgress(_ newProgress: CGFloat, animated: Bool)
}
