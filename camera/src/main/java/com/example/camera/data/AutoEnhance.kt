package com.example.camera.data

import kotlin.math.max

/** Simple statistics used by the auto-enhancer. All values normalised 0..1. */
data class ImageStats(
    val meanLuma: Float,
    val averageDeviation: Float,
    val warmth: Float
)

/**
 * Turns image statistics into a sane starting point for the editor. The rules are
 * deliberately conservative: auto-enhance should look like a good photo, not a
 * filter. Algorithms are pure so they can be tested without a device.
 */
object AutoEnhance {

    fun stats(pixels: IntArray): ImageStats {
        if (pixels.isEmpty()) return ImageStats(0.5f, 0.1f, 0f)
        val step = max(1, pixels.size / 20_000)

        var sumL = 0.0
        var sumDev = 0.0
        var sumR = 0.0
        var sumB = 0.0
        var count = 0
        var i = 0
        while (i < pixels.size) {
            val c = pixels[i]
            val r = ((c shr 16) and 0xFF) / 255f
            val g = ((c shr 8) and 0xFF) / 255f
            val b = (c and 0xFF) / 255f
            val l = ColorOps.luma(r, g, b)
            sumL += l
            sumDev += kotlin.math.abs(l - 0.5f)
            sumR += r
            sumB += b
            count++
            i += step
        }
        if (count == 0) return ImageStats(0.5f, 0.1f, 0f)
        val n = count.toFloat()
        return ImageStats(
            meanLuma = (sumL / n).toFloat(),
            averageDeviation = ((sumDev / n).toFloat() * 2f).coerceIn(0f, 1f),
            warmth = (sumR / n - sumB / n).toFloat()
        )
    }

    fun suggest(stats: ImageStats): EditParams {
        val exposure = ((0.46f - stats.meanLuma) * 1.8f).coerceIn(-0.45f, 0.45f)
        val contrast = ((0.42f - stats.averageDeviation) * 1.1f).coerceIn(-0.10f, 0.35f)
        val saturation = if (stats.averageDeviation < 0.24f) 0.16f else 0.07f
        val warmth = (-stats.warmth * 0.8f).coerceIn(-0.18f, 0.18f)

        return EditParams(
            exposure = round(exposure),
            contrast = round(contrast),
            saturation = round(saturation),
            warmth = round(warmth),
            sharpen = 0.22f,
            hdr = true,
            beauty = true
        )
    }

    private fun round(v: Float): Float = Math.round(v * 100f) / 100f
}
