import SwiftUI

/// SwiftUI wrapper around the shared UIKit bar. Hosts a plain container so
/// the BAR VARIANT can be swapped in place (the v1 pill bar and the metal
/// bar are different classes) without recreating the representable.
public struct ShrinkingTabBarView: UIViewRepresentable {
    let items: [TabItem]
    @Binding var selectedIndex: Int
    let coordinator: ShrinkCoordinator?
    var variant: BarVariant = .metal

    /// The memberwise initializer is internal, so package consumers get an
    /// explicit one.
    ///
    /// - Parameter coordinator: leave this `nil` (the default) and the bar
    ///   shrinks on scroll by itself — no coordinator to build, nothing to
    ///   attach to each `ScrollView`. Pass one only to drive the shrink
    ///   yourself, which turns the automatic behaviour off.
    public init(items: [TabItem],
                selectedIndex: Binding<Int>,
                variant: BarVariant = .metal,
                coordinator: ShrinkCoordinator? = nil) {
        self.items = items
        self._selectedIndex = selectedIndex
        self.coordinator = coordinator
        self.variant = variant
    }

    public final class Container: UIView {
        var variant: BarVariant?
        var bar: (UIView & ShrinkableBar)?
    }

    public func makeUIView(context: Context) -> Container {
        let container = Container()
        rebuildBar(in: container)
        return container
    }

    public func updateUIView(_ container: Container, context: Context) {
        if container.variant != variant {
            rebuildBar(in: container)
        }
        container.bar?.selectedIndex = selectedIndex
    }

    private func rebuildBar(in container: Container) {
        container.bar?.removeFromSuperview()
        let bar: UIView & ShrinkableBar = switch variant {
        case .pill: PillTabBar(items: items)
        case .metal: ShrinkingTabBar(items: items)
        }
        bar.onSelect = { selectedIndex = $0 }
        bar.frame = container.bounds
        bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(bar)
        container.bar = bar
        container.variant = variant
        // Assigning the bar switches its automatic mode off, so this must
        // happen only when a coordinator was actually supplied.
        coordinator?.bar = bar
    }
}
