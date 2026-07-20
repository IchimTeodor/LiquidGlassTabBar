import UIKit

/// The ORIGINAL v1 bar, kept VERBATIM from commit 7ef4e84 ("fix: begin pill
/// drag from current animation state") as a reference point for the demo —
/// the only edits are the class rename (ShrinkingTabBar -> PillTabBar, so it
/// can coexist with the final metal-lens bar) and the ShrinkableBar
/// conformance the hosts use to swap variants. Do not modernize it; its
/// value is being exactly what was built first.
///
/// Custom tab bar with a Liquid Glass background (iOS 26+, material fallback
/// on iOS 18–25) that shrinks between full size and 0.8, anchored to its
/// bottom edge, with a selection pill that tracks finger drags across the
/// bar like the native iOS 26 tab bar.
///
/// The shrink resizes the glass capsule with real layout instead of applying
/// a CGAffineTransform to the bar: UIVisualEffectView's backdrop is rendered
/// with its own geometry and ignores ancestor transforms, so a transform
/// scales the bar's content but leaves the glass at full size. Item buttons
/// get a matching content-scale transform (ordinary views honor transforms).
public final class PillTabBar: UIView, ShrinkableBar {
    static let minScale: CGFloat = 0.8

    static func scale(for progress: CGFloat) -> CGFloat {
        1 - (1 - minScale) * min(max(progress, 0), 1)
    }

    /// The glass capsule's frame at `progress` inside a bar of size `bounds`,
    /// anchored bottom-center.
    static func glassFrame(progress: CGFloat, in bounds: CGSize) -> CGRect {
        let s = scale(for: progress)
        let size = CGSize(width: bounds.width * s, height: bounds.height * s)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: bounds.height - size.height,
                      width: size.width,
                      height: size.height)
    }

    /// Nearest item index for a horizontal position within the item strip.
    static func nearestIndex(forX x: CGFloat, stripWidth: CGFloat, count: Int) -> Int {
        guard count > 0, stripWidth > 0 else { return 0 }
        let slot = stripWidth / CGFloat(count)
        return min(max(Int(x / slot), 0), count - 1)
    }

    public var onSelect: ((Int) -> Void)?

    /// Shrink in response to ANY scroll view the user drags, discovered
    /// automatically — no coordinator to build and no per-scroll-view
    /// wiring, in UIKit or SwiftUI alike. This is the whole setup:
    ///
    ///     bar.minimizesOnScroll = true
    ///
    /// Assigning this bar to a `ShrinkCoordinator` turns it off, since that
    /// means you are driving the shrink yourself.
    public var minimizesOnScroll: Bool = true {
        didSet { refreshAutomaticShrink() }
    }

    private let automaticShrink = AutomaticShrink()

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        // The probe rides the window, so it can only be installed once
        // there is one — and must follow the bar if it changes windows.
        refreshAutomaticShrink()
    }

    private func refreshAutomaticShrink() {
        automaticShrink.refresh(isEnabled: minimizesOnScroll, bar: self, window: window)
    }
    public var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }

    /// Test hook: the glass capsule's current frame within the bar.
    var glassFrameForTesting: CGRect { effectView.frame }
    /// Test hook: the selection pill's current frame within the bar.
    var pillFrameForTesting: CGRect { pill.frame }
    /// Test hook: the selection pill's current alpha (0 at rest, 1 mid-drag).
    var pillAlphaForTesting: CGFloat { pill.alpha }

    private let effectView: UIVisualEffectView
    private let pill: UIView
    private let stack = UIStackView()
    private var itemButtons: [UIButton] = []
    private var progress: CGFloat = 0
    private var glassWidth: NSLayoutConstraint!
    private var glassHeight: NSLayoutConstraint!
    private var isDraggingPill = false

    public init(items: [TabItem]) {
        if #available(iOS 26.0, *) {
            effectView = UIVisualEffectView(effect: UIGlassEffect())
            let glass = UIGlassEffect()
            glass.isInteractive = true
            pill = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            let fill = UIView()
            fill.backgroundColor = .systemFill
            pill = fill
        }
        super.init(frame: .zero)

        effectView.clipsToBounds = true
        effectView.layer.cornerCurve = .continuous
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, item) in items.enumerated() {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: item.systemImage)
            config.title = item.title
            config.imagePlacement = .top
            config.imagePadding = 2
            config.preferredSymbolConfigurationForImage =
                UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            config.titleTextAttributesTransformer =
                UIConfigurationTextAttributesTransformer { attributes in
                    var updated = attributes
                    updated.font = UIFont.preferredFont(forTextStyle: .caption2)
                    return updated
                }
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedIndex = index
                self?.onSelect?(index)
            }, for: .touchUpInside)
            itemButtons.append(button)
            stack.addArrangedSubview(button)
        }

        // Sibling above the glass capsule but below the item buttons, so the
        // buttons render crisply on top of the pill — a glass pill must never
        // be nested inside another effect view's contentView. Hidden at rest:
        // the pill only materializes while a drag is in flight.
        pill.isUserInteractionEnabled = false
        pill.clipsToBounds = true
        pill.layer.cornerCurve = .continuous
        pill.alpha = 0
        addSubview(pill)
        addSubview(stack)

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))

        glassWidth = effectView.widthAnchor.constraint(equalToConstant: 0)
        glassHeight = effectView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            effectView.centerXAnchor.constraint(equalTo: centerXAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassWidth,
            glassHeight,
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        updateSelection()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        applyProgress()
    }

    public func setProgress(_ newProgress: CGFloat, animated: Bool) {
        progress = min(max(newProgress, 0), 1)
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0,
                           usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: {
                self.applyProgress()
                self.layoutIfNeeded()
            })
        } else {
            applyProgress()
            // Constraint-constant changes outside a layout pass don't
            // reliably dirty layout on their own; scoped here (never from
            // inside layoutSubviews) so layout can't re-dirty itself.
            setNeedsLayout()
        }
    }

    /// Test hook: activate the item at `index` as a tap would.
    func simulateTap(at index: Int) {
        itemButtons[index].sendActions(for: .touchUpInside)
    }

    /// Test hook: drive the pill drag programmatically (x in bar coordinates).
    /// Mirrors handlePan: the first non-ended call begins the drag
    /// (materializes the pill), subsequent ones move it.
    func simulatePillDrag(toX x: CGFloat, ended: Bool) {
        if ended {
            finishPillDrag(atX: x)
        } else if isDraggingPill {
            movePill(toX: x)
        } else {
            beginPillDrag(atX: x)
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let x = recognizer.location(in: self).x
        switch recognizer.state {
        case .began:
            beginPillDrag(atX: x)
        case .changed:
            movePill(toX: x)
        case .ended, .cancelled, .failed:
            finishPillDrag(atX: x)
        default:
            break
        }
    }

    private func stripFrame() -> CGRect {
        stack.frame
    }

    private func pillFrame(forIndex index: Int) -> CGRect {
        guard itemButtons.indices.contains(index) else { return .zero }
        // Force the stack to finish its own internal (fillEqually) layout
        // before reading button geometry: UIStackView resizes arranged
        // subviews during its own layoutSubviews, which — inside our
        // ancestor's layoutSubviews — hasn't run yet, so button frames here
        // would otherwise still reflect the previous size.
        stack.layoutIfNeeded()
        // Use the button's untransformed layout geometry: `frame` is the
        // transformed bounding box while the content-scale transform is
        // active, which would double-shrink the pill (slot already scales
        // via real layout). `center`/`bounds` are unaffected by transform.
        let button = itemButtons[index]
        let layoutFrame = CGRect(x: button.center.x - button.bounds.width / 2,
                                 y: button.center.y - button.bounds.height / 2,
                                 width: button.bounds.width,
                                 height: button.bounds.height)
        return convert(layoutFrame, from: stack).insetBy(dx: 2, dy: 6)
    }

    /// Materializes the pill at drag start: sized to the slot of the item
    /// nearest the touch, centered under the finger, fading in like the
    /// native lens.
    private func beginPillDrag(atX x: CGFloat) {
        isDraggingPill = true
        let strip = stripFrame()
        let index = Self.nearestIndex(forX: x - strip.minX,
                                      stripWidth: strip.width,
                                      count: itemButtons.count)
        // Frame setup shares the fade-in's animation block: a rapid re-drag
        // can begin while the previous release's dissolve is still gliding
        // the pill toward its slot, and a direct (non-animated) frame set
        // would snap it out from under that animation. One from-current-state
        // block hands off smoothly instead.
        UIView.animate(withDuration: 0.15, delay: 0,
                       options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.pill.frame = self.pillFrame(forIndex: index)
            self.pill.layer.cornerRadius = self.pill.frame.height / 2
            self.movePill(toX: x)
            self.pill.alpha = 1
        })
    }

    private func movePill(toX x: CGFloat) {
        let strip = stripFrame()
        guard strip.width > 0 else { return }
        let half = pill.frame.width / 2
        pill.center.x = min(max(x, strip.minX + half), strip.maxX - half)
    }

    private func finishPillDrag(atX x: CGFloat) {
        let strip = stripFrame()
        let index = Self.nearestIndex(forX: x - strip.minX,
                                      stripWidth: strip.width,
                                      count: itemButtons.count)
        isDraggingPill = false
        if index != selectedIndex {
            selectedIndex = index
        }
        // Glide to the chosen slot while dissolving, like the native lens.
        let target = pillFrame(forIndex: index)
        UIView.animate(withDuration: 0.25, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.pill.center = CGPoint(x: target.midX, y: target.midY)
            self.pill.alpha = 0
        })
        onSelect?(index)  // fires for same-index release too, matching tap behavior
    }

    private func applyProgress() {
        let frame = Self.glassFrame(progress: progress, in: bounds.size)
        glassWidth.constant = frame.width
        glassHeight.constant = frame.height
        effectView.layer.cornerRadius = frame.height / 2
        let s = Self.scale(for: progress)
        for button in itemButtons {
            button.transform = CGAffineTransform(scaleX: s, y: s)
        }
        // The pill is hidden unless dragging; its size is set at drag begin.
    }

    private func updateSelection() {
        for (index, button) in itemButtons.enumerated() {
            button.configuration?.baseForegroundColor =
                index == selectedIndex ? .systemBlue : .secondaryLabel
        }
    }
}
