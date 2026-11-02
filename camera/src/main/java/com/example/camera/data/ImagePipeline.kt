package com.example.camera.data

import android.graphics.Bitmap
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * The on-device "AI" enhance + edit renderer.
 *
 * Everything is deterministic, CPU-only pixel maths: no cloud, no model download,
 * no network permission. The pipeline runs on a downscaled copy for the live
 * preview and on the full-resolution file when saving.
 */
object ImagePipeline {

    fun render(src: Bitmap, params: EditParams, maxDim: Int): Bitmap {
        val working = scaleTo(src, maxDim)
        val w = working.width
        val h = working.height
        val px = IntArray(w * h)
        working.getPixels(px, 0, w, 0, 0, w, h)
        if (working !== src) working.recycle()

        if (!params.isIdentity) {
            applyLook(px, params)
            if (params.night) nightPass(px, w, h)
            if (params.hdr) hdrPass(px, w, h)
            if (params.sharpen > 0.001f) sharpenPass(px, w, h, params.sharpen)
            if (params.beauty) beautyPass(px, w, h)
            if (params.portrait) portraitPass(px, w, h)
        }

        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(px, 0, w, 0, 0, w, h)
        return out
    }

    // ---------------------------------------------------------------- look

    private fun applyLook(px: IntArray, p: EditParams) {
        val look = Looks.of(p.filter)
        val bright = look.brightness + p.exposure * 0.55f
        val contrast = (look.contrast + p.contrast).coerceIn(-0.85f, 2.5f)
        val saturation = (look.saturation + p.saturation).coerceIn(-1f, 2.5f)
        val warmth = (look.warmth + p.warmth).coerceIn(-1f, 1f) * 0.07f
        val lift = look.lift
        val gamma = look.gamma.coerceIn(0.4f, 2.5f)
        val gain = 1f + contrast
        val satScale = 1f + saturation

        for (i in px.indices) {
            val c = px[i]
            var r = red(c) / 255f
            var g = green(c) / 255f
            var b = blue(c) / 255f

            r = (r + bright - 0.5f) * gain + 0.5f
            g = (g + bright - 0.5f) * gain + 0.5f
            b = (b + bright - 0.5f) * gain + 0.5f

            if (lift != 0f) {
                r = ColorOps.lift(r, lift)
                g = ColorOps.lift(g, lift)
                b = ColorOps.lift(b, lift)
            }
            if (gamma != 1f) {
                r = ColorOps.gamma(r, gamma)
                g = ColorOps.gamma(g, gamma)
                b = ColorOps.gamma(b, gamma)
            }

            val l = ColorOps.luma(ColorOps.clamp01(r), ColorOps.clamp01(g), ColorOps.clamp01(b))
            r = l + (r - l) * satScale + warmth + look.tintR
            g = l + (g - l) * satScale + look.tintG
            b = l + (b - l) * satScale - warmth + look.tintB

            px[i] = ColorOps.pack(r, g, b)
        }
    }

    // ---------------------------------------------------------------- night

    /**
     * Night mode: gently denoise with a small blur, lift the shadows with a
     * gamma curve and restore a little of the saturation that lifting washes out.
     */
    private fun nightPass(px: IntArray, w: Int, h: Int) {
        val radius = max(2, min(w, h) / 260)
        val blurred = boxBlur(px, w, h, radius)
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            var r = ColorOps.lerp(red(c) / 255f, red(b) / 255f, 0.16f)
            var g = ColorOps.lerp(green(c) / 255f, green(b) / 255f, 0.16f)
            var bl = ColorOps.lerp(blue(c) / 255f, blue(b) / 255f, 0.16f)

            r = ColorOps.gamma(r, 0.86f)
            g = ColorOps.gamma(g, 0.86f)
            bl = ColorOps.gamma(bl, 0.86f)

            val l = ColorOps.luma(r, g, bl)
            val s = 1.06f
            px[i] = ColorOps.pack(l + (r - l) * s, l + (g - l) * s, l + (bl - l) * s)
        }
    }

    // ------------------------------------------------------------------ hdr

    /**
     * HDR: local contrast from a wide-radius blur, a saturation nudge and a soft
     * highlight shoulder so bright areas keep their texture.
     */
    private fun hdrPass(px: IntArray, w: Int, h: Int) {
        val radius = max(2, min(w, h) / 60)
        val blurred = boxBlur(px, w, h, radius)
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            val detail = lumaOf(c) - lumaOf(b)

            var r = red(c) / 255f + detail * 0.75f
            var g = green(c) / 255f + detail * 0.75f
            var bl = blue(c) / 255f + detail * 0.75f

            val l = ColorOps.luma(ColorOps.clamp01(r), ColorOps.clamp01(g), ColorOps.clamp01(bl))
            val s = 1.10f
            r = l + (r - l) * s
            g = l + (g - l) * s
            bl = l + (bl - l) * s

            px[i] = ColorOps.pack(
                ColorOps.shoulder(r),
                ColorOps.shoulder(g),
                ColorOps.shoulder(bl)
            )
        }
    }

    // -------------------------------------------------------------- sharpen

    private fun sharpenPass(px: IntArray, w: Int, h: Int, amount: Float) {
        val radius = max(1, min(w, h) / 500)
        val blurred = boxBlur(px, w, h, radius)
        val k = amount.coerceIn(0f, 1f) * 1.3f
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            val r = red(c) + (red(c) - red(b)) * k
            val g = green(c) + (green(c) - green(b)) * k
            val bl = blue(c) + (blue(c) - blue(b)) * k
            px[i] = rgba(r, g, bl)
        }
    }

    // --------------------------------------------------------------- beauty

    /**
     * Retouch: blend towards a blurred copy only where the local detail is low,
     * which smooths skin texture while leaving eyes, lips and edges sharp.
     */
    private fun beautyPass(px: IntArray, w: Int, h: Int) {
        val radius = max(2, min(w, h) / 180)
        val blurred = boxBlur(px, w, h, radius)
        for (i in px.indices) {
            val c = px[i]
            val b = blurred[i]
            val detail = abs(lumaOf(c) - lumaOf(b))
            val keep = (detail / 0.10f).coerceIn(0f, 1f)
            val m = 0.55f * (1f - keep)

            var r = ColorOps.lerp(red(c) / 255f, red(b) / 255f, m) + 0.012f
            var g = ColorOps.lerp(green(c) / 255f, green(b) / 255f, m) + 0.012f
            var bl = ColorOps.lerp(blue(c) / 255f, blue(b) / 255f, m) + 0.012f

            val l = ColorOps.luma(ColorOps.clamp01(r), ColorOps.clamp01(g), ColorOps.clamp01(bl))
            val s = 0.97f
            r = l + (r - l) * s
            g = l + (g - l) * s
            bl = l + (bl - l) * s

            px[i] = ColorOps.pack(r, g, bl)
        }
    }

    // ------------------------------------------------------------- portrait

    /**
     * Portrait blur. A true subject mask needs an ML model, which this build does
     * not ship, so this is an honest radial falloff: sharp around the centre,
     * softly blurred towards the frame edges.
     */
    private fun portraitPass(px: IntArray, w: Int, h: Int) {
        val radius = max(3, min(w, h) / 55)
        val blurred = boxBlur(px, w, h, radius)
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
                val m = smooth * 0.85f
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
                tmp[row + x] = ((sr / win) shl 16) or ((sg / win) shl 8) or (sb / win) or (0xFF shl 24)
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
                out[y * w + x] = ((sr / win) shl 16) or ((sg / win) shl 8) or (sb / win) or (0xFF shl 24)
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
        (0xFF shl 24) or (r.toInt().coerceIn(0, 255) shl 16) or
            (g.toInt().coerceIn(0, 255) shl 8) or b.toInt().coerceIn(0, 255)
}
