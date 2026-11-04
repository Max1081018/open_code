package com.example.camera.data

import android.graphics.Bitmap
import android.graphics.Matrix
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * The on-device computational-photography renderer.
 *
 * Everything is deterministic, CPU-only pixel maths: no cloud, no model download,
 * no network permission. The pipeline runs on a downscaled copy for the live
 * preview and on the full-resolution file when saving. Real subject masking for
 * portrait bokeh comes from ML Kit and is passed in as a confidence mask.
 */
object ImagePipeline {

    fun render(
        src: Bitmap,
        params: EditParams,
        maxDim: Int,
        mask: FloatArray? = null,
        maskW: Int = 0,
        maskH: Int = 0
    ): Bitmap {
        val working = scaleTo(src, maxDim)
        val w = working.width
        val h = working.height
        val px = IntArray(w * h)
        working.getPixels(px, 0, w, 0, 0, w, h)
        if (working !== src) working.recycle()

        if (!params.isIdentity) {
            if (params.aiVision) aiVisionPass(px, w, h)
            applyColour(px, params)
            if (params.night) nightPass(px, w, h)
            if (params.hdr) hdrPass(px, w, h)
            if (params.clarity > 0.001f) localContrastPass(px, w, h, params.clarity)
            if (params.denoise > 0.001f) denoisePass(px, w, h, params.denoise)
            if (params.detail) detailPass(px, w, h)
            if (params.sharpen > 0.001f) sharpenPass(px, w, h, params.sharpen)
            if (params.beauty) beautyPass(px, w, h)
            if (params.portrait) portraitPass(px, w, h, params.portraitStrength, mask, maskW, maskH)
            if (params.grain > 0.001f) grainPass(px, w, h, params.grain)
            if (params.vignette > 0.001f) vignettePass(px, w, h, params.vignette)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(px, 0, w, 0, 0, w, h)
        return transform(out, params)
    }

    // ------------------------------------------------------------- colour

    /**
     * Look + user sliders in a single pass. Keeping this to one loop is what makes
     * full-resolution exports feel fast on a mid-range phone.
     */
    private fun applyColour(px: IntArray, p: EditParams) {
        val look = Looks.of(p.filter)
        val t = p.filterIntensity.coerceIn(0f, 1f)

        val brightness = look.brightness * t + p.exposure * 0.55f
        val contrast = (look.contrast * t + p.contrast).coerceIn(-0.85f, 2.2f)
        val saturation = (look.saturation * t + p.saturation).coerceIn(-1f, 2.5f)
        val warmth = (look.warmth * t + p.warmth).coerceIn(-1f, 1f) * 0.07f
        val tint = (look.tint * t + p.tint).coerceIn(-1f, 1f) * 0.07f
        val lift = look.lift * t
        val gamma = (1f + (look.gamma - 1f) * t).coerceIn(0.4f, 2.5f)
        val highlights = (look.highlights * t + p.highlights).coerceIn(-1f, 1f)
        val shadows = (look.shadows * t + p.shadows).coerceIn(-1f, 1f)
        val fade = (look.fade * t + p.fade).coerceIn(0f, 0.6f)
        val tintR = look.tintR * t
        val tintG = look.tintG * t
        val tintB = look.tintB * t
        val gain = 1f + contrast
        val satScale = 1f + saturation

        for (i in px.indices) {
            val c = px[i]
            var r = red(c) / 255f
            var g = green(c) / 255f
            var b = blue(c) / 255f

            r = (r + brightness - 0.5f) * gain + 0.5f
            g = (g + brightness - 0.5f) * gain + 0.5f
            b = (b + brightness - 0.5f) * gain + 0.5f

            if (lift != 0f) {
                r = ColorOps.lift(r, lift)
                g = ColorOps.lift(g, lift)
                b = ColorOps.lift(b, lift)
            }

            val l0 = ColorOps.luma(
                ColorOps.clamp01(r),
                ColorOps.clamp01(g),
                ColorOps.clamp01(b)
            )
            if (highlights != 0f) {
                val mask = l0 * l0
                val amount = highlights * mask * 0.45f
                r -= amount
                g -= amount
                b -= amount
            }
            if (shadows != 0f) {
                val mask = (1f - l0) * (1f - l0)
                val amount = shadows * mask * 0.45f
                r += amount
                g += amount
                b += amount
            }
            if (fade > 0f) {
                r = r * (1f - fade * 0.35f) + fade * 0.20f
                g = g * (1f - fade * 0.35f) + fade * 0.20f
                b = b * (1f - fade * 0.35f) + fade * 0.20f
            }

            if (gamma != 1f) {
                r = ColorOps.gamma(r, gamma)
                g = ColorOps.gamma(g, gamma)
                b = ColorOps.gamma(b, gamma)
            }

            val l = ColorOps.luma(
                ColorOps.clamp01(r),
                ColorOps.clamp01(g),
                ColorOps.clamp01(b)
            )
            r = l + (r - l) * satScale + warmth + tint + tintR
            g = l + (g - l) * satScale - tint * 0.35f + tintG
            b = l + (b - l) * satScale - warmth + tint + tintB

            px[i] = ColorOps.pack(
                ColorOps.shoulder(r, 0.82f),
                ColorOps.shoulder(g, 0.82f),
                ColorOps.shoulder(b, 0.82f)
            )
        }
    }

    // ---------------------------------------------------------- ai vision

    /**
     * Scene-adaptive pass: grey-world white balance, gentle shadow/highlight
     * recovery, vibrance for muted colours and a light detail lift. Amounts stay
     * small because AutoEnhance has already set the main recipe.
     */
    private fun aiVisionPass(px: IntArray, w: Int, h: Int) {
        val step = max(1, px.size / 30_000)
        var sr = 0.0
        var sg = 0.0
        var sb = 0.0
        var n = 0
        var i = 0
        while (i < px.size) {
            val c = px[i]
            sr += red(c)
            sg += green(c)
            sb += blue(c)
            n++
            i += step
        }
        if (n == 0) return
        val mr = (sr / n).toFloat()
        val mg = (sg / n).toFloat()
        val mb = (sb / n).toFloat()
        val target = (mr + mg + mb) / 3f
        val gr = (target / max(1f, mr)).coerceIn(0.90f, 1.10f)
        val gg = (target / max(1f, mg)).coerceIn(0.90f, 1.10f)
        val gb = (target / max(1f, mb)).coerceIn(0.90f, 1.10f)

        for (j in px.indices) {
            val c = px[j]
            var r = red(c) / 255f * gr
            var g = green(c) / 255f * gg
            var b = blue(c) / 255f * gb
            val l = ColorOps.luma(
                ColorOps.clamp01(r),
                ColorOps.clamp01(g),
                ColorOps.clamp01(b)
            )
            val mx = max(r, max(g, b))
            val mn = min(r, min(g, b))
            val sat = if (mx > 0f) (mx - mn) / mx else 0f
            val vibrance = (0.16f * (1f - sat)).coerceIn(0f, 0.16f)
            r = l + (r - l) * (1f + vibrance)
            g = l + (g - l) * (1f + vibrance)
            b = l + (b - l) * (1f + vibrance)
            val shadow = (1f - l) * (1f - l) * 0.10f
            val highlight = l * l * 0.06f
            px[j] = ColorOps.pack(
                ColorOps.shoulder(r + shadow - highlight, 0.84f),
                ColorOps.shoulder(g + shadow - highlight, 0.84f),
                ColorOps.shoulder(b + shadow - highlight, 0.84f)
            )
        }
        localContrastPass(px, w, h, 0.10f)
    }

    // -------------------------------------------------------------- night

    /**
     * Night mode: bilateral edge-aware denoise, chroma cleanup, strong shadow
     * lift and highlight protection, then a detail restore. This is the
     * "clear photo in the dark" pass.
     */
    private fun nightPass(px: IntArray, w: Int, h: Int) {
        denoisePass(px, w, h, 0.72f)
        val radius = max(2, min(w, h) / 90)
        val blurred = boxBlur(px, w, h, radius)
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            var r = ColorOps.lerp(red(c) / 255f, red(b) / 255f, 0.10f)
            var g = ColorOps.lerp(green(c) / 255f, green(b) / 255f, 0.10f)
            var bl = ColorOps.lerp(blue(c) / 255f, blue(b) / 255f, 0.10f)

            r = ColorOps.gamma(r, 0.84f)
            g = ColorOps.gamma(g, 0.84f)
            bl = ColorOps.gamma(bl, 0.84f)

            val l = ColorOps.luma(r, g, bl)
            val detail = l - ColorOps.luma(
                red(b) / 255f,
                green(b) / 255f,
                blue(b) / 255f
            )
            val boost = detail / (1f + abs(detail) * 5f)
            r += boost * 0.55f
            g += boost * 0.55f
            bl += boost * 0.55f

            val sat = 1.08f
            r = l + (r - l) * sat
            g = l + (g - l) * sat
            bl = l + (bl - l) * sat

            px[i] = ColorOps.pack(
                ColorOps.shoulder(r, 0.78f),
                ColorOps.shoulder(g, 0.78f),
                ColorOps.shoulder(bl, 0.78f)
            )
        }
    }

    // ---------------------------------------------------------------- hdr

    /**
     * Multi-scale local tone mapping in linear light: fine texture and broad
     * local contrast are rebuilt with a ratio (anti-halo) transform, shadows
     * lift and highlights roll off with a soft knee.
     */
    private fun hdrPass(px: IntArray, w: Int, h: Int) {
        val fine = boxBlur(px, w, h, max(1, min(w, h) / 420))
        val coarse = boxBlur(px, w, h, max(2, min(w, h) / 45))
        for (i in px.indices) {
            val c = px[i]
            val f = fine[i]
            val k = coarse[i]
            val l = lumaOf(c)
            val cf = linOf(c)
            val ff = linOf(f)
            val kf = linOf(k)
            val gateF = ColorOps.smoothstep(0.001f, 0.05f, abs(l - lumaOf(f)))
            val gateK = ColorOps.smoothstep(0.0005f, 0.03f, abs(l - lumaOf(k)))
            var target = cf + (cf - ff) * 0.55f * gateF
            target += (target - kf) * 0.35f * gateK

            // Shadow lift and highlight knee in linear light.
            val shadow = (1f - l) * (1f - l) * 0.16f
            val highlight = l * l * 0.10f
            target = clampUnit(target + shadow - highlight)

            // Ratio keeps hue; clamp keeps strong edges free of ringing.
            val rel = (target / max(0.002f, cf)).coerceIn(0.35f, 2.6f)
            var r = gammaBack(clampUnit(linCh(c, 0) * rel))
            var g = gammaBack(clampUnit(linCh(c, 1) * rel))
            var b = gammaBack(clampUnit(linCh(c, 2) * rel))

            val ll = ColorOps.luma(r, g, b)
            val sat = 1.10f
            r = ll + (r - ll) * sat
            g = ll + (g - ll) * sat
            b = ll + (b - ll) * sat

            px[i] = ColorOps.pack(
                ColorOps.shoulder(r, 0.80f),
                ColorOps.shoulder(g, 0.80f),
                ColorOps.shoulder(b, 0.80f)
            )
        }
    }

    // ------------------------------------------------------------ clarity

    /**
     * Local contrast: adds mid-frequency structure back on top of the base image
     * in linear light with an anti-halo ratio transform.
     */
    private fun localContrastPass(px: IntArray, w: Int, h: Int, amount: Float) {
        val radius = max(2, min(w, h) / 55)
        val blurred = boxBlur(px, w, h, radius)
        val k = amount.coerceIn(0f, 1f) * 0.60f
        for (i in px.indices) {
            val c = px[i]
            px[i] = detailAdd(c, blurred[i], k + 1f, k)
        }
    }

    // -------------------------------------------------------------- detail

    /**
     * AI Detail: multi-scale micro-contrast in linear light. It adds texture at
     * three radii with a soft gate so the result gains detail without halos.
     */
    private fun detailPass(px: IntArray, w: Int, h: Int) {
        val r1 = max(1, min(w, h) / 900)
        val r2 = max(2, min(w, h) / 240)
        val r3 = max(4, min(w, h) / 80)
        val b1 = boxBlur(px, w, h, r1)
        val b2 = boxBlur(px, w, h, r2)
        val b3 = boxBlur(px, w, h, r3)
        for (i in px.indices) {
            val c = px[i]
            val a1 = detailAdd(c, b1[i], 1.05f, 1f)
            val a2 = detailAdd(c, b2[i], 0.65f, 1f)
            val a3 = detailAdd(c, b3[i], 0.35f, 1f)
            // Average of the three gain-applied variants over the original.
            val cr = (red(a1) + red(a2) + red(a3) + red(c) * 2f) / 5f
            val cg = (green(a1) + green(a2) + green(a3) + green(c) * 2f) / 5f
            val cb = (blue(a1) + blue(a2) + blue(a3) + blue(c) * 2f) / 5f
            px[i] = rgba(cr, cg, cb)
        }
    }

    // ------------------------------------------------------------- denoise

    /**
     * True bilateral denoise: each pixel is a luma-weighted average of its
     * neighbourhood, so flat areas get cleaned while edges and textures keep
     * their structure. Chroma is smoothed wider than luma, which is what keeps
     * night shots both clean and sharp.
     */
    private fun denoisePass(px: IntArray, w: Int, h: Int, amount: Float) {
        val strength = amount.coerceIn(0f, 1f)
        if (strength <= 0f) return
        // Range sigma in gamma-space luma. Stronger settings accept more.
        val sig2 = 2f * (0.045f + 0.11f * strength).let { it * it }
        val radius = if (strength > 0.55f) 2 else 1
        val chromaWeight = strength * 0.55f
        val out = IntArray(px.size)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val i = y * w + x
                val c = px[i]
                val lc = lumaOf(c)
                var wr = 0f
                var wg = 0f
                var wb = 0f
                var wl = 0f
                var cr = 0f
                var cg = 0f
                var cb = 0f
                var cl = 0f
                for (dy in -radius..radius) {
                    val ny = (y + dy).coerceIn(0, h - 1)
                    val row = ny * w
                    for (dx in -radius..radius) {
                        val nx = (x + dx).coerceIn(0, w - 1)
                        val n = px[row + nx]
                        val ln = lumaOf(n)
                        val dl = ln - lc
                        val range = 1f / (1f + (dl * dl) / sig2)
                        // Spatial weight: 1.0 centre, 0.81 ortho, 0.5 diagonal.
                        val spatial = when {
                            dx == 0 && dy == 0 -> 1f
                            dx == 0 || dy == 0 -> 0.81f
                            else -> 0.50f
                        }
                        val wluma = range * spatial
                        val wchroma = spatial
                        val nr = red(n) / 255f
                        val ng = green(n) / 255f
                        val nb = blue(n) / 255f
                        wr += nr * wluma
                        wg += ng * wluma
                        wb += nb * wluma
                        wl += wluma
                        cr += nr * wchroma
                        cg += ng * wchroma
                        cb += nb * wchroma
                        cl += wchroma
                    }
                }
                // Luma goes only where the neighbourhood truly matches.
                val invW = 1f / max(1e-4f, wl)
                var r = ColorOps.lerp(red(c) / 255f, wr * invW, strength)
                var g = ColorOps.lerp(green(c) / 255f, wg * invW, strength)
                var b = ColorOps.lerp(blue(c) / 255f, wb * invW, strength)
                // Chroma cleanup is wider: it averages the whole neighbourhood.
                val invCW = 1f / max(1e-4f, cl)
                r = ColorOps.lerp(r, cr * invCW, chromaWeight)
                g = ColorOps.lerp(g, cg * invCW, chromaWeight)
                b = ColorOps.lerp(b, cb * invCW, chromaWeight)
                out[i] = ColorOps.pack(r, g, b)
            }
        }
        System.arraycopy(out, 0, px, 0, px.size)
    }

    // ------------------------------------------------------------- sharpen

    /**
     * Edge-aware unsharp masking in linear light. The gain is applied to the
     * *ratio* rather than the difference, which suppresses halos around strong
     * edges, and a range gate keeps noise from being amplified.
     */
    private fun sharpenPass(px: IntArray, w: Int, h: Int, amount: Float) {
        val radius = max(1, min(w, h) / 700)
        val blurred = boxBlur(px, w, h, radius)
        val k = amount.coerceIn(0f, 1f) * 1.35f
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            val edge = abs(lumaOf(c) - lumaOf(b))
            val gate = ColorOps.smoothstep(0.004f, 0.030f, edge)
            if (gate <= 0f) continue
            val cl = linOf(c)
            val bl = linOf(b)
            val add = (cl - bl) * k * gate
            val gain = (cl + add) / max(0.002f, cl)
            val gainCl = gain.coerceIn(0.5f, 2.2f)
            px[i] = rgba(
                gammaBack(linCh(c, 0) * gainCl) * 255f,
                gammaBack(linCh(c, 1) * gainCl) * 255f,
                gammaBack(linCh(c, 2) * gainCl) * 255f
            )
        }
    }

    private fun linOf(c: Int): Float {
        val r = linCh(c, 0)
        val g = linCh(c, 1)
        val b = linCh(c, 2)
        return ColorOps.luma(r, g, b)
    }

    private fun linCh(c: Int, channel: Int): Float {
        val v = when (channel) {
            0 -> red(c) / 255f
            1 -> green(c) / 255f
            else -> blue(c) / 255f
        }
        // sRGB -> linear approximation: square (true 2.2, close enough and fast).
        return v * v
    }

    private fun gammaBack(v: Float): Float = sqrt(v.coerceIn(0f, 1f))

    private fun clampUnit(v: Float): Float = v.coerceIn(0f, 1f)

    /** Linear-light luma keep, per-channel ratio transform with clamped gain. */
    private fun detailAdd(
        c: Int,
        base: Int,
        k: Float,
        softK: Float
    ): Int {
        val cf = linOf(c)
        val bf = linOf(base)
        val edge = abs(lumaOf(c) - lumaOf(base))
        val gate = ColorOps.smoothstep(0.002f, 0.05f, edge)
        val add = (cf - bf) * k * gate
        val gain = (cf + add * softK) / max(0.002f, cf)
        val gainCl = gain.coerceIn(0.4f, 2.6f)
        return rgba(
            gammaBack(linCh(c, 0) * gainCl) * 255f,
            gammaBack(linCh(c, 1) * gainCl) * 255f,
            gammaBack(linCh(c, 2) * gainCl) * 255f
        )
    }

    // -------------------------------------------------------------- beauty

    /**
     * Retouch: blend towards a blurred copy only on skin-toned, low-detail areas,
     * which smooths texture while leaving eyes, lips, hair and edges sharp.
     */
    private fun beautyPass(px: IntArray, w: Int, h: Int) {
        val radius = max(2, min(w, h) / 170)
        val blurred = boxBlur(px, w, h, radius)
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            val r0 = red(c) / 255f
            val g0 = green(c) / 255f
            val b0 = blue(c) / 255f
            val skin = skinAmount(r0, g0, b0)
            if (skin <= 0.01f) continue
            val detail = abs(lumaOf(c) - lumaOf(b))
            val keep = ColorOps.smoothstep(0.02f, 0.12f, detail)
            val m = skin * 0.62f * (1f - keep)
            var r = ColorOps.lerp(r0, red(b) / 255f, m) + 0.008f * m
            var g = ColorOps.lerp(g0, green(b) / 255f, m) + 0.008f * m
            var bl = ColorOps.lerp(b0, blue(b) / 255f, m) + 0.008f * m
            val l = ColorOps.luma(r, g, bl)
            val sat = 0.98f
            r = l + (r - l) * sat
            g = l + (g - l) * sat
            bl = l + (bl - l) * sat
            px[i] = ColorOps.pack(r, g, bl)
        }
    }

    private fun skinAmount(r: Float, g: Float, b: Float): Float {
        val y = ColorOps.luma(r, g, b)
        if (y < 0.12f || y > 0.96f) return 0f
        val cb = 128f - 0.168736f * r * 255f - 0.331264f * g * 255f + 0.5f * b * 255f
        val cr = 128f + 0.5f * r * 255f - 0.418688f * g * 255f - 0.081312f * b * 255f
        if (cb < 76f || cb > 130f || cr < 132f || cr > 178f) return 0f
        val cbScore = 1f - abs(cb - 103f) / 27f
        val crScore = 1f - abs(cr - 155f) / 23f
        return (min(cbScore, crScore) * 1.4f).coerceIn(0f, 1f)
    }

    // ------------------------------------------------------------ portrait

    /**
     * Portrait bokeh. Uses the ML Kit confidence mask when it contains a subject,
     * otherwise falls back to an honest radial edge blur. The "out of focus"
     * plate comes from a quarter-scale blur that is bilinearly sampled back up,
     * which reads like a real f/1.4 rendering instead of a smeared overlay.
     */
    private fun portraitPass(
        px: IntArray,
        w: Int,
        h: Int,
        strength: Float,
        mask: FloatArray?,
        maskW: Int,
        maskH: Int
    ) {
        val radius = max(3, min(w, h) / 42)
        val blurred = softBokeh(px, w, h, radius)
        val s = strength.coerceIn(0f, 1f)
        if (mask != null && maskW > 1 && maskH > 1 && maskCoverage(mask) > 0.015f) {
            for (y in 0 until h) {
                for (x in 0 until w) {
                    val i = y * w + x
                    val confidence = sampleMask(mask, maskW, maskH, x, y, w, h)
                    val background = (1f - confidence).coerceIn(0f, 1f)
                    val m = ColorOps.smoothstep(0.15f, 0.85f, background) * s
                    if (m > 0.002f) {
                        val c = px[i]
                        val b = blurred[i]
                        px[i] = rgba(
                            ColorOps.lerp(red(c).toFloat(), red(b).toFloat(), m),
                            ColorOps.lerp(green(c).toFloat(), green(b).toFloat(), m),
                            ColorOps.lerp(blue(c).toFloat(), blue(b).toFloat(), m)
                        )
                    }
                }
            }
            return
        }

        val cx = w / 2f
        val cy = h * 0.44f
        val maxR = sqrt((w * w + h * h).toFloat()) * 0.5f
        var i = 0
        for (y in 0 until h) {
            for (x in 0 until w) {
                val c = px[i]
                val b = blurred[i]
                val d = hypot(x - cx, y - cy) / maxR
                val t = ((d - 0.30f) / 0.28f).coerceIn(0f, 1f)
                val smooth = t * t * (3f - 2f * t)
                val m = smooth * 0.85f * s
                if (m > 0.001f) {
                    px[i] = rgba(
                        ColorOps.lerp(red(c).toFloat(), red(b).toFloat(), m),
                        ColorOps.lerp(green(c).toFloat(), green(b).toFloat(), m),
                        ColorOps.lerp(blue(c).toFloat(), blue(b).toFloat(), m)
                    )
                }
                i++
            }
        }
    }

    /**
     * A smooth bokeh plate: blur at quarter scale (cheap, very flat) then
     * bilinearly sample up. Blends a little of the fine-radius blur so edges do
     * not look banded.
     */
    private fun softBokeh(px: IntArray, w: Int, h: Int, radius: Int): IntArray {
        val fine = boxBlur(px, w, h, max(2, radius / 5))
        val ds = max(2, radius / 6)
        val dw = max(1, w / ds)
        val dh = max(1, h / ds)
        val small = IntArray(dw * dh)
        for (sy in 0 until dh) {
            for (sx in 0 until dw) {
                val x0 = sx * ds
                val y0 = sy * ds
                val x1 = (x0 + ds).coerceAtMost(w)
                val y1 = (y0 + ds).coerceAtMost(h)
                var sr = 0
                var sg = 0
                var sb = 0
                var n = 0
                for (yy in y0 until y1) {
                    val row = yy * w
                    for (xx in x0 until x1) {
                        val c = fine[row + xx]
                        sr += red(c)
                        sg += green(c)
                        sb += blue(c)
                        n++
                    }
                }
                small[sy * dw + sx] = rgba(sr / n.toFloat(), sg / n.toFloat(), sb / n.toFloat())
            }
        }
        val smallBlur = boxBlur(small, dw, dh, max(1, radius / 3))
        val out = IntArray(px.size)
        var i = 0
        for (y in 0 until h) {
            val fy = ((y + 0.5f) / ds).coerceIn(0.5f, dh - 0.5f)
            val y0 = (fy - 0.5f).toInt().coerceIn(0, dh - 1)
            val y1 = (y0 + 1).coerceIn(0, dh - 1)
            val ty = fy - 0.5f - y0
            for (x in 0 until w) {
                val fx = ((x + 0.5f) / ds).coerceIn(0.5f, dw - 0.5f)
                val x0 = (fx - 0.5f).toInt().coerceIn(0, dw - 1)
                val x1 = (x0 + 1).coerceIn(0, dw - 1)
                val tx = fx - 0.5f - x0
                val a = smallBlur[y0 * dw + x0]
                val b = smallBlur[y0 * dw + x1]
                val c = smallBlur[y1 * dw + x0]
                val d = smallBlur[y1 * dw + x1]
                val tr = ColorOps.lerp(
                    ColorOps.lerp(red(a).toFloat(), red(b).toFloat(), tx),
                    ColorOps.lerp(red(c).toFloat(), red(d).toFloat(), tx),
                    ty
                )
                val tg = ColorOps.lerp(
                    ColorOps.lerp(green(a).toFloat(), green(b).toFloat(), tx),
                    ColorOps.lerp(green(c).toFloat(), green(d).toFloat(), tx),
                    ty
                )
                val tb = ColorOps.lerp(
                    ColorOps.lerp(blue(a).toFloat(), blue(b).toFloat(), tx),
                    ColorOps.lerp(blue(c).toFloat(), blue(d).toFloat(), tx),
                    ty
                )
                // Keep 20% of the fine blur so edges stay continuous.
                out[i] = rgba(
                    ColorOps.lerp(tr, red(fine[i]).toFloat(), 0.2f),
                    ColorOps.lerp(tg, green(fine[i]).toFloat(), 0.2f),
                    ColorOps.lerp(tb, blue(fine[i]).toFloat(), 0.2f)
                )
                i++
            }
        }
        return out
    }

    private fun maskCoverage(mask: FloatArray): Float {
        if (mask.isEmpty()) return 0f
        var sum = 0f
        val step = max(1, mask.size / 4_000)
        var i = 0
        var n = 0
        while (i < mask.size) {
            sum += mask[i]
            n++
            i += step
        }
        return if (n == 0) 0f else sum / n
    }

    private fun sampleMask(
        mask: FloatArray,
        mw: Int,
        mh: Int,
        x: Int,
        y: Int,
        w: Int,
        h: Int
    ): Float {
        val fx = (x.toFloat() / max(1, w - 1)) * (mw - 1)
        val fy = (y.toFloat() / max(1, h - 1)) * (mh - 1)
        val x0 = fx.toInt().coerceIn(0, mw - 1)
        val y0 = fy.toInt().coerceIn(0, mh - 1)
        val x1 = (x0 + 1).coerceAtMost(mw - 1)
        val y1 = (y0 + 1).coerceAtMost(mh - 1)
        val tx = fx - x0
        val ty = fy - y0
        val a = ColorOps.lerp(mask[y0 * mw + x0], mask[y0 * mw + x1], tx)
        val b = ColorOps.lerp(mask[y1 * mw + x0], mask[y1 * mw + x1], tx)
        return ColorOps.lerp(a, b, ty)
    }

    // --------------------------------------------------------- film grain

    private fun grainPass(px: IntArray, w: Int, h: Int, amount: Float) {
        val k = amount.coerceIn(0f, 1f) * 0.16f
        var seed = 0x9E3779B9.toInt()
        for (i in px.indices) {
            seed = seed xor (seed shl 13)
            seed = seed xor (seed ushr 17)
            seed = seed xor (seed shl 5)
            val noise = ((seed and 0xFF) / 255f - 0.5f) * k
            val c = px[i]
            val l = lumaOf(c)
            val weight = 0.35f + 0.65f * (1f - abs(l - 0.5f) * 2f)
            px[i] = rgba(
                red(c) + noise * 255f * weight,
                green(c) + noise * 255f * weight,
                blue(c) + noise * 255f * weight
            )
        }
    }

    // ------------------------------------------------------------ vignette

    private fun vignettePass(px: IntArray, w: Int, h: Int, amount: Float) {
        val k = amount.coerceIn(0f, 1f) * 0.55f
        val cx = w / 2f
        val cy = h / 2f
        val maxR = sqrt((w * w + h * h).toFloat()) * 0.5f
        var i = 0
        for (y in 0 until h) {
            for (x in 0 until w) {
                val d = hypot(x - cx, y - cy) / maxR
                val t = ColorOps.smoothstep(0.42f, 1.0f, d)
                val scale = 1f - t * k
                val c = px[i]
                px[i] = rgba(
                    red(c) * scale,
                    green(c) * scale,
                    blue(c) * scale
                )
                i++
            }
        }
    }

    // ------------------------------------------------------------- transform

    private fun transform(src: Bitmap, params: EditParams): Bitmap {
        var current = src
        val rotation = ((params.rotation % 360) + 360) % 360
        val rawAspect = params.cropAspect
        // The crop is taken in the source frame, before rotation. Swapping the
        // ratio for 90/270 keeps the aspect the user picked in the UI.
        val aspect = if (rawAspect != null && rawAspect > 0.01f) {
            if (rotation % 180 != 0) 1f / rawAspect else rawAspect
        } else {
            null
        }
        if (aspect != null) {
            val cw = current.width
            val ch = current.height
            val currentAspect = cw.toFloat() / ch.toFloat()
            val newW: Int
            val newH: Int
            if (currentAspect > aspect) {
                newH = ch
                newW = max(1, (ch * aspect).roundToInt())
            } else {
                newW = cw
                newH = max(1, (cw / aspect).roundToInt())
            }
            if (newW != cw || newH != ch) {
                val x = (cw - newW) / 2
                val y = (ch - newH) / 2
                val cropped = Bitmap.createBitmap(current, x, y, newW, newH)
                if (cropped !== current) {
                    current.recycle()
                    current = cropped
                }
            }
        }

        if (rotation == 0 && !params.flipH) return current

        val matrix = Matrix()
        if (rotation != 0) matrix.postRotate(rotation.toFloat())
        if (params.flipH) matrix.postScale(-1f, 1f)
        val rotated = Bitmap.createBitmap(
            current,
            0,
            0,
            current.width,
            current.height,
            matrix,
            true
        )
        if (rotated !== current) current.recycle()
        return rotated
    }

    // ---------------------------------------------------------------- blur

    /** Separable box blur. Edges clamp, so no dark halo at the frame border. */
    fun boxBlur(src: IntArray, w: Int, h: Int, radius: Int): IntArray {
        if (radius <= 0 || w <= 0 || h <= 0) return src.copyOf()
        val tmp = IntArray(w * h)
        val out = IntArray(w * h)
        val win = radius * 2 + 1

        for (y in 0 until h) {
            val row = y * w
            var sr = 0
            var sg = 0
            var sb = 0
            for (k in -radius..radius) {
                val c = src[row + k.coerceIn(0, w - 1)]
                sr += red(c)
                sg += green(c)
                sb += blue(c)
            }
            for (x in 0 until w) {
                tmp[row + x] =
                    ((sr / win) shl 16) or ((sg / win) shl 8) or (sb / win) or (0xFF shl 24)
                val outC = src[row + (x - radius).coerceIn(0, w - 1)]
                val inC = src[row + (x + radius + 1).coerceIn(0, w - 1)]
                sr += red(inC) - red(outC)
                sg += green(inC) - green(outC)
                sb += blue(inC) - blue(outC)
            }
        }

        for (x in 0 until w) {
            var sr = 0
            var sg = 0
            var sb = 0
            for (k in -radius..radius) {
                val c = tmp[k.coerceIn(0, h - 1) * w + x]
                sr += red(c)
                sg += green(c)
                sb += blue(c)
            }
            for (y in 0 until h) {
                out[y * w + x] =
                    ((sr / win) shl 16) or ((sg / win) shl 8) or (sb / win) or (0xFF shl 24)
                val outC = tmp[(y - radius).coerceIn(0, h - 1) * w + x]
                val inC = tmp[(y + radius + 1).coerceIn(0, h - 1) * w + x]
                sr += red(inC) - red(outC)
                sg += green(inC) - green(outC)
                sb += blue(inC) - blue(outC)
            }
        }
        return out
    }

    // --------------------------------------------------------------- utils

    private fun scaleTo(src: Bitmap, maxDim: Int): Bitmap {
        if (maxDim <= 0) return src
        val longEdge = max(src.width, src.height)
        if (longEdge <= maxDim) return src
        val ratio = maxDim.toFloat() / longEdge.toFloat()
        val w = max(1, (src.width * ratio).roundToInt())
        val h = max(1, (src.height * ratio).roundToInt())
        return Bitmap.createScaledBitmap(src, w, h, true)
    }

    private fun red(c: Int): Int = (c shr 16) and 0xFF

    private fun green(c: Int): Int = (c shr 8) and 0xFF

    private fun blue(c: Int): Int = c and 0xFF

    private fun lumaOf(c: Int): Float =
        ColorOps.luma(red(c) / 255f, green(c) / 255f, blue(c) / 255f)

    private fun rgba(r: Float, g: Float, b: Float): Int =
        (0xFF shl 24) or
            (r.toInt().coerceIn(0, 255) shl 16) or
            (g.toInt().coerceIn(0, 255) shl 8) or
            b.toInt().coerceIn(0, 255)

    private fun rgba(r: Int, g: Int, b: Int): Int =
        (0xFF shl 24) or
            (r.coerceIn(0, 255) shl 16) or
            (g.coerceIn(0, 255) shl 8) or
            b.coerceIn(0, 255)
}
