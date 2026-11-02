package com.example.camera.data

/**
 * The six starter looks plus "Original". A look is a set of colour offsets applied
 * before the user's own adjustments, so filters and sliders compose cleanly.
 */
enum class FilterId(val label: String) {
    ORIGINAL("Original"),
    LARK("Lark"),
    JUNO("Juno"),
    NOIR("Noir"),
    SUNSET("Sunset"),
    DREAM("Dream"),
    VIVID("Vivid")
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
    val lift: Float = 0f,
    val gamma: Float = 1f,
    val tintR: Float = 0f,
    val tintG: Float = 0f,
    val tintB: Float = 0f
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
            lift = 0.04f
        )
        FilterId.JUNO -> Look(
            contrast = 0.16f,
            saturation = 0.30f,
            warmth = -0.05f,
            tintR = -0.010f,
            tintG = 0.005f,
            tintB = 0.030f
        )
        FilterId.NOIR -> Look(
            brightness = -0.03f,
            contrast = 0.30f,
            saturation = -1f,
            gamma = 1.05f
        )
        FilterId.SUNSET -> Look(
            brightness = 0.02f,
            contrast = 0.10f,
            saturation = 0.25f,
            warmth = 0.35f,
            lift = 0.02f,
            tintR = 0.020f,
            tintB = -0.010f
        )
        FilterId.DREAM -> Look(
            brightness = 0.07f,
            contrast = -0.14f,
            saturation = 0.08f,
            warmth = 0.10f,
            lift = 0.10f,
            gamma = 0.96f
        )
        FilterId.VIVID -> Look(
            brightness = -0.01f,
            contrast = 0.24f,
            saturation = 0.55f
        )
    }
}

/**
 * Everything the renderer needs. [filter] picks a [Look]; the rest are the user's
 * own adjustments and the AI toggles.
 */
data class EditParams(
    val filter: FilterId = FilterId.ORIGINAL,
    val exposure: Float = 0f,
    val contrast: Float = 0f,
    val saturation: Float = 0f,
    val warmth: Float = 0f,
    val sharpen: Float = 0f,
    val night: Boolean = false,
    val hdr: Boolean = false,
    val beauty: Boolean = false,
    val portrait: Boolean = false
) {
    val isIdentity: Boolean
        get() = filter == FilterId.ORIGINAL &&
            exposure == 0f &&
            contrast == 0f &&
            saturation == 0f &&
            warmth == 0f &&
            sharpen == 0f &&
            !night &&
            !hdr &&
            !beauty &&
            !portrait

    fun withFilter(id: FilterId): EditParams = copy(filter = id)

    fun resetAdjustments(): EditParams = copy(
        exposure = 0f,
        contrast = 0f,
        saturation = 0f,
        warmth = 0f,
        sharpen = 0f,
        night = false,
        hdr = false,
        beauty = false,
        portrait = false
    )
}
