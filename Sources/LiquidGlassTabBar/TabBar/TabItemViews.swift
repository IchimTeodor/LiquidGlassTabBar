import UIKit

/// The badge drawn at an item icon's top-trailing corner: a bare dot, or a
/// capsule around a count or short string.
///
/// It lives in BOTH item rows (the gray base row and the tinted replica the
/// lens reveals) with identical colors, so the badge looks the same whether
/// or not the bubble is over it — matching the system bar, where a badge
/// stays red regardless of selection.
@MainActor
final class BadgeView: UIView {
    private static let dotDiameter: CGFloat = 8
    private static let horizontalPadding: CGFloat = 5
    private static let minimumCapsuleHeight: CGFloat = 16

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .systemRed
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ badge: TabBadge) {
        isHidden = !badge.isVisible
        label.text = badge.displayText
        label.isHidden = badge.displayText == nil
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        guard let text = label.text, !text.isEmpty else {
            return CGSize(width: Self.dotDiameter, height: Self.dotDiameter)
        }
        let textSize = label.intrinsicContentSize
        // Capsules stay at least as wide as they are tall, so a single digit
        // renders as a circle rather than a squeezed pill.
        let height = max(textSize.height, Self.minimumCapsuleHeight)
        return CGSize(width: max(textSize.width + Self.horizontalPadding * 2, height),
                      height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// Builds the item buttons for both bar variants.
///
/// The two rows differ only in which image and tint they use: the base row
/// draws the unselected artwork in the unselected color, and the replica the
/// bar masks with the lens draws the selected artwork in the selected color.
/// Selection is therefore expressed by REVEALING the replica, which is what
/// lets a dragged bubble color part of one icon and part of the next.
@MainActor
enum TabItemViews {
    /// Vertical inset from the button's top to the badge, and horizontal
    /// offset from its center — the icon is centered and sits at the top, so
    /// anchoring to the button's own edges puts the badge at the icon's
    /// top-trailing corner without reaching into UIButton's internals.
    private static let badgeTopInset: CGFloat = 1
    private static let badgeCenterOffset: CGFloat = 9

    static func makeButton(for item: TabItem,
                           selected: Bool,
                           tint: UIColor,
                           interactive: Bool) -> (button: UIButton, badge: BadgeView) {
        var config = UIButton.Configuration.plain()
        config.image = item.image(selected: selected)
        config.title = item.title
        config.imagePlacement = .top
        config.imagePadding = 2
        config.baseForegroundColor = tint
        // Reclaim the plain() configuration's default 16pt side insets: they
        // eat 32pt of a slot that is only ~68pt wide at full shrink, which
        // left "Favorites" 36pt for a 48pt word and hyphen-wrapped it onto
        // two lines. The shrink narrows slots via REAL layout while the 0.8
        // content scale is a transform applied afterwards, so the title must
        // fit the shrunk slot at FULL font size — the squeeze is entirely in
        // the insets. Titles are centered and far narrower than a bare slot,
        // so neighbours still don't touch. Vertical insets are untouched
        // (they set the button's height).
        config.contentInsets.leading = 0
        config.contentInsets.trailing = 0
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = UIFont.preferredFont(forTextStyle: .caption2)
                return updated
            }
        let button = UIButton(configuration: config)
        button.isUserInteractionEnabled = interactive

        let badge = BadgeView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.apply(item.badge)
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: button.centerXAnchor,
                                           constant: badgeCenterOffset),
            badge.topAnchor.constraint(equalTo: button.topAnchor, constant: badgeTopInset),
        ])
        return (button, badge)
    }

    /// Re-applies just the parts that can change after construction, so a
    /// tint change doesn't have to rebuild (and re-lay-out) the whole row.
    static func updateTint(_ button: UIButton, to tint: UIColor) {
        button.configuration?.baseForegroundColor = tint
    }

}
