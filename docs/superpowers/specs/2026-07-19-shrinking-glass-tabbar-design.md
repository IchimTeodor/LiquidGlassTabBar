# Shrinking Liquid Glass Tab Bar — Design

**Date:** 2026-07-19
**Status:** Approved

## Goal

A custom tab bar with a Liquid Glass background that progressively shrinks to a
0.8 scale factor as the user scrolls down, and restores to full size on scroll
up. Behavior must be identical whether the host screen is UIKit or SwiftUI.

## Why custom (native tab bar findings)

On iOS 26 the native tab bar supports scroll-driven *minimization*
(`.tabBarMinimizeBehavior(.onScrollDown)` in SwiftUI,
`UITabBarController.tabBarMinimizeBehavior` in UIKit), but that collapses the
bar to a single-tab pill. There is no native API for a proportional 0.8 scale
with all tabs visible, so a custom bar is required. The custom bar uses the
Liquid Glass APIs directly so it still looks native.

## Constraints

- Deployment target: **iOS 18.0**.
- Liquid Glass (`UIGlassEffect`) on iOS 26+; fallback to
  `UIBlurEffect(style: .systemUltraThinMaterial)` on iOS 18–25.
- **Shrinking is iOS 26+ only.** On iOS 18–25 the bar keeps its material
  background and stays at full size regardless of scrolling; the shrink
  behavior accompanies the Liquid Glass appearance. Gated in one place
  (`ShrinkCoordinator`) so both hosts stay consistent.
- Swift, no external dependencies.
- Project generated with XcodeGen (`project.yml` committed).

## Architecture — one core, two wrappers

```
TabBarShrinkModel (pure logic, unit-tested)
        │  scroll events in → progress (0…1) out
        ▼
ShrinkingTabBar (UIKit UIView) — single source of truth for look & animation
   ├─ Glass background (UIGlassEffect / material fallback)
   ├─ Capsule shape, 4 items (SF Symbol + label), tint-based selection
   └─ setProgress(_:) maps 0…1 → scale 1.0…0.8, anchored bottom-center
        │
   ┌────┴─────────────────┐
   ▼                      ▼
UIKit host            SwiftUI wrapper (UIViewRepresentable)
(direct use)          + CustomTabContainer view
```

### TabBarShrinkModel

Pure, framework-free type. Input: scroll offset samples plus drag phase
(dragging / ended). Output: progress in 0…1.

- Progressive tracking: ~80 pt of downward scroll maps linearly to progress
  0 → 1; upward scroll reverses it.
- Near content top (offset ≤ 0 after adjusting for content inset): progress
  forced to 0 (bar always full size).
- Bounce/rubber-band regions (offset < 0 or beyond max) are ignored.
- On drag end: settle to the nearest endpoint (0 or 1), honoring fling
  direction when velocity is significant.

### ShrinkingTabBar (UIKit view)

- `UIVisualEffectView` background: `UIGlassEffect` when available
  (`#available(iOS 26, *)`), else ultra-thin material; capsule corner shape.
- 4 tab items rendered as SF Symbol + caption label; selected item tinted.
- **Drag-only liquid glass pill**: at rest there is NO pill — selection is
  shown by tint alone. When a pan begins on the bar, an interactive liquid
  glass lens (`UIGlassEffect` with `isInteractive = true` on iOS 26;
  `.systemFill` capsule on iOS 18–25) materializes sized to the item slot,
  follows the finger horizontally (clamped to the item strip), and on
  release snaps to the nearest item, selects it, and fades out — matching
  the native iOS 26 tab bar's drag interaction. The pill is a
  non-interactive sibling above the bar's glass (never nested inside
  another effect view), below the item buttons.
- `setProgress(_:)` shrinks the bar with **real layout, not a transform**:
  the glass capsule's width/height constraints interpolate to 0.8×, anchored
  bottom-center, with corner radius tracking the shrunken height; item
  buttons get a matching content-scale transform. (A `CGAffineTransform` on
  the bar does not work: `UIVisualEffectView`'s backdrop is rendered with its
  own geometry and ignores ancestor transforms, so only content would scale —
  found during on-device verification.) Settle animations use a spring.
- `onSelect: (Int) -> Void` callback; `selectedIndex` settable from outside.

### Scroll feeds — content views know nothing about the bar

- UIKit: `ScrollShrinkObserver` — one instance per host; `attach(to:)` wires
  any `UIScrollView` via KVO on `contentOffset` plus a target-action on the
  scroll view's own `panGestureRecognizer` for drag begin/end. Content view
  controllers carry no tab-bar code.
- SwiftUI: `.shrinksTabBar()` modifier reading the coordinator from the
  environment (`\.shrinkCoordinator`, injected once at the container).
  No per-tab guards needed: only the actively dragged scroll view emits
  `.interacting` phase changes, and the coordinator ignores samples outside
  a drag.

Both worlds drive the same model and the same view → identical behavior.

## Mock app

- 4 tabs: **Home, Search, Favorites, Profile** — each a scrollable list of
  ~50 mock rows, **each tab owning its own scroll view** with its scroll
  position preserved across tab switches.
- Hosts use the native tab containers with their system bars hidden and the
  custom bar overlaid: the **SwiftUI host** is a `TabView(selection:)`
  (children apply `.toolbar(.hidden, for: .tabBar)`); the **UIKit host** is
  a `UITabBarController` subclass with `tabBar.isHidden = true`.
- Launches into the SwiftUI host; a toggle switches to the UIKit host, both
  using the same `ShrinkingTabBar`.
- Custom bar overlaid at the bottom, respecting the safe area. Tab switch
  still resets the bar to full size.

## Edge cases

- Content shorter than the screen → bar never shrinks.
- Rapid direction reversal mid-drag → progress follows the delta continuously;
  no snapping until release.
- Tab switch while shrunk → bar animates back to full size (each tab's own
  scroll position is preserved; the shrink model re-baselines on the next
  drag).

## Testing

- Unit tests for `TabBarShrinkModel`: progress math, top-of-content rule,
  bounce handling, settle direction with/without velocity.
- Unit test that a shrink-disabled coordinator never shrinks; shrink-behavior
  tests construct the coordinator with shrinking explicitly enabled so the
  suite passes on both iOS 18 and iOS 26 simulators.
- Build + tests run via `xcodebuild` against the iOS simulator.
- Manual verification of glass rendering and animation feel in the simulator.
