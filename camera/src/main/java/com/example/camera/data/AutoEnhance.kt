package com.example.camera.data

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Simple statistics used by the auto-enhancer. All values normalised 0..1. */
data class ImageStats(
    val meanLuma: Float,
    val averageDeviation: Float,
    val warmth: Float,
    val saturation: Float = 0f,
    val highlightClip: Float = 0f,
    val shadowClip: Float = 0f,
    val contrast: Float = 0f
)

/** The scene bucket the enhancer uses to pick a recipe. */
enum class Scene(val label: String) {
    GENERAL("Everyday"),
    NIGHT("Night"),
    LOW_LIGHT("Low light"),
    PORTRAIT("Portrait"),
    LANDSCAPE("Landscape"),
    FOOD("Food"),
    TEXT("Document"),
    SUNSET("Golden hour"),
    BACKLIT("Backlit")
}

/**
 * Turns image statistics into a sane starting point for the editor. The rules are
 * deliberately conservative: auto-enhance should look like a good photo, not a
 * filter. Algorithms are pure so they can be tested without a device.
 */
object AutoEnhance {

    fun stats(pixels: IntArray): ImageStats {
        if (pixels.isEmpty()) return ImageStats(0.5f, 0.1f, 0f)
        val step = max(1, pixels.size / 40_000)

        var sumL = 0.0
        var sumDev = 0.0
        var sumR = 0.0
        var sumB = 0.0
        var sumSat = 0.0
        var sumContrast = 0.0
        var highlights = 0
        var shadows = 0
        var count = 0
        var i = 0
        while (i < pixels.size) {
            val c = pixels[i]
            val r = ((c shr 16) and 0xFF) / 255f
            val g = ((c shr 8) and 0xFF) / 255f
            val b = (c and 0xFF) / 255f
            val l = ColorOps.luma(r, g, b)
            val mx = max(r, max(g, b))
            val mn = min(r, min(g, b))
            sumL += l
            sumDev += abs(l - 0.5f)
            sumR += r
            sumB += b
            sumSat += if (mx > 0f) (mx - mn) / mx else 0f
            sumContrast += mx - mn
            if (l > 0.94f) highlights++
            if (l < 0.06f) shadows++
            count++
            i += step
        }
        if (count == 0) return ImageStats(0.5f, 0.1f, 0f)
        val n = count.toFloat()
        return ImageStats(
            meanLuma = (sumL / n).toFloat(),
            averageDeviation = ((sumDev / n).toFloat() * 2f).coerceIn(0f, 1f),
            warmth = (sumR / n - sumB / n).toFloat(),
            saturation = (sumSat / n).toFloat().coerceIn(0f, 1f),
            highlightClip = (highlights / n).coerceIn(0f, 1f),
            shadowClip = (shadows / n).coerceIn(0f, 1f),
            contrast = (sumContrast / n).toFloat().coerceIn(0f, 1f)
        )
    }

    /**
     * Picks a scene from ML Kit labels when available, and from the histogram when
     * the labels are generic or missing. Labels are matched case-insensitively.
     */
    fun classify(stats: ImageStats, labels: List<String> = emptyList()): Scene {
        val text = labels.joinToString(" ").lowercase()
        fun has(vararg words: String): Boolean = words.any { text.contains(it) }

        if (has("food", "dish", "meal", "pizza", "burger", "cake", "dessert", "coffee", "drink")) {
            return Scene.FOOD
        }
        if (has("document", "text", "paper", "receipt", "book", "whiteboard")) {
            return Scene.TEXT
        }
        if (has("night", "darkness", "moon", "fireworks", "city light")) {
            return Scene.NIGHT
        }
        if (has("person", "face", "selfie", "portrait", "people", "human")) {
            return Scene.PORTRAIT
        }
        if (has("sunset", "sunrise", "dusk", "golden hour")) {
            return Scene.SUNSET
        }
        if (has("sky", "mountain", "beach", "landscape", "nature", "tree", "forest", "sea", "lake", "flower")) {
            return Scene.LANDSCAPE
        }
        if (has("backlight", "silhouette", "window")) {
            return Scene.BACKLIT
        }

        return when {
            stats.meanLuma < 0.14f -> Scene.NIGHT
            stats.meanLuma < 0.30f -> Scene.LOW_LIGHT
            stats.highlightClip > 0.08f && stats.shadowClip > 0.08f -> Scene.BACKLIT
            stats.saturation > 0.42f && stats.averageDeviation < 0.35f -> Scene.FOOD
            stats.averageDeviation > 0.58f -> Scene.LANDSCAPE
            else -> Scene.GENERAL
        }
    }

    fun suggest(stats: ImageStats, scene: Scene = Scene.GENERAL): EditParams {
        val dark = scene == Scene.NIGHT || scene == Scene.LOW_LIGHT || scene == Scene.BACKLIT
        val portrait = scene == Scene.PORTRAIT
        val landscape = scene == Scene.LANDSCAPE
        val food = scene == Scene.FOOD

        val exposure = ((0.46f - stats.meanLuma) * 1.9f).coerceIn(-0.5f, 0.62f)
        val contrast = when {
            portrait -> ((0.40f - stats.averageDeviation) * 0.7f).coerceIn(-0.08f, 0.18f)
            landscape -> ((0.44f - stats.averageDeviation) * 1.2f).coerceIn(-0.10f, 0.30f)
            else -> ((0.42f - stats.averageDeviation) * 1.1f).coerceIn(-0.10f, 0.35f)
        }
        val saturation = when {
            portrait -> 0.04f
            food -> 0.24f
            landscape -> 0.18f
            dark -> 0.12f
            else -> if (stats.averageDeviation < 0.24f) 0.16f else 0.08f
        }
        val warmth = (-stats.warmth * 0.8f).coerceIn(-0.18f, 0.18f)
        val shadows = when {
            scene == Scene.NIGHT -> 0.32f
            scene == Scene.BACKLIT -> 0.24f
            dark -> 0.18f
            else -> (stats.shadowClip * 0.9f).coerceIn(0f, 0.18f)
        }
        val highlights = when {
            scene == Scene.BACKLIT -> -0.22f
            stats.highlightClip > 0.06f -> -0.16f
            else -> 0f
        }
        val clarity = when {
            landscape -> 0.26f
            food -> 0.20f
            portrait -> 0.08f
            else -> 0.15f
        }
        val denoise = when {
            scene == Scene.NIGHT -> 0.52f
            scene == Scene.LOW_LIGHT -> 0.36f
            else -> 0.08f
        }

        return EditParams(
            exposure = round(exposure),
            contrast = round(contrast),
            saturation = round(saturation),
            warmth = round(warmth),
            highlights = round(highlights),
            shadows = round(shadows),
            clarity = round(clarity),
            denoise = round(denoise),
            sharpen = 0.32f,
            hdr = true,
            beauty = true,
            night = scene == Scene.NIGHT,
            detail = landscape || food,
            aiVision = true
        )
    }

    private fun round(v: Float): Float = Math.round(v * 100f) / 100f
}
