import UIKit

/// Custom tab bar with a Liquid Glass background (iOS 26+, material fallback
/// on iOS 18–25) that shrinks between full size and 0.8, anchored to its
/// bottom edge, with a Metal-shader lens (see MetalLensView/Shaders.metal)
/// that tracks finger drags across the bar like the native iOS 26 tab bar.
/// This is the FINAL variant of the bar; the original v1 pill bar is kept
/// verbatim as `PillTabBar` for comparison (see BarVariant).
///
/// The shrink resizes the glass capsule with real layout instead of applying
/// a CGAffineTransform to the bar: UIVisualEffectView's backdrop is rendered
/// with its own geometry and ignores ancestor transforms, so a transform
/// scales the bar's content but leaves the glass at full size. Item buttons
/// get a matching content-scale transform (ordinary views honor transforms).
final class ShrinkingTabBar: UIView, ShrinkableBar {
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

    var onSelect: ((Int) -> Void)?
    var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            updateSelection()
        }
    }

    /// Test hook: the glass capsule's current frame within the bar.
    var glassFrameForTesting: CGRect { effectView.frame }
    /// Test hook: the selection lens's untransformed size (transform-immune:
    /// frame would report the stretched bounding box mid-drag).
    var lensBoundsForTesting: CGRect { lens.bounds }
    /// Test hook: the selection lens's current alpha (0 at rest, 1 mid-drag).
    var lensAlphaForTesting: CGFloat { lens.alpha }
    /// Test hook: the tint mask's frame in the tinted row's coordinate space.
    var tintMaskFrameForTesting: CGRect { tintMask.frame }
    /// Test hook: the item buttons' title labels (empty before first layout).
    var itemTitleLabelsForTesting: [UILabel] { itemButtons.compactMap(\.titleLabel) }

    /// Holds every piece of bar content EXCEPT the lens (glass capsule, item
    /// rows) and fills the bar exactly, so it shares the bar's coordinate
    /// space. The lens snapshots this container — never the bar itself — so
    /// it can never draw itself into its own texture.
    private let contentContainer = UIView()
    private let effectView: UIVisualEffectView
    private let lens = MetalLensView()
    private let stack = UIStackView()
    private let tintedStack = UIStackView()
    private let tintMask = UIView()
    private var itemButtons: [UIButton] = []
    private var tintedButtons: [UIButton] = []
    private var progress: CGFloat = 0
    private var glassWidth: NSLayoutConstraint!
    private var glassHeight: NSLayoutConstraint!
    private var isDraggingLens = false

    init(items: [TabItem]) {
        if #available(iOS 26.0, *) {
            effectView = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        }
        super.init(frame: .zero)

        // Shape the glass with corner configuration on iOS 26+: cropping via
        // clipsToBounds + layer.cornerRadius makes UIGlassEffect render a
        // rectangle we then crop, so it never knows its capsule shape and
        // can't draw the refractive rim on the edges. The capsule config
        // tracks bounds automatically; cropping remains the fallback.
        if #available(iOS 26.0, *) {
            effectView.cornerConfiguration = .capsule()
        } else {
            effectView.clipsToBounds = true
            effectView.layer.cornerCurve = .continuous
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)
        contentContainer.addSubview(effectView)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        tintedStack.axis = .horizontal
        tintedStack.distribution = .fillEqually
        tintedStack.translatesAutoresizingMaskIntoConstraints = false
        tintedStack.isUserInteractionEnabled = false

        for (index, item) in items.enumerated() {
            // Base row: permanently gray; the blue "selection" look comes
            // from the masked tinted replica painted on top.
            let button = Self.makeButton(for: item, tint: .secondaryLabel, interactive: true)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedIndex = index
                self?.onSelect?(index)
            }, for: .touchUpInside)
            itemButtons.append(button)
            stack.addArrangedSubview(button)

            let tinted = Self.makeButton(for: item, tint: .systemBlue, interactive: false)
            tintedButtons.append(tinted)
            tintedStack.addArrangedSubview(tinted)
        }

        // Direct bar subview, ABOVE contentContainer — a lens must never be
        // nested inside another effect view's contentView, and it needs
        // everything beneath it (capsule, icons, tint) isolated in one
        // container it can snapshot cleanly, itself excluded. Hidden at
        // rest: the lens only materializes while a drag is in flight.
        lens.alpha = 0
        addSubview(lens)
        contentContainer.addSubview(stack)
        // Tinted replica of the item row, masked so blue shows only where
        // the mask covers — the lens paints icon/label PORTIONS continuously
        // as it slides, like the native tab bar (partially across two items
        // mid-slide). The mask frame is in tintedStack's coordinate space.
        contentContainer.addSubview(tintedStack)
        tintMask.backgroundColor = .black
        tintMask.layer.cornerCurve = .continuous
        tintedStack.mask = tintMask

        // Lens wiring. The container — not the window — is the snapshot
        // source: the native lens does NOT refract what is behind the bar (a
        // window texture put mirrored copies of the row text into the bottom
        // band), and with the container as source, beyond-texture rim
        // samples clamp to the bar's transparent edge pixels and render as
        // clean face wash, matching the native cap. contentContainer fills
        // the bar, so the lens's own coordinates map 1:1 into the texture.
        lens.snapshotSource = contentContainer
        // Capture the one-per-drag snapshot with the tint mask LIFTED
        // (every icon tinted): the mask rides the lens, so everything
        // inside the lens silhouette — the only region the shader's inward
        // bezel displacement ever samples — is tinted live; a capture with
        // the mask frozen at its begin-of-drag position goes stale as the
        // lens moves and the rim would warp the UNCOLORED base icons over a
        // live tinted one.
        lens.prepareForSnapshot = { [weak self] capture in
            guard let self else { return capture() }
            self.tintedStack.mask = nil
            capture()
            self.tintedStack.mask = self.tintMask
        }

        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))

        glassWidth = effectView.widthAnchor.constraint(equalToConstant: 0)
        glassHeight = effectView.heightAnchor.constraint(equalToConstant: 0)
        var constraints: [NSLayoutConstraint] = [
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.centerXAnchor.constraint(equalTo: centerXAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassWidth,
            glassHeight,
        ]
        // Base row and tinted replica share identical geometry — one loop so
        // they can't drift out of pixel alignment.
        for row in [stack, tintedStack] {
            constraints += [
                row.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
                row.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
                row.topAnchor.constraint(equalTo: effectView.topAnchor),
                row.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    private static func makeButton(for item: TabItem, tint: UIColor, interactive: Bool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: item.systemImage)
        config.title = item.title
        config.imagePlacement = .top
        config.imagePadding = 2
        config.baseForegroundColor = tint
        // Reclaim the plain() configuration's default 16pt side insets: they
        // eat 32pt of a slot that is only ~68pt wide at full shrink, which
        // left "Favorites" 36pt for a 48pt word and hyphen-wrapped it onto
        // two lines. The shrink narrows slots via REAL layout while the 0.8
        // content scale is a transform applied afterwards, so the title must
        // fit the shrunk slot at FULL font size — the squeeze is entirely in
        // the insets. Titles are centered and far narrower than a bare slot,
        // so neighbours still don't touch. Vertical insets are untouched
        // (they set the button's height).
        config.contentInsets.leading = 0
        config.contentInsets.trailing = 0
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        config.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = UIFont.preferredFont(forTextStyle: .caption2)
                return updated
            }
        let button = UIButton(configuration: config)
        button.isUserInteractionEnabled = interactive
        return button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyProgress()
    }

    func setProgress(_ newProgress: CGFloat, animated: Bool) {
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

    /// Test hook: drive the lens drag programmatically (x in bar coordinates).
    /// Mirrors handlePan: the first non-ended call begins the drag
    /// (materializes the lens), subsequent ones move it.
    func simulateLensDrag(toX x: CGFloat, ended: Bool) {
        if ended {
            finishLensDrag(atX: x)
        } else if isDraggingLens {
            moveLens(toX: x)
        } else {
            beginLensDrag(atX: x)
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let x = recognizer.location(in: self).x
        switch recognizer.state {
        case .began:
            beginLensDrag(atX: x)
        case .changed:
            moveLens(toX: x)
        case .ended, .cancelled, .failed:
            finishLensDrag(atX: x)
        default:
            break
        }
    }

    private func lensFrame(forIndex index: Int) -> CGRect {
        guard itemButtons.indices.contains(index) else { return .zero }
        // Force the stack to finish its own internal (fillEqually) layout
        // before reading button geometry: UIStackView resizes arranged
        // subviews during its own layoutSubviews, which — inside our
        // ancestor's layoutSubviews — hasn't run yet, so button frames here
        // would otherwise still reflect the previous size.
        stack.layoutIfNeeded()
        // Use the button's untransformed layout geometry: `frame` is the
        // transformed bounding box while the content-scale transform is
        // active, which would double-shrink the lens (slot already scales
        // via real layout). `center`/`bounds` are unaffected by transform.
        let button = itemButtons[index]
        let layoutFrame = CGRect(x: button.center.x - button.bounds.width / 2,
                                 y: button.center.y - button.bounds.height / 2,
                                 width: button.bounds.width,
                                 height: button.bounds.height)
        let slotFrame = convert(layoutFrame, from: stack).insetBy(dx: 2, dy: 6)
        return Self.expandedLensFrame(slotFrame)
    }

    /// The real iOS 26 Liquid Glass lens, compared side by side, is a
    /// blob that bulges past the bar's own top/bottom edge — not a
    /// slot-sized pill. The SDF bezel needs the extra room to read as glass
    /// instead of a tight sticker. The bar doesn't clip the lens (it's a
    /// direct subview of the bar, added above contentContainer, and neither
    /// the bar nor its ancestors set clipsToBounds/masksToBounds), so the
    /// overflow renders untouched. Proportions measured against the native
    /// active-state screenshot: the grabbed bubble is ~1.2x the slot pill's
    /// width and rises a few points past the bar's edges (an earlier 1.5x
    /// was visibly wider than native).
    private static func expandedLensFrame(_ frame: CGRect) -> CGRect {
        frame.insetBy(dx: -frame.width * 0.12, dy: -12)
    }

    /// Materializes the lens at drag start: sized to the slot of the item
    /// nearest the touch, centered under the finger, fading in like the
    /// native lens.
    private func beginLensDrag(atX x: CGFloat) {
        isDraggingLens = true
        // Live for the whole drag: the display link renders every frame's
        // uniforms -> distort -> present cycle from here until the release
        // dissolve finishes (the snapshot itself is captured once, inside
        // setLive(true)).
        lens.setLive(true)
        let strip = stack.frame
        let index = Self.nearestIndex(forX: x - strip.minX,
                                      stripWidth: strip.width,
                                      count: itemButtons.count)
        // Frame setup shares the fade-in's animation block: a rapid re-drag
        // can begin while the previous release's dissolve is still gliding
        // the lens toward its slot, and a direct (non-animated) frame set
        // would snap it out from under that animation. One from-current-state
        // block hands off smoothly instead. The lens starts slightly small
        // and springs to full size — the native-style materialize pop; the
        // tint mask matches the lens from the first frame.
        lens.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.lens.transform = .identity
            self.lens.frame = self.lensFrame(forIndex: index)
            // Capsule shaping lives inside the lens view/shader, which
            // refits itself on bounds changes.
            self.lens.alpha = 1
            self.tintMask.transform = .identity
            self.sizeTintMaskToLens()
        })
        moveLens(toX: x)
    }

    private func moveLens(toX x: CGFloat) {
        let strip = stack.frame
        guard strip.width > 0 else { return }
        // Clamp the lens CENTER to the first/last slot centers — NOT the
        // old "keep the whole lens inside the strip" clamp (strip.minX +
        // lens.bounds.width / 2): with the bubble expanded wider than a
        // slot, that clamp stopped it short of the end items ("the bubble
        // can't go further than a specific point in the leading or
        // trailing") and it could never center on them the way the native
        // bubble does, its edges free to overhang the bar's side. This
        // also matches the release behavior, which glides to the slot
        // center via lensFrame(forIndex:).
        // ...plus a 6pt allowance past the end-slot centers (tuned by eye:
        // 0 read as stopping short, 12 as too much): the finger can push
        // the bubble slightly toward the bar's edge, and the release glide
        // settles it back onto the slot.
        let slot = slotWidth
        let target = min(max(x, strip.minX + slot / 2 - 6),
                         strip.maxX - slot / 2 + 6)
        // Springy inertia: the lens trails the finger on an under-damped
        // spring rather than tracking rigidly. Stretch proportional to how
        // far it visually lags (presentation layer = on-screen position).
        let visualX = lens.layer.presentation()?.position.x ?? lens.center.x
        let lag = min(abs(target - visualX) / 120, 1)
        let stretch = CGAffineTransform(scaleX: 1 + 0.18 * lag,
                                        y: 1 + 0.08 * lag)
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.55, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.lens.center.x = target
            self.lens.transform = stretch
            // The tint mask rides with the lens (in stack coordinates) with
            // the same size and stretch, so the painted blue window matches
            // the glass exactly — covered portions of icons/labels color
            // continuously as the lens slides.
            self.sizeTintMaskToLens()
            self.tintMask.center = CGPoint(x: target - strip.minX,
                                           y: self.stack.bounds.height / 2)
            self.tintMask.transform = stretch
        })
    }

    private func finishLensDrag(atX x: CGFloat) {
        let strip = stack.frame
        let index = Self.nearestIndex(forX: x - strip.minX,
                                      stripWidth: strip.width,
                                      count: itemButtons.count)
        isDraggingLens = false
        if index != selectedIndex {
            selectedIndex = index
        }
        // Glide to the chosen slot while dissolving, like the native lens;
        // the tint mask settles onto the chosen slot (whole item blue).
        let target = lensFrame(forIndex: index)
        UIView.animate(withDuration: 0.25, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.lens.center = CGPoint(x: target.midX, y: target.midY)
            self.lens.transform = .identity
            self.lens.alpha = 0
            self.tintMask.transform = .identity
            self.parkTintMask(at: index)
        }, completion: { [weak self] _ in
            self?.lens.setLive(false)
        })
        onSelect?(index)  // fires for same-index release too, matching tap behavior
    }

    /// Equal-division slot width (fillEqually) — the one strip metric the
    /// drag clamp and slotRect share.
    private var slotWidth: CGFloat {
        stack.bounds.width / CGFloat(max(itemButtons.count, 1))
    }

    /// The item slot rect at `index` in the (tinted) stack's coordinate
    /// space. Deterministic under fillEqually and transform-independent.
    private func slotRect(_ index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * slotWidth, y: 0,
               width: slotWidth, height: stack.bounds.height)
    }

    /// Mid-drag: the tint mask mirrors the lens capsule (size + corner rule;
    /// the caller positions/stretches it).
    private func sizeTintMaskToLens() {
        tintMask.bounds.size = lens.bounds.size
        tintMask.layer.cornerRadius = lens.bounds.height / 2
    }

    /// At rest: the tint mask parks on the slot at `index` (whole item blue).
    private func parkTintMask(at index: Int) {
        tintMask.frame = slotRect(index)
        tintMask.layer.cornerRadius = tintMask.frame.height / 2
    }

    private func applyProgress() {
        let frame = Self.glassFrame(progress: progress, in: bounds.size)
        glassWidth.constant = frame.width
        glassHeight.constant = frame.height
        // Force the resolve now: effectView/stack live inside contentContainer,
        // one hop below self, so a constant change here marks contentContainer
        // (not self) as needing layout again — self's own layoutSubviews (this
        // method) won't get a second invocation to pick up the corrected
        // stack.bounds read below. Resolving eagerly keeps this call the single
        // source of truth within one layout pass.
        contentContainer.layoutIfNeeded()
        if #available(iOS 26.0, *) {
            // Capsule corner configuration tracks bounds automatically.
        } else {
            effectView.layer.cornerRadius = frame.height / 2
        }
        let s = Self.scale(for: progress)
        for button in itemButtons + tintedButtons {
            button.transform = CGAffineTransform(scaleX: s, y: s)
        }
        // The lens is hidden unless dragging; its size is set at drag begin.
        // At rest the tint mask parks on the selected slot, tracking
        // shrink/layout changes.
        if !isDraggingLens {
            parkTintMask(at: selectedIndex)
        }
    }

    private func updateSelection() {
        // Selection visual is purely the mask's position over the tinted
        // replica (base row is static gray). Glide to the new slot.
        guard !isDraggingLens, !bounds.isEmpty else { return }
        UIView.animate(withDuration: 0.35, delay: 0,
                       usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: {
            self.parkTintMask(at: self.selectedIndex)
        })
    }
}
