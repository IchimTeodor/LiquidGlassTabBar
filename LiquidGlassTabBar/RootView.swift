import SwiftUI

/// Switches between the SwiftUI and UIKit hosts to demonstrate that the same
/// tab bar core behaves identically in both.
struct RootView: View {
    @State private var useUIKit = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if useUIKit {
                UIKitHostView()
                    .ignoresSafeArea()
            } else {
                SwiftUIHostView()
            }
            Button(useUIKit ? "Host: UIKit" : "Host: SwiftUI") {
                useUIKit.toggle()
            }
            .buttonStyle(.bordered)
            .padding(.trailing, 16)
        }
    }
}
