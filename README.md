# LiquidGlassTabBar

A study in rebuilding the iOS 26 **Liquid Glass** tab bar from scratch — including the refractive "bubble" that follows your finger, rendered by a real Metal fragment shader rather than stacked Core Animation layers.

It ships as a Swift package you can drop into an app, plus a demo that runs the custom bar side by side with the genuine system tab bar — so the reproduction can be compared against ground truth on the same screen, at the same moment, with the same content underneath.

## What's in here

**A scroll-driven shrinking tab bar.** Scrolling down shrinks the bar to 80% anchored to its bottom edge; scrolling up restores it, with fling-aware settling. The shrink resizes the glass capsule with real Auto Layout rather than a transform — `UIVisualEffectView` renders its backdrop with its own geometry and ignores ancestor transforms, so a transform would scale the contents and leave the glass at full size.

**A Metal-shader Liquid Glass lens.** The selection bubble is a `CAMetalLayer` view whose fragment shader computes a capsule signed-distance field, derives a convex height profile and surface normal from it, and displaces the sampled backdrop inward per color channel. This is the ShaderToy-style analogue of the system's `CASDFGlassDisplacementEffect` / `CASDFGlassHighlightEffect` pair. All of its styling — shape, bezel, rim, face tint — lives in the shader; there are no UIKit rim or shine sublayers.

**Two bar variants and three hosts, switchable at runtime.** Buttons in the top-right corner toggle between the Metal bar and the original v1 pill bar (kept verbatim for comparison), and between a SwiftUI host, a UIKit host, and a native `UITabBarController` reference.

## Requirements

- Xcode 26 or later
- iOS 18.0+ deployment target
- iOS 26+ for the real `UIGlassEffect` and shrink-on-scroll; on iOS 18–25 the bar falls back to a `systemUltraThinMaterial` blur and stays at full size
- A device or simulator with Metal (the lens degrades to rendering nothing if Metal is unavailable — the rest of the bar is entirely independent of it)

## Installation

Add the package in Xcode via **File → Add Package Dependencies**, or declare it directly:

```swift
dependencies: [
    .package(url: "https://github.com/IchimTeodor/LiquidGlassTabBar.git", from: "1.0.0")
]
```

Then `import LiquidGlassTabBar`.

## Usage

In SwiftUI, hand the bar your items and a selection binding, and attach `.shrinksTabBar()` to the scroll view that should drive the shrink:

```swift
import SwiftUI
import LiquidGlassTabBar

struct ContentView: View {
    private let items = [
        TabItem(title: "Home", systemImage: "house.fill"),
        TabItem(title: "Search", systemImage: "magnifyingglass"),
    ]
    @State private var selectedIndex = 0
    @State private var coordinator = ShrinkCoordinator()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                // your content
            }
            .shrinksTabBar()
            .environment(\.shrinkCoordinator, coordinator)

            ShrinkingTabBarView(items: items,
                                selectedIndex: $selectedIndex,
                                coordinator: coordinator)
                .frame(height: 64)
                .padding(.horizontal, 16)
        }
    }
}
```

In UIKit, add `ShrinkingTabBar` as a subview and point a `ScrollShrinkObserver` at each scroll view:

```swift
let bar = ShrinkingTabBar(items: items)
bar.onSelect = { index in /* switch tabs */ }

let coordinator = ShrinkCoordinator()
coordinator.bar = bar
let observer = ScrollShrinkObserver(coordinator: coordinator)
observer.attach(to: tableView)
```

The scroll views never need to know about the bar — the observer watches `contentOffset` via KVO and drives the shared coordinator.

## Running the demo

```sh
git clone https://github.com/IchimTeodor/LiquidGlassTabBar.git
open LiquidGlassTabBar/Demo/LiquidGlassTabBarDemo.xcodeproj
```

Build and run the `LiquidGlassTabBarDemo` scheme. The demo project is committed so it opens directly, but it's generated from `Demo/project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you add or remove demo files, regenerate rather than editing the project by hand:

```sh
brew install xcodegen   # once
cd Demo && xcodegen generate
```

## Running the tests

```sh
xcodebuild -scheme LiquidGlassTabBar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The suite covers the pure shrink model, the scroll plumbing, and the bar's layout and drag behavior — slot geometry, tint-mask tracking, lens sizing, and title layout under shrink. A simulator destination is required: the package is iOS-only, so `swift test` on macOS won't build it.

## How the lens works

The interesting engineering is in `MetalLensView.swift` and `Shaders.metal`. A few decisions worth knowing before reading them:

**Snapshot once, slide the window.** The entire bar content is rasterized into a single texture when a drag begins — the content is static during a drag; only the lens moves. Each display-link tick then updates uniforms and re-encodes one small draw. An earlier per-frame `drawHierarchy` was what made the refraction visibly trail the bubble.

**The sampling origin comes from the presentation layer, one frame ahead.** The bubble rides an underdamped spring, so the model position is not where it appears. The shader reads the in-flight presentation position and extrapolates along the measured velocity to where the lens will be when the drawable actually reaches the glass.

**The displacement profile is fold-free by construction.** For content to magnify rather than tear, the inward sampling map's slope must stay in `(-1, 0)` everywhere. Earlier smoothstep-based profiles exceeded that and folded, shredding content into thin filaments. The current profile is quadratic with its slope clamped below 1, which guarantees monotonicity — bold rim magnification with no duplicates or shredding.

**Presentation is transaction-synchronized.** With the default async present, the drawable reaches the screen one frame after the Core Animation transaction that moved the lens. `presentsWithTransaction` plus commit / `waitUntilScheduled` / present lands it in the same frame CA is building.

Both files carry extensive comments recording what was tried and rejected, which is most of the value if you're attempting something similar.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/LiquidGlassTabBar/Core/` | Pure, UI-free shrink logic: the shrink model, the scroll-to-model bridge, KVO scroll observation |
| `Sources/LiquidGlassTabBar/TabBar/` | Both bar implementations, the Metal lens view, and the shader |
| `Sources/LiquidGlassTabBar/SwiftUI/` | `ShrinkingTabBarView` and the `.shrinksTabBar()` modifier |
| `Tests/LiquidGlassTabBarTests/` | Swift Testing suites |
| `Demo/` | The demo app: SwiftUI host, UIKit host, and the native reference host |
| `docs/` | Design spec and implementation plan |

`TabBarShrinkModel` is deliberately free of UIKit: it takes scroll samples and produces a progress value, so the scroll behavior is testable without a view hierarchy.

`Shaders.metal` lives alongside the Swift sources, so SwiftPM compiles it into a `default.metallib` inside the target's resource bundle. That's why the lens loads its library from `Bundle.module` — the no-argument `makeDefaultLibrary()` reads the *main* bundle, which in a package consumer holds the app's shaders, not the package's.

## Contributing

Contributions are welcome. `main` is protected — please open a pull request rather than pushing directly:

1. Fork the repo and branch off `main`
2. Make your change, and add or update tests to cover it
3. Confirm the full suite passes (see above)
4. Open a PR describing what changed and why

If you're tuning the lens's visual parameters, please say what you compared against — the existing constants were set by eye against native screenshots, and the comments record the reasoning so future changes don't undo hard-won lessons.
