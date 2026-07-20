import SwiftUI

private struct ShrinkCoordinatorKey: EnvironmentKey {
    static let defaultValue: ShrinkCoordinator? = nil
}

public extension EnvironmentValues {
    /// The host's shared shrink coordinator, injected once at the container.
    var shrinkCoordinator: ShrinkCoordinator? {
        get { self[ShrinkCoordinatorKey.self] }
        set { self[ShrinkCoordinatorKey.self] = newValue }
    }
}

/// Feeds a ScrollView's geometry and drag phases into the environment's
/// ShrinkCoordinator. No per-tab guards are needed: only the actively
/// dragged scroll view emits `.interacting` phase changes, and the
/// coordinator ignores samples outside a drag.
private struct ShrinksTabBarOnScroll: ViewModifier {
    @Environment(\.shrinkCoordinator) private var coordinator

    private struct ScrollSample: Equatable {
        var offset: CGFloat
        var viewport: CGFloat
        var content: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollSample.self) { geometry in
                // NOTE: UIKit's ScrollShrinkObserver reduces the viewport by
                // adjusted content insets; containerSize here does not. See
                // the matching note in ScrollShrinkObserver.
                ScrollSample(offset: geometry.contentOffset.y + geometry.contentInsets.top,
                             viewport: geometry.containerSize.height,
                             content: geometry.contentSize.height)
            } action: { _, sample in
                coordinator?.scrolled(offset: sample.offset,
                                      viewportHeight: sample.viewport,
                                      contentHeight: sample.content)
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .interacting {
                    coordinator?.dragBegan()
                } else if oldPhase == .interacting {
                    coordinator?.dragEnded()
                }
            }
    }
}

public extension View {
    /// Attach to any ScrollView to drive the shared shrinking tab bar.
    func shrinksTabBar() -> some View {
        modifier(ShrinksTabBarOnScroll())
    }
}
