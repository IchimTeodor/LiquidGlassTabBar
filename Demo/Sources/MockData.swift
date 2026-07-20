import UIKit
import LiquidGlassTabBar

enum MockData {
    /// Exercises both icon kinds and the badge styles: three SF Symbol items
    /// (one with a dot, one with a count) plus one built from supplied
    /// artwork, so the demo covers both of `TabItem`'s initializers rather
    /// than only the symbol path.
    @MainActor
    static let tabs: [TabItem] = [
        TabItem(title: "Home", systemImage: "house.fill"),
        TabItem(title: "Search", systemImage: "magnifyingglass", badge: .dot),
        TabItem(title: "Favorites", systemImage: "heart.fill", badge: .count(3)),
        TabItem(title: "Profile",
                image: profileImage(selected: false),
                selectedImage: profileImage(selected: true)),
    ]

    @MainActor
    static func rows(for tab: Int) -> [String] {
        (1...50).map { "\(tabs[tab].title) row \($0)" }
    }

    /// Stands in for artwork an app would ship as an asset. Drawn from a
    /// symbol purely so the demo needs no bundled image files — what matters
    /// is that these arrive as plain UIImages, with a distinct one for the
    /// selected state, exactly as real artwork would.
    @MainActor
    private static func profileImage(selected: Bool) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        let name = selected ? "person.crop.circle.fill" : "person.crop.circle"
        return UIImage(systemName: name, withConfiguration: configuration) ?? UIImage()
    }
}
