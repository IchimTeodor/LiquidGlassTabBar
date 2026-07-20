import Foundation
import LiquidGlassTabBar

enum MockData {
    static let tabs: [TabItem] = [
        TabItem(title: "Home", systemImage: "house.fill"),
        TabItem(title: "Search", systemImage: "magnifyingglass"),
        TabItem(title: "Favorites", systemImage: "heart.fill"),
        TabItem(title: "Profile", systemImage: "person.fill"),
    ]

    static func rows(for tab: Int) -> [String] {
        (1...50).map { "\(tabs[tab].title) row \($0)" }
    }
}
