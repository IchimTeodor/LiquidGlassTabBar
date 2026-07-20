import UIKit
import Metal
import simd

/// A liquid-glass lens rendered by an actual GPU shader instead of
/// hand-crafted Core Animation layers or a Core Image filter graph: a
/// snapshot of the bar content is uploaded as a texture and a fragment
/// shader (see Shaders.metal) computes a capsule signed-distance field,
/// derives a convex height profile and its surface normal from it, and
/// displaces the sample inward per color channel (chromatic aberration)
/// with an in-shader specular rim — the ShaderToy-style reproduction of the
/// system's `CASDFGlassDisplacementEffect`/`CASDFGlassHighlightEffect` pair
/// referenced in Gui Rambo's Liquid Glass talk. ALL styling (shape, bezel,
/// rim, face tint) lives in the shader — there are no UIKit rim/shine
/// sublayers here.
///
/// Pipeline shape ("snapshot once, slide the window"): the WHOLE content
/// container is snapshotted into ONE texture when the drag begins — the
/// bar content is static during a drag; only the lens moves — and each
/// display-link tick just updates uniforms (the sampling window's origin,
/// read from the lens layer's PRESENTATION position so it tracks the
/// in-flight spring with zero lag) and re-encodes a single GPU draw. No
/// per-tick drawHierarchy, no per-tick upload — that per-frame CPU
/// rasterization is what made the refraction visibly trail the lens.
final class MetalLensView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    /// Width (pt) of the refracting band at the silhouette. Widened 12 ->
    /// 16 -> 20 with the fold-free magnifying profile: the rim
    /// magnification factor is 1/(1 - 2*displacementScale/bezel), so the
    /// band width and rim displacement together set how boldly and how
    /// DEEP strokes thicken at the edge (the round-27 zoomed native crops
    /// show the whole covered icon transforming, not just a shallow edge
    /// sliver).
    private static let bezel: CGFloat = 20
    /// Displacement, in points, AT the silhouette (the profile's maximum;
    /// see Shaders.metal stage 2). With bezel 20 this requests slope
    /// k = 2*8/20 = 0.8 -> ~5x stroke magnification at the rim (the
    /// vertical axis boost raises it further, clamped below the fold
    /// limit in the shader) — the round-27 native crops read noticeably
    /// bolder than the earlier 4x. Earlier steep-profile values exceeded
    /// slope 1 entirely and tore content into shredded filaments (the
    /// recurring "green strings" artifact).
    private static let displacementScale: CGFloat = 8
    /// Chromatic aberration spread: per-channel displacement delta. Tuned
    /// 2 -> 6 -> 4 -> 1.5: the native fringe is a THIN, delicate
    /// oil-slick rainbow line tracing warped content at the rim; any
    /// larger delta separates the channels into fat single-channel
    /// (green-cast) patches on high-contrast edges.
    private static let aberration: CGFloat = 1.5
    /// Light direction (normalized-ish; the shader re-normalizes), top-leading.
    private static let lightDir = SIMD2<Float>(-0.6, -0.8)
    /// Uniform white-wash mix so the body reads as a glass slab with its
    /// own substance rather than a pure warp of the backdrop. Re-raised
    /// 0.12 -> 0.04 -> 0.10: the round-12 native screenshot clearly shows
    /// a frosted, milky interior — covered content is visibly veiled, not
    /// raw. (The earlier "perfectly clean center" read came from a
    /// lower-fidelity comparison.)
    private static let faceAlpha: Float = 0.10
    /// Droplet inertia — velocity (px/sec) -> deform target scaling.
    /// Deliberately low so the squish stays genuinely PROPORTIONAL to drag
    /// speed across the whole realistic range: the cap below is only
    /// reached at ~830 px/sec (a real flick); a lazy drag barely deforms.
    /// The previous 0.0008 saturated at ~440 px/sec, so nearly every drag
    /// hit max squish and speed made no visible difference.
    private static let deformVelocityScale: Float = 0.0003
    /// Hard cap on the deform magnitude (unitless stretch factor): the
    /// blob elongates, it never collapses into a sliver or spikes on a
    /// fast fling. Lowered from 0.35 — "too squishy" against the native
    /// reference.
    private static let deformMax: Float = 0.25
    /// UNDERDAMPED spring driving `deform` toward the velocity target:
    /// stiff enough to track a drag with feel, damped lightly enough that
    /// a sudden stop overshoots zero and rings down — the water-drop
    /// wobble. The warp is sign-invariant (it stretches along an AXIS, not
    /// a direction — see Shaders.metal), so each oscillation extremum
    /// reads as one squish. With stiffness 170 (w0 ~= 13.0 rad/s) and
    /// damping 14 (zeta ~= 0.54; critical would be ~26), consecutive
    /// extrema decay by ~exp(-2) ~= 0.14: one clear squish, a second very
    /// faded one, and the third is imperceptible. (The previous damping of
    /// 9 decayed only ~0.32 per extremum — three-plus visible squishes,
    /// too wobbly.)
    private static let deformStiffness: Float = 170
    private static let deformDamping: Float = 14

    weak var snapshotSource: UIView?

    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var sampler: MTLSamplerState?

    private var displayLink: CADisplayLink?

    /// The one-per-drag snapshot of the ENTIRE content container, plus the
    /// scale it was rasterized at (needed to convert the lens's point
    /// coordinates into texture pixels) and the lens region size it was
    /// captured for (a mid-drag shrink resizes the lens slot — the stale
    /// texture would then be sampled at the wrong scale, so it triggers a
    /// re-snapshot; see tick()).
    private var snapshotTexture: MTLTexture?
    private var snapshotScale: CGFloat = 1
    private var snapshotRegionSize: CGSize = .zero

    /// Hook the bar wraps around each snapshot capture so it can put the
    /// content container into the canonical state the shader assumes.
    /// Why: the snapshot is taken ONCE per drag, but the bar's tint mask
    /// rides the lens continuously — a capture with the mask at its
    /// begin-of-drag position goes stale as the lens moves, and the rim
    /// then warps the UNCOLORED base icons while the live icon beneath is
    /// tinted. The bezel displacement only ever samples INWARD (content
    /// inside the lens silhouette), and everything inside the lens is
    /// tinted live by the riding mask — so capturing with the mask lifted
    /// (every icon tinted) makes every rim sample color-correct for the
    /// whole drag; the flat-center fade shows the LIVE (correctly masked)
    /// content anyway.
    /// One around-closure (prepare, run `capture`, restore) rather than a
    /// will/did pair, so the lift/restore pairing can't be half-wired.
    var prepareForSnapshot: ((_ capture: () -> Void) -> Void)?

    /// Droplet-deformation spring state, integrated per display-link tick
    /// (CPU cost is a handful of float ops — the per-tick budget stays
    /// "uniforms only"). `deform` is the shader-space stretch vector: its
    /// direction is the motion axis, its magnitude the stretch amount.
    private var deform = SIMD2<Float>.zero
    private var deformVelocity = SIMD2<Float>.zero
    private var lastOriginPx: SIMD2<Float>?
    private var lastTickTime: CFTimeInterval?
    /// Lens on-screen velocity in px/sec (byproduct of the deform spring's
    /// velocity estimate), reused to extrapolate the sampling origin one
    /// frame ahead — the presentation position we read reflects the frame
    /// currently on glass, but the drawable we encode shows at the NEXT
    /// vsync; without the lookahead the refraction trails by one frame.
    private var originVelocityPx = SIMD2<Float>.zero

    init() {
        // Guards the Swift/MSL struct-mirroring contract (see LensUniforms):
        // any field addition/reordering that changes the layout trips this
        // immediately instead of rendering garbage.
        assert(MemoryLayout<LensUniforms>.stride == 64,
               "LensUniforms layout drifted from Shaders.metal")
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        // Transaction-synchronized presentation: with the default async
        // present, the drawable reaches the screen one frame AFTER the CA
        // transaction that moved the lens layer/tint mask — the refraction
        // visibly trails the glass during a drag. presentsWithTransaction
        // + commit/waitUntilScheduled/present (see render()) lands the new
        // drawable in the SAME frame CA is building.
        metalLayer.presentsWithTransaction = true
        // Tag the drawable as sRGB so Core Animation color-matches it to
        // the display. With colorspace nil CA does NO color management and
        // the sRGB-encoded pixel values get reinterpreted in the display's
        // native (wider, P3) gamut — grays survive that unchanged, but
        // saturated colors like the systemBlue selected tint visibly
        // oversaturate compared to the color-matched UIKit content around
        // the lens. The snapshot upload context is sRGB (DeviceRGB), so
        // this tag makes the pipeline end-to-end consistent.
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)

        // Deliberately NO layer drop shadow: a CALayer draws its shadow
        // directly BEHIND its own content, and this lens's body is
        // intentionally TRANSLUCENT (thin face wash, flat-center fade
        // showing the live bar through) — a shadow showed straight through
        // the body and filled the bubble with an opaque gray slab (round-16
        // regression). The bubble's physical-edge definition comes from the
        // shader's silhouette hairline instead.

        // Metal is unavailable only in exotic environments (no GPU access);
        // on-device and in the simulator it's always present. Guard-fail
        // gracefully instead of crashing: every method below no-ops when
        // the pipeline never got built, so the view just renders nothing
        // (the bar's own alpha/selection wiring is entirely independent of
        // whether this succeeds — see ShrinkingTabBar).
        guard let device else {
            print("[MetalLensView] init: MTLCreateSystemDefaultDevice() returned nil — Metal lens will render nothing.")
            return
        }
        metalLayer.device = device
        commandQueue = device.makeCommandQueue()

        // Bundle.module, NOT makeDefaultLibrary(): SwiftPM compiles
        // Shaders.metal into a default.metallib inside THIS target's resource
        // bundle, while the no-argument makeDefaultLibrary() looks only in the
        // main bundle — which, for a package consumed by an app, holds the
        // app's shaders and not ours. Loading from the module bundle is what
        // makes the lens work for every consumer instead of silently
        // rendering nothing.
        guard let library = try? device.makeDefaultLibrary(bundle: .module),
              let vertexFn = library.makeFunction(name: "lensVertex"),
              let fragmentFn = library.makeFunction(name: "lensFragment") else {
            print("[MetalLensView] init: failed to load lensVertex/lensFragment from the package's Metal library — check Shaders.metal is a target source and the package was rebuilt.")
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // No blending: the pass is a single draw over a transparent clear,
        // and the shader outputs PREMULTIPLIED color — which is exactly the
        // form CAMetalLayer expects to composite. Source-alpha blending
        // here would multiply the (already premultiplied) rgb by alpha a
        // second time and square the alpha, darkening translucent regions.
        descriptor.colorAttachments[0].isBlendingEnabled = false
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        if pipelineState == nil {
            print("[MetalLensView] init: makeRenderPipelineState failed — Metal lens will render nothing.")
        } else {
            print("[MetalLensView] init: Metal pipeline ready (\(device.name)).")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        displayLink?.invalidate()
    }

    /// A running CADisplayLink retains its target, so a live link left
    /// running on a detached lens would leak the view and keep rendering
    /// forever; stopping on window detach is a defensive backstop alongside
    /// the explicit setLive(false) calls.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            setLive(false)
        }
    }

    private var screenScale: CGFloat { window?.screen.scale ?? UIScreen.main.scale }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = screenScale
        metalLayer.contentsScale = scale
        let drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard drawableSize.width > 0, drawableSize.height > 0,
              metalLayer.drawableSize != drawableSize else { return }
        metalLayer.drawableSize = drawableSize
    }

    /// Starts or stops the render loop: the bar calls this with `true` at
    /// drag begin and `false`
    /// once the release dissolve finishes, so the CADisplayLink never
    /// outlives a drag. Going live captures the one-per-drag snapshot;
    /// going dead drops it, so the next drag always re-captures fresh
    /// content (selection tint may have changed between drags).
    func setLive(_ live: Bool) {
        if live {
            guard displayLink == nil else { return }
            // No pipeline (Metal unavailable / shader load failed): nothing
            // can ever render, so skip the snapshot and display link too.
            guard pipelineState != nil else { return }
            captureSnapshot()
            resetDeformState()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate()
            displayLink = nil
            snapshotTexture = nil
            resetDeformState()
        }
    }

    /// Fresh drag, fresh droplet: no leftover wobble from the last drag,
    /// and no velocity spike from a stale lastOriginPx (the lens may have
    /// been re-parked anywhere since).
    private func resetDeformState() {
        deform = .zero
        deformVelocity = .zero
        lastOriginPx = nil
        lastTickTime = nil
        originVelocityPx = .zero
    }

    /// Rasterizes the ENTIRE content container into the cached texture.
    /// Called at drag begin and again only when the snapshot is actually
    /// invalidated (lens region size change mid-drag) — never per tick.
    private func captureSnapshot() {
        guard let device, let source = snapshotSource, !source.bounds.isEmpty else { return }
        snapshotScale = screenScale
        let capture = { self.snapshotTexture = Self.makeSnapshotTexture(of: source, device: device) }
        if let prepareForSnapshot {
            prepareForSnapshot(capture)
        } else {
            capture()
        }
        snapshotRegionSize = bounds.size
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let pipelineState, let commandQueue, let sampler else {
            print("[MetalLensView] tick: Metal pipeline unavailable (device/pipeline/queue/sampler nil) — nothing will render.")
            return
        }
        guard snapshotSource != nil, !bounds.isEmpty else {
            return // not wired up yet / zero-sized — normal during lens setup, not an error
        }
        // The snapshot only goes stale if the bar re-lays out mid-drag
        // (shrink progress change resizes the lens slot). Cheap size check,
        // not a per-tick re-rasterization.
        if snapshotTexture == nil
            || abs(bounds.width - snapshotRegionSize.width) > 0.5
            || abs(bounds.height - snapshotRegionSize.height) > 0.5 {
            captureSnapshot()
        }
        guard let texture = snapshotTexture else {
            print("[MetalLensView] tick: snapshot capture failed — skipping this frame.")
            return
        }
        let origin = updateDeform()
        // One-frame lookahead on the sampling origin: extrapolate along the
        // measured velocity to where the lens will be when this drawable
        // actually hits glass (link.targetTimestamp). One scalar madd per
        // frame — all per-PIXEL work stays in the fragment shader.
        let lookahead = Float(min(max(link.targetTimestamp - CACurrentMediaTime(), 0), 1.0 / 30.0))
        render(texture: texture, pipelineState: pipelineState,
               commandQueue: commandQueue, sampler: sampler,
               originPx: origin + originVelocityPx * lookahead)
    }

    /// The sampling window's origin in texture pixels — the lens's VISUAL
    /// position (presentation layer; see packUniforms for why). Shared by
    /// the uniform packing and the deform velocity estimate so both track
    /// the exact same signal.
    private func currentOriginPx() -> SIMD2<Float> {
        let center = layer.presentation()?.position ?? layer.position
        return SIMD2<Float>(Float((center.x - bounds.width / 2) * snapshotScale),
                            Float((center.y - bounds.height / 2) * snapshotScale))
    }

    /// One spring step of the droplet deformation, driven by the lens's
    /// on-screen velocity: while moving, `deform` leans toward
    /// velocity * deformVelocityScale (stretch along motion); on a sudden
    /// stop the target snaps to zero and the UNDERDAMPED spring overshoots
    /// and oscillates — the settle wobble — before decaying to a clean
    /// capsule at rest. Semi-implicit Euler with an exponential damping
    /// factor, which is unconditionally stable at display-link rates.
    /// Returns this tick's origin so the caller doesn't re-read the
    /// presentation layer.
    private func updateDeform() -> SIMD2<Float> {
        let now = CACurrentMediaTime()
        let origin = currentOriginPx()
        defer {
            lastTickTime = now
            lastOriginPx = origin
        }
        guard let lastTime = lastTickTime, let lastOrigin = lastOriginPx else { return origin }
        // Clamp dt: a hitched frame (app snapshotting, debugger pause)
        // would otherwise integrate one giant step and kick the spring.
        let dt = Float(min(max(now - lastTime, 1.0 / 240.0), 1.0 / 30.0))
        let velocity = (origin - lastOrigin) / dt // px/sec
        originVelocityPx = velocity // reused by tick() for the one-frame lookahead
        var target = velocity * Self.deformVelocityScale
        let targetLen = simd_length(target)
        if targetLen > Self.deformMax {
            target *= Self.deformMax / targetLen
        }
        deformVelocity += (target - deform) * Self.deformStiffness * dt
        deformVelocity *= exp(-Self.deformDamping * dt)
        deform += deformVelocity * dt
        // Hard cap AFTER integration too: the underdamped overshoot may
        // briefly exceed the (already-clamped) target's magnitude.
        let deformLen = simd_length(deform)
        if deformLen > Self.deformMax {
            deform *= Self.deformMax / deformLen
        }
        return origin
    }

    /// Rasterizes the source's full bounds and hands it to Metal as a
    /// texture (the shader slides a lens-sized sampling window across it
    /// via the regionOrigin uniform).
    ///
    /// Deliberately NOT MTKTextureLoader: `MTKTextureLoader.newTexture(cgImage:)`
    /// fails with "Image decoding failed" for CGImages coming out of
    /// `UIGraphicsImageRenderer` — its format sniffing doesn't reliably
    /// recognize every CGImage pixel layout UIKit can hand back (a known
    /// MTKTextureLoader limitation, not a bug in the snapshot itself).
    /// Redrawing into a CGContext we fully control guarantees a canonical
    /// top-down RGBA8 buffer, which a manually created MTLTexture accepts
    /// unconditionally.
    private static func makeSnapshotTexture(of source: UIView, device: MTLDevice) -> MTLTexture? {
        let renderer = UIGraphicsImageRenderer(bounds: source.bounds)
        // layer.render(in:), NOT drawHierarchy(afterScreenUpdates: false):
        // the capture is wrapped in prepareForSnapshot, which lifts the
        // bar's tint mask for the duration of THIS call. drawHierarchy with
        // afterScreenUpdates:false renders the last COMMITTED state and can
        // miss that just-made model change (and :true forces a screen-
        // update pass — hitch/flash risk). layer.render draws the current
        // MODEL tree synchronously, so the lifted mask is always captured.
        // The UIVisualEffectView glass renders as transparent pixels either
        // way (neither API reaches the backdrop), which the shader's alpha
        // carrying already assumes.
        let uiImage = renderer.image { ctx in
            source.layer.render(in: ctx.cgContext)
        }
        guard let cgImage = uiImage.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // NO vertical flip: CGContext coordinates are bottom-left-origin,
        // but a bitmap context's MEMORY layout puts CG's top row at buffer
        // row 0 — drawing the image upright with the identity transform
        // therefore already lands the image's top row in buffer row 0,
        // exactly the top-down order the shader's texture coordinates
        // assume. Adding a flip transform here (the intuitive-seeming move)
        // inverts the buffer and renders the lens content upside down.
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: &pixels, bytesPerRow: bytesPerRow)
        return texture
    }

    private func render(texture: MTLTexture, pipelineState: MTLRenderPipelineState,
                        commandQueue: MTLCommandQueue, sampler: MTLSamplerState,
                        originPx: SIMD2<Float>) {
        guard let drawable = metalLayer.nextDrawable() else {
            print("[MetalLensView] render: nextDrawable() returned nil (drawableSize=\(metalLayer.drawableSize)) — skipping this frame.")
            return
        }
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        encoder.setRenderPipelineState(pipelineState)
        var uniforms = packUniforms(texture: texture, originPx: originPx)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LensUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LensUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        // Transaction-synchronized present (metalLayer.presentsWithTransaction
        // is true): commit, wait until the GPU work is scheduled, THEN
        // present — on the main thread inside the display-link callback,
        // so the drawable joins the same Core Animation transaction that
        // is moving the lens layer and tint mask this frame. The async
        // `commandBuffer.present(drawable)` path put the refraction one
        // frame behind the glass. The wait is a scheduling handoff (not a
        // full GPU completion wait) on a single tiny draw.
        commandBuffer.commit()
        commandBuffer.waitUntilScheduled()
        drawable.present()
    }

    /// Mirrors the MSL `LensUniforms` struct in Shaders.metal field for
    /// field: `SIMD2<Float>` has the same 8-byte alignment in Swift that
    /// `float2` has in MSL, so with identical field order both compilers
    /// lay the struct out identically (including the 4 padding bytes
    /// before `regionOrigin`) — no shared bridging header needed. If
    /// fields are added or reordered, change BOTH structs the same way.
    private struct LensUniforms {
        var size: SIMD2<Float>
        var cornerRadius: Float
        var bezel: Float
        var scale: Float
        var aberration: Float
        var lightDir: SIMD2<Float>
        var faceAlpha: Float
        var regionOrigin: SIMD2<Float>
        var textureSize: SIMD2<Float>
        var deform: SIMD2<Float>
    }

    /// All values in PIXELS (points x snapshotScale) to match the texture.
    ///
    /// regionOrigin tracks the lens's VISUAL position: `originPx` is
    /// derived from the PRESENTATION layer (where the in-flight spring has
    /// actually put the lens this frame) plus the one-frame velocity
    /// lookahead computed in tick(), so the refracted content stays glued
    /// to the glass. It is deliberately NOT clamped into [0, textureSize]:
    /// with the lens frame expanded past the item slot it legitimately
    /// goes out of range at edge items, and the shader's math plus the
    /// clamp-to-edge sampler handle that by stretching edge texels — a
    /// CPU-side clamp would only risk drifting out of sync with the GPU's.
    private func packUniforms(texture: MTLTexture, originPx: SIMD2<Float>) -> LensUniforms {
        let scale = snapshotScale
        return LensUniforms(
            size: SIMD2<Float>(Float(bounds.width * scale), Float(bounds.height * scale)),
            cornerRadius: Float(bounds.height / 2 * scale),
            bezel: Float(Self.bezel * scale),
            scale: Float(Self.displacementScale * scale),
            aberration: Float(Self.aberration * scale),
            lightDir: Self.lightDir,
            faceAlpha: Self.faceAlpha,
            regionOrigin: originPx,
            textureSize: SIMD2<Float>(Float(texture.width), Float(texture.height)),
            deform: deform)
    }
}
