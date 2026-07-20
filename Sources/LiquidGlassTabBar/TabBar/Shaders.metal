#include <metal_stdlib>
using namespace metal;

// Mirrored FIELD FOR FIELD by the Swift `MetalLensView.LensUniforms`
// struct: SIMD2<Float> has the same 8-byte alignment in Swift that float2
// has in MSL, so with identical field order both compilers lay the struct
// out identically (including the 4 padding bytes before regionOrigin; a
// stride assertion on the Swift side guards the contract). If fields are
// added or reordered, change BOTH structs the same way.
struct LensUniforms {
    float2 size;          // lens drawable size in pixels
    float cornerRadius;   // capsule radius in pixels
    float bezel;          // bezel width in pixels
    float scale;          // displacement at the silhouette, pixels
    float aberration;     // per-channel displacement delta
    float2 lightDir;      // normalized, top-leading
    float faceAlpha;      // uniform white-wash mix toward the glass "face"
    float2 regionOrigin;  // lens frame origin within the snapshot, pixels
    float2 textureSize;   // full snapshot texture size in pixels
    float2 deform;        // droplet stretch: direction = motion axis, length = amount (unitless, capped ~0.25)
};

struct VertexOut {
    float4 position [[position]];
    float2 uv; // pixel coordinates within the drawable, origin top-left
};

// Fullscreen triangle (covers the whole viewport with 3 vertices instead of
// 4 for a quad) indexed purely from vertex_id, no vertex buffer needed.
vertex VertexOut lensVertex(uint vertexID [[vertex_id]],
                             constant LensUniforms &uniforms [[buffer(0)]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };
    float2 clip = positions[vertexID];
    VertexOut out;
    out.position = float4(clip, 0.0, 1.0);
    // NDC y=+1 is the top of the viewport in Metal's window-space mapping,
    // so top-left-origin pixel coordinates fall out directly: no extra
    // vertical flip needed once texture sampling also uses topLeft origin.
    float2 ndc01 = clip * 0.5 + 0.5;
    out.uv = float2(ndc01.x, 1.0 - ndc01.y) * uniforms.size;
    return out;
}

// Signed distance to a capsule/rounded-box with half-extents `halfSize`
// (already reduced by `radius`) and corner radius `radius` — the standard
// sdRoundedBox construction (Inigo Quilez): negative inside, zero on the
// silhouette, positive outside. When radius == size.y/2 this degenerates to
// a true capsule (stadium) shape, which is what the lens bodies use.
static float sdRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize;
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

// ===========================================================================
// Refraction stages.
//
// Each stage of the refraction pipeline is a small, single-responsibility
// function so an individual stage can be tuned (or replaced) without
// touching the others; `lensFragment` at the bottom is a thin composition
// of them. Deliberately ONE render pass: the stages are data-dependent in
// sequence (shape -> profile -> normal -> offset -> sample -> light), so
// splitting them across passes would buy no generality and would add
// intermediate textures plus latency to a lens that presents
// transaction-synchronized every frame.
// ===========================================================================

/// Stage 1 — droplet warp (shape only). Warps the SDF's sample space by
/// the spring-driven deform vector. The stretch-along-motion is
/// RENORMALIZED into a perpendicular squash: a naive along-axis stretch
/// (dividing `along` by 1+amt) pushed the silhouette up to 25% past the
/// drawable, whose bounds the capsule already fills exactly — the
/// stretched tips clipped flat mid-drag. Keeping the along axis at 1:1
/// and squashing the perpendicular axis instead yields the same
/// relative-elongation read while the silhouette can only ever SHRINK
/// within the drawable. Everything derived from the SDF (silhouette,
/// displacement, lighting, hairline) inherits the deformation
/// automatically; the sampling-window math is untouched, so the content
/// under the glass stays put while the lens stretches over it.
static float2 dropletWarp(float2 p, float2 deform) {
    float amt = length(deform);
    if (amt <= 0.001) {
        return p;
    }
    float2 dir = deform / amt;
    float along = dot(p, dir);
    float perp  = dot(p, float2(-dir.y, dir.x));
    return dir * along + float2(-dir.y, dir.x) * (perp * (1.0 + 1.5 * amt));
}

/// Stage 2 — bezel displacement profile: a FOLD-FREE MAGNIFYING map.
///
/// The defining property (learned from a zoomed capsule-crop of the
/// native magnifier icon at the rim): the native lens THICKENS strokes
/// near the edge — true magnification — with smooth continuous curves.
/// Magnification of the inward sampling map s -> s + m(s) is
/// 1 / (1 + m'(s)); for content to magnify rather than tear, the slope
/// must satisfy -1 < m' < 0 EVERYWHERE. Every earlier profile violated
/// that: the smoothstep complement's peak slope was 1.5*scale/bezel
/// (~1.4, and ~2.3 after the vertical axis boost), so the map FOLDED —
/// content mirrored and shredded into the thin green filaments the
/// comparison shows, and the folds split the color channels apart.
///
/// This profile is quadratic, m(t) = 0.5*k*bezel*(1-t)^2, whose slope
/// rises linearly from 0 at the flat center (seamless crossing — no kink
/// at the inner boundary) to -k at the silhouette. k is derived from the
/// requested rim displacement (`scale` = m at the silhouette, so
/// k = 2*scale/bezel) and CLAMPED below 1 (0.88 incl. the axis boost),
/// guaranteeing monotonicity: peak rim magnification 1/(1-k) — bold
/// thick strokes like the native — with zero folds, duplicates, or
/// shredding by construction.
static float displacementMagnitude(float inside, float bezel, float scale,
                                   float axisBoost) {
    float t = clamp(inside / max(bezel, 0.0001), 0.0, 1.0);
    float kBase = 2.0 * scale / max(bezel, 0.0001);
    float k = min(kBase * axisBoost, 0.88);
    float edge = 1.0 - t;
    return 0.5 * k * bezel * edge * edge;
}

/// Stage 3 — outward surface normal: central-difference gradient of the
/// SDF (cheap and exact enough at this resolution — no closed-form
/// gradient needed for a rounded box).
static float2 surfaceNormal(float2 p, float2 halfSize, float radius) {
    const float e = 1.0;
    float dxPlus = sdRoundedBox(p + float2(e, 0.0), halfSize, radius);
    float dxMinus = sdRoundedBox(p - float2(e, 0.0), halfSize, radius);
    float dyPlus = sdRoundedBox(p + float2(0.0, e), halfSize, radius);
    float dyMinus = sdRoundedBox(p - float2(0.0, e), halfSize, radius);
    float2 grad = float2(dxPlus - dxMinus, dyPlus - dyMinus) / (2.0 * e);
    return grad / max(length(grad), 0.0001); // points outward
}

/// Stage 4a — anisotropic axis boost: the native bubble is a wide, SHORT
/// dome — steep surface curvature along the vertical axis, gentle along
/// the horizontal — so its top/bottom bands refract more strongly than
/// the side caps: 1x at the sides, ~1.7x at the top/bottom edges,
/// blending smoothly around the corners. Fed INTO the profile's slope
/// clamp (stage 2) rather than multiplied onto the finished offset, so
/// the boost can never push the map past the fold limit.
static float axisBoostFor(float2 normalDir) {
    return 1.0 + 0.7 * normalDir.y * normalDir.y;
}

/// Stage 4b — refraction offset. Pushes the sample INWARD, opposite the
/// outward normal — convex glass bends edge rays toward the lens center,
/// magnifying the covered content at the rim. (An OUTWARD variant was
/// tried and rejected by eye; the doubled-icon regression came from a
/// non-monotone profile, not from the inward direction itself — see
/// stage 2.)
///
/// The inward direction is rotated ~20deg toward the local TANGENT: in
/// the round-27 native crops the distortion visibly SWEEPS along the rim
/// contour (the house's roof line curves around the edge) rather than
/// pointing straight at the center. The tangential component is a SHEAR
/// of the sampling map, so it cannot reintroduce folds — stage 2's radial
/// monotonicity guarantee is untouched.
static float2 refractionOffset(float2 normalDir, float m) {
    const float ct = 0.94; // cos ~20deg
    const float st = 0.34; // sin ~20deg
    float2 inward = -normalDir;
    float2 tangent = float2(-normalDir.y, normalDir.x);
    return (inward * ct + tangent * st) * m;
}

/// Stage 5 — dispersive sampling (chromatic aberration): SIX taps spread
/// across displacement factors (1-spread)..(1+spread) with spectral RGB
/// weights — red at the least-bent end, blue at the most-bent (shorter
/// wavelengths have the higher refractive index), green in the middle.
/// Six taps rather than the classic three: with the magnifying profile's
/// large relative spread, three discrete taps separated into distinct
/// per-channel color bands and the standalone middle band read GREEN on
/// high-contrast strokes; a zoomed native crop shows a smooth
/// blue->cyan->magenta sheen ACROSS the magnified stroke instead, which
/// the denser spectrum reproduces (adjacent taps overlap and blend, so an
/// isolated pure-green band cannot form). Returns PREMULTIPLIED body
/// color and coverage — the snapshot is premultiplied RGBA and the glass
/// renders as transparent pixels in it, so coverage is carried from the
/// two mid-spectrum taps rather than forced.
static float4 sampleDispersed(texture2d<float> snapshot, sampler snapshotSampler,
                              float2 base, float2 offs, float spread,
                              float2 textureSize) {
    constexpr int taps = 6;
    float3 acc = float3(0.0);
    float coverage = 0.0;
    for (int i = 0; i < taps; ++i) {
        float u = float(i) / float(taps - 1);        // 0..1 along the spectrum
        float f = 1.0 + spread * (2.0 * u - 1.0);    // (1-spread)..(1+spread)
        float4 tap = snapshot.sample(snapshotSampler, (base + offs * f) / textureSize);
        float3 w = float3(1.0 - u, 1.0 - abs(2.0 * u - 1.0), u);
        acc += tap.rgb * w;
        if (i == 2 || i == 3) { coverage += 0.5 * tap.a; }
    }
    // Per-channel weight sums for 6 evenly spaced taps: r/b = 3.0, g = 2.4.
    return float4(acc / float3(3.0, 2.4, 3.0), coverage);
}

/// Stage 6 — flat-center fade: where displacement is ~zero the sample is
/// a 1:1 copy of the LIVE content directly beneath the lens — drawing it
/// again composites a (bilinear, subpixel-shifted mid-drag) duplicate
/// over the original, thickening antialiased glyphs into a visibly darker
/// read. The native lens warps in place and never double-draws, so the
/// body's coverage ramps in with displacement instead: the flat center
/// contributes only the faint face wash (live content shows through
/// pristine); by ~4px of displacement the warped copy is at full
/// strength, where it genuinely differs from what is beneath.
static float centerFadeWeight(float m) {
    return clamp(m / 4.0, 0.0, 1.0);
}

fragment float4 lensFragment(VertexOut in [[stage_in]],
                              texture2d<float> snapshot [[texture(0)]],
                              sampler snapshotSampler [[sampler(0)]],
                              constant LensUniforms &uniforms [[buffer(0)]]) {
    float2 size = uniforms.size;
    float2 uv = in.uv;
    float2 halfSize = size * 0.5 - float2(uniforms.cornerRadius);

    // Shape: droplet-warped capsule SDF; outside is discarded.
    float2 p = dropletWarp(uv - size * 0.5, uniforms.deform);
    float d = sdRoundedBox(p, halfSize, uniforms.cornerRadius);
    if (d > 0.0) {
        discard_fragment();
    }
    float inside = -d;

    // Refraction: normal -> axis boost -> fold-free profile -> inward
    // dispersive sampling. The texture is a snapshot captured once per
    // drag; `regionOrigin` slides the lens-sized sampling window across it
    // every frame (the "snapshot once, move the window" pipeline —
    // per-tick work is pure GPU).
    float2 normalDir = surfaceNormal(p, halfSize, uniforms.cornerRadius);
    float m = displacementMagnitude(inside, uniforms.bezel, uniforms.scale,
                                    axisBoostFor(normalDir));
    float2 offs = refractionOffset(normalDir, m);
    float spread = uniforms.aberration / max(uniforms.scale, 0.0001);
    float2 base = uniforms.regionOrigin + uv;
    float4 tap = sampleDispersed(snapshot, snapshotSampler,
                                 base, offs, spread, uniforms.textureSize);
    // SELECTIVE frost: the snapshot's background is transparent (the
    // glass renders as alpha 0 in it), so a warped copy composited as-is
    // lets the LIVE stroke beneath peek through wherever the copy has
    // background — live icon + shifted copy superimposed into a scribbled
    // tangle. A fully opaque milk band fixed that but painted the whole
    // bubble as a solid white donut ("something is broken now"). The live
    // stroke sits exactly at the UNDISPLACED sample position, so one extra
    // tap there tells us precisely where frost must cover: coverage is
    // the max of the displaced copy's ink and the live ink beneath — the
    // copy's ink draws, the live ink underneath is hidden by milk, and
    // everywhere else the band stays translucent glass like the native.
    // (The 0.93 milk matches the light-mode bar over white rows; a
    // dark-mode pass would want it uniform-driven.)
    float4 liveTap = snapshot.sample(snapshotSampler, base / uniforms.textureSize);
    float bodyW = centerFadeWeight(m);
    float cover = max(tap.a, liveTap.a);
    float3 frosted = tap.rgb + float3(0.93) * (cover - tap.a);
    float3 body = frosted * bodyW;
    float a = cover * bodyW;

    // Face: faint uniform white wash composited OVER the body
    // (premultiplied "over" — the face contributes its own coverage, so
    // the glass-slab tint reads even where the snapshot is transparent).
    float3 color = float3(uniforms.faceAlpha) + body * (1.0 - uniforms.faceAlpha);
    float alpha = uniforms.faceAlpha + a * (1.0 - uniforms.faceAlpha);

    // Specular rim: lens-own light, added with its own coverage so the rim
    // shows over transparent backdrop too; the dark counter-rim only
    // darkens content that actually has coverage. Kept subtle to match the
    // reference: the native lens has barely any ring of its own — the
    // warped content itself reads as the edge. The counter-rim weight is
    // faint for the same reason (a heavier one read dirty/muddy).
    float rim = smoothstep(uniforms.bezel, 0.0, inside);
    float2 lightDirN = normalize(uniforms.lightDir);
    float spec = pow(max(dot(normalDir, lightDirN), 0.0), 10.0) * rim;
    float darkSpec = pow(max(dot(normalDir, -lightDirN), 0.0), 10.0) * rim;
    float specA = spec * 0.5;
    color += specA; // white * specA, already premultiplied
    alpha = clamp(alpha + specA, 0.0, 1.0);
    color -= darkSpec * 0.1 * alpha;

    // Silhouette hairline: a thin bright contour along the entire edge —
    // the native bubble has a crisp, defined outline separating it from
    // the bar's own milky white; without it ours read as a borderless fog
    // patch. ~4px wide, fading inward; added with its own coverage like
    // the specular so it shows over the transparent glass backdrop, and it
    // also masks the native-style compression jump at the silhouette.
    float edgeA = (1.0 - smoothstep(0.0, 4.0, inside)) * 0.30;
    color += edgeA;
    alpha = clamp(alpha + edgeA, 0.0, 1.0);

    // Inner contour shade: a soft GRAY band just inside the hairline
    // (~2-9px). A white hairline alone is invisible against the white
    // list rows where the bubble bulges past the bar's top/bottom edge —
    // exactly where nothing else marks the silhouette once the
    // behind-bar content is (correctly) left unrefracted — so the
    // native-style contour needs this darker backing to stay
    // distinguishable on white ("not distinctable on top & bottom").
    // Light-gray ink at partial coverage: darkens white beneath by ~12%
    // at the band's peak, negligible over dark content.
    float shadeA = smoothstep(0.0, 2.0, inside)
                 * (1.0 - smoothstep(2.0, 9.0, inside)) * 0.18;
    color += shadeA * 0.35;
    alpha = clamp(alpha + shadeA, 0.0, 1.0);

    // Premultiplied output (what CAMetalLayer composites; the pipeline has
    // blending disabled — single draw over a transparent clear). Keep the
    // premultiplied invariant rgb <= alpha.
    color = clamp(color, 0.0, alpha);
    return float4(color, alpha);
}
