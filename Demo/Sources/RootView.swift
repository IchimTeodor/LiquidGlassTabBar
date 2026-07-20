import SwiftUI
import LiquidGlassTabBar

/// Switches between the SwiftUI and UIKit hosts (same custom tab bar core
/// in both) plus a Native reference host: an untouched UITabBarController
/// whose real iOS 26 Liquid Glass bar (with minimize-on-scroll enabled)
/// serves as the ground truth to compare the custom bars against.
struct RootView: View {
    enum Host {
        case swiftUI, uiKit, native
    }

    @State private var host: Host = .swiftUI
    @State private var variant: BarVariant = .metal

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch host {
            case .swiftUI:
                SwiftUIHostView(variant: variant)
            case .uiKit:
                UIKitHostView(variant: variant)
                    .ignoresSafeArea()
            case .native:
                NativeHostView()
                    .ignoresSafeArea()
            }
            HStack {
                // The bar-variant choice only applies to the custom bar;
                // hide the button on the native reference host to keep
                // screenshots clean.
                if host != .native {
                    Button(variantButtonTitle) {
                        variant = variant == .metal ? .pill : .metal
                    }
                    .buttonStyle(.bordered)
                }
                Button(hostButtonTitle) {
                    host = Self.nextHost(after: host)
                }
                .buttonStyle(.bordered)
            }
            .padding(.trailing, 16)
        }
    }

    private var hostButtonTitle: String {
        switch host {
        case .swiftUI: return "Host: SwiftUI"
        case .uiKit: return "Host: UIKit"
        case .native: return "Host: Native"
        }
    }

    private static func nextHost(after host: Host) -> Host {
        switch host {
        case .swiftUI: return .uiKit
        case .uiKit: return .native
        case .native: return .swiftUI
        }
    }

    private var variantButtonTitle: String {
        switch variant {
        case .pill: return "Bar: v1 Pill"
        case .metal: return "Bar: Metal"
        }
    }
}
