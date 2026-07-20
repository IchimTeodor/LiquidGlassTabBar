// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidGlassTabBar",
    // iOS 18 is the floor the bar builds against; the Liquid Glass look and
    // shrink-on-scroll activate at runtime on iOS 26+, and fall back to a
    // material blur at full size below that.
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "LiquidGlassTabBar", targets: ["LiquidGlassTabBar"]),
    ],
    targets: [
        // Shaders.metal sits alongside the Swift sources: SwiftPM compiles it
        // into a default.metallib inside this target's resource bundle, which
        // is why the lens loads its library from Bundle.module rather than
        // the main bundle.
        .target(name: "LiquidGlassTabBar"),
        .testTarget(name: "LiquidGlassTabBarTests", dependencies: ["LiquidGlassTabBar"]),
    ],
    // Swift 5 language mode, matching what this code was written against: the
    // bar's UIView conformers are main-actor in practice but are driven from
    // the deliberately nonisolated ShrinkCoordinator, which Swift 6's strict
    // checking would reject (see the note on ShrinkableBar).
    swiftLanguageModes: [.v5]
)
