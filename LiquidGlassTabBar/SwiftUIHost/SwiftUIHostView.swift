import SwiftUI

/// 4-tab mock host built on a native TabView (system tab bar hidden),
/// driving the shared shrink coordinator via the .shrinksTabBar() modifier.
/// Each tab owns its own ScrollView, so scroll positions persist across
/// tab switches.
struct SwiftUIHostView: View {
    var variant: BarVariant = .metal
    @State private var selectedIndex = 0
    @State private var coordinator = ShrinkCoordinator()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedIndex) {
                ForEach(MockData.tabs.indices, id: \.self) { index in
                    tabContent(for: index)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(index)
                }
            }
            .environment(\.shrinkCoordinator, coordinator)
            ShrinkingTabBarView(items: MockData.tabs,
                                selectedIndex: $selectedIndex,
                                coordinator: coordinator,
                                variant: variant)
                .frame(height: 64)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .onChange(of: selectedIndex) {
            coordinator.tabChanged()
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
        .shrinksTabBar()
    }
}
