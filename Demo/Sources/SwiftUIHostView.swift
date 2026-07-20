import SwiftUI
import LiquidGlassTabBar

/// 4-tab mock host built on a native TabView (system tab bar hidden).
/// Each tab owns its own ScrollView, so scroll positions persist across
/// tab switches.
///
/// Note what is NOT here: no coordinator, no environment injection, and
/// nothing attached to the individual ScrollViews. The bar discovers
/// whichever scroll view is touched and shrinks itself.
struct SwiftUIHostView: View {
    var variant: BarVariant = .metal
    @State private var selectedIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedIndex) {
                ForEach(MockData.tabs.indices, id: \.self) { index in
                    tabContent(for: index)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(index)
                }
            }
            ShrinkingTabBarView(items: MockData.tabs,
                                selectedIndex: $selectedIndex,
                                variant: variant)
                .frame(height: 64)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
    }

    private func tabContent(for index: Int) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(MockData.rows(for: index), id: \.self) { row in
                    Text(row)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    Divider()
                }
            }
            .padding(.bottom, 90) // keep last rows clear of the bar
        }
    }
}
