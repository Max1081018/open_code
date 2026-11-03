package com.example.camera.data

/**
 * Pure colour maths. No Android types here on purpose: every function in this
 * object is covered by plain JVM unit tests.
 */
object ColorOps {

    fun clamp01(v: Float): Float = if (v < 0f) 0f else if (v > 1f) 1f else v

    fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t

    /** Rec. 709 luma, the weighting the eye actually uses. */
    fun luma(r: Float, g: Float, b: Float): Float = 0.2126f * r + 0.7152f * g + 0.0722f * b

    /** Contrast around the 0.5 pivot. 0 leaves the value untouched. */
    fun contrast(v: Float, amount: Float): Float = (v - 0.5f) * (1f + amount) + 0.5f

    /** Lifts shadows towards white while pinning the highlights. */
    fun lift(v: Float, amount: Float): Float {
        if (amount == 0f) return v
        val c = clamp01(v)
        return c + amount * (1f - c)
    }

    fun gamma(v: Float, gamma: Float): Float {
        if (gamma == 1f) return v
        val c = clamp01(v)
        return Math.pow(c.toDouble(), gamma.toDouble()).toFloat()
    }

    /** Scales the distance from the luma axis. -1 makes the pixel grey. */
    fun saturate(r: Float, g: Float, b: Float, amount: Float): FloatArray {
        val l = luma(r, g, b)
        val s = 1f + amount
        return floatArrayOf(l + (r - l) * s, l + (g - l) * s, l + (b - l) * s)
    }

    /**
     * Soft highlight shoulder. Linear up to 0.75, then eases into 1.0 so bright
     * skies keep separation instead of clipping to flat white.
     */
    fun shoulder(v: Float, knee: Float = 0.75f): Float {
        val c = clamp01(v)
        if (c <= knee) return c
        val t = (c - knee) / (1f - knee)
        return knee + (1f - knee) * t * t
    }

    /** Smooth 0..1 ramp between two edges. */
    fun smoothstep(edge0: Float, edge1: Float, x: Float): Float {
        if (edge0 == edge1) return if (x < edge0) 0f else 1f
        val t = clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3f - 2f * t)
    }

    /** S-curve around mid grey, useful for a gentle filmic contrast. */
    fun sCurve(v: Float, amount: Float): Float {
        val c = clamp01(v)
        val k = amount.coerceIn(0f, 1f)
        return lerp(c, c * c * (3f - 2f * c), k)
    }

    fun to255(v: Float): Int = (clamp01(v) * 255f + 0.5f).toInt()

    fun pack(r: Float, g: Float, b: Float): Int =
        (0xFF shl 24) or (to255(r) shl 16) or (to255(g) shl 8) or to255(b)
}
