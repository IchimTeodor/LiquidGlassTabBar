# LiquidGlassTabBar

A study in rebuilding the iOS 26 **Liquid Glass** tab bar from scratch — including the refractive "bubble" that follows your finger, rendered by a real Metal fragment shader rather than stacked Core Animation layers.

It ships as a Swift package you can drop into an app, plus a demo that runs the custom bar side by side with the genuine system tab bar — so the reproduction can be compared against ground truth on the same screen, at the same moment, with the same content underneath.

## What's in here

**A scroll-driven shrinking tab bar.** Scrolling down shrinks the bar to 80% anchored to its bottom edge; scrolling up restores it, with fling-aware settling. The shrink resizes the glass capsule with real Auto Layout rather than a transform — `UIVisualEffectView` renders its backdrop with its own geometry and ignores ancestor transforms, so a transform would scale the contents and leave the glass at full size.

**A Metal-shader Liquid Glass lens.** The selection bubble is a `CAMetalLayer` view whose fragment shader computes a capsule signed-distance field, derives a convex height profile and surface normal from it, and displaces the sampled backdrop inward per color channel. This is the ShaderToy-style analogue of the system's `CASDFGlassDisplacementEffect` / `CASDFGlassHighlightEffect` pair. All of its styling — shape, bezel, rim, face tint — lives in the shader; there are no UIKit rim or shine sublayers.

**Two bar variants and three hosts, switchable at runtime.** Buttons in the top-right corner toggle between the Metal bar and the original v1 pill bar (kept verbatim for comparison), and between a SwiftUI host, a UIKit host, and a native `UITabBarController` reference.

## Requirements

- Xcode 26 or later
- Swift 6 language mode (the package builds cleanly under strict concurrency)
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

Hand the bar your items and a selection binding. Shrink-on-scroll is on by default and needs no wiring — nothing is attached to your scroll views, and there is no coordinator to build:

```swift
import SwiftUI
import LiquidGlassTabBar

struct ContentView: View {
    private let items = [
        TabItem(title: "Home", systemImage: "house.fill"),
        TabItem(title: "Search", systemImage: "magnifyingglass"),
    ]
    @State private var selectedIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                // your content
            }

            ShrinkingTabBarView(items: items, selectedIndex: $selectedIndex)
                .frame(height: 64)
                .padding(.horizontal, 16)
        }
    }
}
```

UIKit is the same idea — add the bar and you're done:

```swift
let bar = ShrinkingTabBar(items: items)
bar.onSelect = { index in /* switch tabs */ }
view.addSubview(bar)
// bar.minimizesOnScroll is already true; nothing else to wire.
```

### Icons

Items take either an SF Symbol or your own artwork, with a separate image for the selected state:

```swift
TabItem(title: "Home", systemImage: "house.fill")

TabItem(title: "Profile",
        image: UIImage(named: "profile")!,
        selectedImage: UIImage(named: "profile.fill")!)
```

Supplied artwork is template-rendered by default, so it picks up the bar's tints like a symbol does. Pass `renderingMode: .original` for multicolor artwork that tinting would flatten to a single color. SF Symbols are always template — tinting them per state is how they show selection.

### Badges

```swift
TabItem(title: "Search", systemImage: "magnifyingglass", badge: .dot)
TabItem(title: "Inbox", systemImage: "tray", badge: .count(3))
```

`TabBadge` is `.none`, `.dot`, or `.text(String)`. `count(_:maximum:)` is a factory over those: it clamps to `"99+"` by default and returns `.none` for zero, so an unread count can be bound straight through without special-casing empty.

Badges are state, so they change without rebuilding items:

```swift
bar.setBadge(.count(unreadCount), at: 1)   // UIKit
```

In SwiftUI they come from the items array — change an item's badge in your state and the bar follows.

### Tints and shrink progress

```swift
bar.selectedTintColor = .systemIndigo
bar.unselectedTintColor = .secondaryLabel
bar.onShrinkProgress = { progress in /* 0 = full size, 1 = fully shrunk */ }
```

```swift
ShrinkingTabBarView(items: items, selectedIndex: $selectedIndex)
    .tabBarTints(selected: .systemIndigo, unselected: .secondaryLabel)
    .onTabBarShrink { progress in shrinkProgress = progress }
```

`onShrinkProgress` fires only when the value actually changes, and reports the target of an animated shrink rather than once per frame — it's a signal about intent (fade a header, say), not an animation clock.

### How it finds your scroll views

The bar puts an inert probe gesture recognizer on its window. Recognizers on an ancestor are offered every touch that lands in a descendant, so the probe is asked about each touch-down anywhere in the app; walking up from the touched view finds the scroll view containing it, which is observed from then on. The probe always declines the touch, so it never begins, and cannot delay, cancel, or compete with anything.

Discovery happens on touch rather than by scanning the hierarchy up front because scroll views appear lazily — an unselected tab, a sheet, or a lazily built list has none yet when the bar is installed, and UIKit offers no general "a scroll view was added" hook to re-scan on. A scroll view you're touching definitely exists, and that touch is exactly when the shrink is about to need it.

The same mechanism serves both frameworks: a SwiftUI `ScrollView` is backed by a `UIScrollView`, so it's discovered the same way a `UITableView` is.

### Driving it yourself

To control the shrink manually, hand the bar a `ShrinkCoordinator`. That switches the automatic path off, so the two can't both push progress into the same bar:

```swift
let coordinator = ShrinkCoordinator()
coordinator.bar = bar                  // turns off bar.minimizesOnScroll
let observer = ScrollShrinkObserver(coordinator: coordinator)
observer.attach(to: tableView)         // attach the ones you care about
```

In SwiftUI, pass the coordinator to `ShrinkingTabBarView(items:selectedIndex:variant:coordinator:)` and attach `.shrinksTabBar()` to the scroll views that should drive it, with the coordinator injected via `.environment(\.shrinkCoordinator, coordinator)`.

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
