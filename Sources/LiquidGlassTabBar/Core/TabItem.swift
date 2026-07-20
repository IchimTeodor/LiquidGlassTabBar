import UIKit

/// Sendable is spelled out because public types don't get the implicit
/// conformance non-public ones do — without it, consumers can't hold items
/// in a `static let`. `UIImage` is itself Sendable, so carrying artwork here
/// costs nothing.
public struct TabItem: Equatable, Sendable {

    /// Where an item's icon comes from.
    public enum Icon: Equatable, Sendable {
        /// An SF Symbol, tinted by the bar for both states.
        case system(String)
        /// Supplied artwork, with a distinct image for the selected state —
        /// which is how custom icons express selection, rather than relying
        /// on a tint.
        case images(normal: UIImage, selected: UIImage)
    }

    /// How supplied artwork is drawn. Ignored by `.system` icons, which are
    /// always template-rendered so the bar can tint them.
    public enum RenderingMode: Equatable, Sendable {
        /// Recolored with the bar's tints, like an SF Symbol. The default:
        /// it keeps custom icons consistent with the selection colors.
        case template
        /// Drawn in its own colors, untinted — for multicolor artwork that
        /// would be flattened to a single color by tinting.
        case original
    }

    public let title: String
    public let icon: Icon
    public let renderingMode: RenderingMode
    /// The badge this item starts with. To change it later, use the bar's
    /// `setBadge(_:at:)` — badges are state, not configuration.
    public let badge: TabBadge

    /// An SF Symbol item. The bar tints the symbol for each state.
    public init(title: String, systemImage: String, badge: TabBadge = .none) {
        self.title = title
        self.icon = .system(systemImage)
        self.renderingMode = .template
        self.badge = badge
    }

    /// An item with supplied artwork.
    ///
    /// - Parameters:
    ///   - image: shown when the item is not selected.
    ///   - selectedImage: shown when it is.
    ///   - renderingMode: `.template` (default) recolors both images with
    ///     the bar's tints; `.original` draws them in their own colors.
    public init(title: String,
                image: UIImage,
                selectedImage: UIImage,
                renderingMode: RenderingMode = .template,
                badge: TabBadge = .none) {
        self.title = title
        self.icon = .images(normal: image, selected: selectedImage)
        self.renderingMode = renderingMode
        self.badge = badge
    }
}

public extension TabItem {
    /// The artwork for one state, with the rendering mode already applied —
    /// the same image the bar draws.
    ///
    /// Public because callers building their own views from these items
    /// (a `UITabBarItem`, say) would otherwise have to switch on `icon` and
    /// re-derive the rendering rules.
    ///
    /// SF Symbols come back `.alwaysTemplate` regardless of `renderingMode`:
    /// tinting them per state is the whole mechanism by which they show
    /// selection.
    func image(selected: Bool) -> UIImage? {
        switch icon {
        case .system(let name):
            return UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate)
        case .images(let normal, let selectedImage):
            let image = selected ? selectedImage : normal
            switch renderingMode {
            case .template: return image.withRenderingMode(.alwaysTemplate)
            case .original: return image.withRenderingMode(.alwaysOriginal)
            }
        }
    }
}
