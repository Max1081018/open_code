package com.example.camera.data

/**
 * A curated set of looks. Every look is a set of colour offsets applied before the
 * user's own adjustments, so filters and sliders compose cleanly.
 */
enum class FilterId(val label: String) {
    ORIGINAL("Original"),
    LARK("Lark"),
    JUNO("Juno"),
    NOIR("Noir"),
    SUNSET("Sunset"),
    DREAM("Dream"),
    VIVID("Vivid"),
    CINEMA("Cinema"),
    FADE("Fade"),
    FOREST("Forest"),
    OCEAN("Ocean"),
    ROSE("Rose"),
    GOLD("Gold"),
    MINT("Mint"),
    NEON("Neon"),
    MONO("Mono"),
    FILM("Film"),
    POP("Pop"),
    SOFT("Soft"),
    CHROME("Chrome"),
    EMBER("Ember"),
    IRIS("Iris"),
    GLACIER("Glacier"),
    PEACH("Peach"),
    CYBER("Cyber"),
    VIOLET("Violet"),
    AMBER("Amber"),
    SLATE("Slate")
}

/**
 * A single look. All values are expressed in normalised 0..1 colour space so they
 * stay independent of bit depth and can be unit tested without Android.
 */
data class Look(
    val brightness: Float = 0f,
    val contrast: Float = 0f,
    val saturation: Float = 0f,
    val warmth: Float = 0f,
    val tint: Float = 0f,
    val lift: Float = 0f,
    val gamma: Float = 1f,
    val tintR: Float = 0f,
    val tintG: Float = 0f,
    val tintB: Float = 0f,
    val fade: Float = 0f,
    val grain: Float = 0f,
    val vignette: Float = 0f,
    val clarity: Float = 0f,
    val highlights: Float = 0f,
    val shadows: Float = 0f
)

object Looks {

    val IDENTITY = Look()

    fun of(id: FilterId): Look = when (id) {
        FilterId.ORIGINAL -> IDENTITY
        FilterId.LARK -> Look(
            brightness = 0.05f,
            contrast = 0.06f,
            saturation = 0.10f,
            warmth = 0.04f,
            lift = 0.04f,
            highlights = 0.04f
        )
        FilterId.JUNO -> Look(
            contrast = 0.16f,
            saturation = 0.30f,
            warmth = -0.05f,
            tintR = -0.010f,
            tintG = 0.005f,
            tintB = 0.030f,
            clarity = 0.10f
        )
        FilterId.NOIR -> Look(
            brightness = -0.03f,
            contrast = 0.30f,
            saturation = -1f,
            gamma = 1.05f,
            grain = 0.16f,
            vignette = 0.28f
        )
        FilterId.SUNSET -> Look(
            brightness = 0.02f,
            contrast = 0.10f,
            saturation = 0.25f,
            warmth = 0.35f,
            lift = 0.02f,
            tintR = 0.020f,
            tintB = -0.010f,
            highlights = 0.08f
        )
        FilterId.DREAM -> Look(
            brightness = 0.07f,
            contrast = -0.14f,
            saturation = 0.08f,
            warmth = 0.10f,
            lift = 0.10f,
            gamma = 0.96f,
            fade = 0.12f
        )
        FilterId.VIVID -> Look(
            brightness = -0.01f,
            contrast = 0.24f,
            saturation = 0.55f,
            clarity = 0.14f
        )
        FilterId.CINEMA -> Look(
            contrast = 0.20f,
            saturation = 0.12f,
            warmth = 0.06f,
            tintB = 0.020f,
            fade = 0.06f,
            vignette = 0.20f,
            clarity = 0.12f
        )
        FilterId.FADE -> Look(
            brightness = 0.03f,
            contrast = -0.10f,
            saturation = -0.12f,
            lift = 0.10f,
            fade = 0.20f,
            grain = 0.14f
        )
        FilterId.FOREST -> Look(
            contrast = 0.12f,
            saturation = 0.18f,
            warmth = -0.10f,
            tintG = 0.018f,
            tintR = -0.012f,
            vignette = 0.14f
        )
        FilterId.OCEAN -> Look(
            contrast = 0.14f,
            saturation = 0.16f,
            warmth = -0.24f,
            tintB = 0.030f,
            tintG = 0.008f,
            clarity = 0.10f
        )
        FilterId.ROSE -> Look(
            brightness = 0.04f,
            contrast = 0.04f,
            saturation = 0.12f,
            warmth = 0.10f,
            tint = 0.14f,
            tintR = 0.020f,
            tintB = 0.012f,
            highlights = 0.04f
        )
        FilterId.GOLD -> Look(
            brightness = 0.03f,
            contrast = 0.12f,
            saturation = 0.20f,
            warmth = 0.30f,
            tintR = 0.024f,
            tintG = 0.010f,
            tintB = -0.014f,
            highlights = 0.10f
        )
        FilterId.MINT -> Look(
            brightness = 0.05f,
            contrast = 0.02f,
            saturation = 0.08f,
            warmth = -0.10f,
            tintG = 0.022f,
            tintB = 0.012f,
            fade = 0.05f
        )
        FilterId.NEON -> Look(
            contrast = 0.26f,
            saturation = 0.65f,
            warmth = -0.12f,
            tint = 0.18f,
            clarity = 0.18f,
            vignette = 0.22f
        )
        FilterId.MONO -> Look(
            contrast = 0.22f,
            saturation = -1f,
            gamma = 1.02f,
            grain = 0.10f
        )
        FilterId.FILM -> Look(
            brightness = 0.02f,
            contrast = 0.10f,
            saturation = -0.04f,
            warmth = 0.12f,
            lift = 0.04f,
            fade = 0.14f,
            grain = 0.28f,
            vignette = 0.18f
        )
        FilterId.POP -> Look(
            contrast = 0.20f,
            saturation = 0.85f,
            clarity = 0.16f,
            highlights = 0.06f
        )
        FilterId.SOFT -> Look(
            brightness = 0.06f,
            contrast = -0.08f,
            saturation = 0.04f,
            warmth = 0.08f,
            lift = 0.07f,
            highlights = 0.08f
        )
        FilterId.CHROME -> Look(
            contrast = 0.28f,
            saturation = -0.10f,
            warmth = -0.06f,
            tintB = 0.018f,
            clarity = 0.24f,
            highlights = 0.10f
        )
        FilterId.EMBER -> Look(
            brightness = 0.02f,
            contrast = 0.18f,
            saturation = 0.35f,
            warmth = 0.30f,
            tintR = 0.015f,
            tintB = -0.012f,
            highlights = 0.06f
        )
        FilterId.IRIS -> Look(
            brightness = 0.05f,
            contrast = -0.06f,
            saturation = 0.22f,
            warmth = -0.08f,
            lift = 0.06f,
            clarity = 0.08f
        )
        FilterId.GLACIER -> Look(
            brightness = 0.03f,
            contrast = 0.10f,
            saturation = 0.14f,
            warmth = -0.20f,
            tintB = 0.02f,
            shadows = 0.06f
        )
        FilterId.PEACH -> Look(
            brightness = 0.06f,
            contrast = -0.04f,
            saturation = 0.18f,
            warmth = 0.16f,
            tint = 0.10f,
            tintR = 0.015f,
            tintG = 0.008f,
            lift = 0.05f,
            highlights = 0.03f
        )
        FilterId.CYBER -> Look(
            brightness = -0.02f,
            contrast = 0.30f,
            saturation = 0.10f,
            warmth = -0.30f,
            tint = 0.30f,
            tintR = -0.020f,
            tintB = 0.030f,
            clarity = 0.20f,
            vignette = 0.25f
        )
        FilterId.VIOLET -> Look(
            brightness = 0.04f,
            contrast = 0.06f,
            saturation = 0.18f,
            warmth = -0.12f,
            tint = 0.22f,
            lift = 0.05f,
            gamma = 0.98f,
            grain = 0.10f
        )
        FilterId.AMBER -> Look(
            brightness = 0.05f,
            contrast = 0.12f,
            saturation = 0.20f,
            warmth = 0.32f,
            tintR = 0.020f,
            tintG = 0.008f,
            highlights = 0.08f
        )
        FilterId.SLATE -> Look(
            brightness = -0.01f,
            contrast = 0.22f,
            saturation = -0.30f,
            warmth = -0.15f,
            tintB = 0.015f,
            gamma = 1.03f,
            clarity = 0.18f,
            vignette = 0.20f
        )
    }
}

/**
 * Everything the renderer needs. [filter] picks a [Look]; the rest are the user's
 * own adjustments and the AI toggles.
 */
data class EditParams(
    val filter: FilterId = FilterId.ORIGINAL,
    val filterIntensity: Float = 1f,
    val exposure: Float = 0f,
    val contrast: Float = 0f,
    val saturation: Float = 0f,
    val warmth: Float = 0f,
    val tint: Float = 0f,
    val highlights: Float = 0f,
    val shadows: Float = 0f,
    val clarity: Float = 0f,
    val sharpen: Float = 0f,
    val denoise: Float = 0f,
    val grain: Float = 0f,
    val vignette: Float = 0f,
    val fade: Float = 0f,
    val night: Boolean = false,
    val hdr: Boolean = false,
    val beauty: Boolean = false,
    val portrait: Boolean = false,
    val portraitStrength: Float = 0.7f,
    val aiVision: Boolean = false,
    val detail: Boolean = false,
    val relight: Boolean = false,
    val relightStrength: Float = 0.6f,
    val rotation: Int = 0,
    val flipH: Boolean = false,
    val cropAspect: Float? = null
) {
    val isIdentity: Boolean
        get() = filter == FilterId.ORIGINAL &&
            exposure == 0f &&
            contrast == 0f &&
            saturation == 0f &&
            warmth == 0f &&
            tint == 0f &&
            highlights == 0f &&
            shadows == 0f &&
            clarity == 0f &&
            sharpen == 0f &&
            denoise == 0f &&
            grain == 0f &&
            vignette == 0f &&
            fade == 0f &&
            !night &&
            !hdr &&
            !beauty &&
            !portrait &&
            !aiVision &&
            !detail &&
            !relight &&
            rotation == 0 &&
            !flipH &&
            cropAspect == null

    fun withFilter(id: FilterId): EditParams = copy(filter = id)

    fun resetAdjustments(): EditParams = copy(
        exposure = 0f,
        contrast = 0f,
        saturation = 0f,
        warmth = 0f,
        tint = 0f,
        highlights = 0f,
        shadows = 0f,
        clarity = 0f,
        sharpen = 0f,
        denoise = 0f,
        grain = 0f,
        vignette = 0f,
        fade = 0f,
        night = false,
        hdr = false,
        beauty = false,
        portrait = false,
        aiVision = false,
        detail = false,
        relight = false
    )
}
