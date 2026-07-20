import SwiftUI

/// SwiftUI wrapper around the shared UIKit bar. Hosts a plain container so
/// the BAR VARIANT can be swapped in place (the v1 pill bar and the metal
/// bar are different classes) without recreating the representable.
public struct ShrinkingTabBarView: UIViewRepresentable {
    let items: [TabItem]
    @Binding var selectedIndex: Int
    let coordinator: ShrinkCoordinator?
    var variant: BarVariant = .metal
    private var selectedTintColor: UIColor = .systemBlue
    private var unselectedTintColor: UIColor = .secondaryLabel
    private var onShrinkProgress: ((CGFloat) -> Void)?

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
        apply(to: container.bar)
    }

    /// Pushes the SwiftUI-owned values into the bar on every update. Badges
    /// come from `items`, so changing an item's badge in SwiftUI state is
    /// what updates it — no imperative call needed.
    private func apply(to bar: (UIView & ShrinkableBar)?) {
        guard let bar = bar as? ShrinkingTabBar else { return }
        bar.selectedTintColor = selectedTintColor
        bar.unselectedTintColor = unselectedTintColor
        bar.onShrinkProgress = onShrinkProgress
        for (index, item) in items.enumerated() where bar.badge(at: index) != item.badge {
            bar.setBadge(item.badge, at: index)
        }
    }

    /// Colors for the selected and unselected items.
    public func tabBarTints(selected: UIColor, unselected: UIColor) -> Self {
        var copy = self
        copy.selectedTintColor = selected
        copy.unselectedTintColor = unselected
        return copy
    }

    /// Reports the shrink as it changes: 0 is full size, 1 fully shrunk.
    public func onTabBarShrink(_ handler: @escaping (CGFloat) -> Void) -> Self {
        var copy = self
        copy.onShrinkProgress = handler
        return copy
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
        apply(to: bar)
        // Assigning the bar switches its automatic mode off, so this must
        // happen only when a coordinator was actually supplied.
        coordinator?.bar = bar
    }
}
