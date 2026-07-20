import SwiftUI

/// SwiftUI wrapper around the shared UIKit bar. Hosts a plain container so
/// the BAR VARIANT can be swapped in place (the v1 pill bar and the metal
/// bar are different classes) without recreating the representable.
public struct ShrinkingTabBarView: UIViewRepresentable {
    let items: [TabItem]
    @Binding var selectedIndex: Int
    let coordinator: ShrinkCoordinator
    var variant: BarVariant = .metal

    /// The memberwise initializer is internal, so package consumers get an
    /// explicit one.
    public init(items: [TabItem],
                selectedIndex: Binding<Int>,
                coordinator: ShrinkCoordinator,
                variant: BarVariant = .metal) {
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
        coordinator.bar = bar
    }
}
