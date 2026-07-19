# LiquidGlassTabBar

A study in rebuilding the iOS 26 **Liquid Glass** tab bar from scratch — including the refractive "bubble" that follows your finger, rendered by a real Metal fragment shader rather than stacked Core Animation layers.

The app runs the custom bar side by side with the genuine system tab bar, so the reproduction can be compared against ground truth on the same screen, at the same moment, with the same content underneath.

## What's in here

**A scroll-driven shrinking tab bar.** Scrolling down shrinks the bar to 80% anchored to its bottom edge; scrolling up restores it, with fling-aware settling. The shrink resizes the glass capsule with real Auto Layout rather than a transform — `UIVisualEffectView` renders its backdrop with its own geometry and ignores ancestor transforms, so a transform would scale the contents and leave the glass at full size.

**A Metal-shader Liquid Glass lens.** The selection bubble is a `CAMetalLayer` view whose fragment shader computes a capsule signed-distance field, derives a convex height profile and surface normal from it, and displaces the sampled backdrop inward per color channel. This is the ShaderToy-style analogue of the system's `CASDFGlassDisplacementEffect` / `CASDFGlassHighlightEffect` pair. All of its styling — shape, bezel, rim, face tint — lives in the shader; there are no UIKit rim or shine sublayers.

**Two bar variants and three hosts, switchable at runtime.** Buttons in the top-right corner toggle between the Metal bar and the original v1 pill bar (kept verbatim for comparison), and between a SwiftUI host, a UIKit host, and a native `UITabBarController` reference.

## Requirements

- Xcode 26 or later
- iOS 18.0+ deployment target
- iOS 26+ for the real `UIGlassEffect` and shrink-on-scroll; on iOS 18–25 the bar falls back to a `systemUltraThinMaterial` blur and stays at full size
- A device or simulator with Metal (the lens degrades to rendering nothing if Metal is unavailable — the rest of the bar is entirely independent of it)

## Getting started

```sh
git clone https://github.com/IchimTeodor/LiquidGlassTabBar.git
cd LiquidGlassTabBar
open LiquidGlassTabBar.xcodeproj
```

Then build and run the `LiquidGlassTabBar` scheme.

The project file is committed so the repo opens directly, but it's generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you add or remove source files, regenerate it rather than editing the project by hand:

```sh
brew install xcodegen   # once
xcodegen generate
```

## Running the tests

```sh
xcodebuild -scheme LiquidGlassTabBar -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The suite covers the pure shrink model, the scroll plumbing, and the bar's layout and drag behavior — slot geometry, tint-mask tracking, lens sizing, and title layout under shrink.

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
| `LiquidGlassTabBar/Core/` | Pure, UI-free shrink logic: the shrink model, the scroll-to-model bridge, KVO scroll observation |
| `LiquidGlassTabBar/TabBar/` | Both bar implementations, the Metal lens view, and the shader |
| `LiquidGlassTabBar/SwiftUIHost/` | SwiftUI host and the `.shrinksTabBar()` modifier |
| `LiquidGlassTabBar/UIKitHost/` | UIKit host and the native reference host |
| `Tests/` | Swift Testing suites |
| `docs/` | Design spec and implementation plan |

`TabBarShrinkModel` is deliberately free of UIKit: it takes scroll samples and produces a progress value, so the scroll behavior is testable without a view hierarchy.

## Contributing

Contributions are welcome. `main` is protected — please open a pull request rather than pushing directly:

1. Fork the repo and branch off `main`
2. Make your change, and add or update tests to cover it
3. Confirm the full suite passes (see above)
4. Open a PR describing what changed and why

If you're tuning the lens's visual parameters, please say what you compared against — the existing constants were set by eye against native screenshots, and the comments record the reasoning so future changes don't undo hard-won lessons.
