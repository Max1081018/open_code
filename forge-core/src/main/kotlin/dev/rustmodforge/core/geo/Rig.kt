package dev.rustmodforge.core.geo

import kotlinx.serialization.Serializable

/**
 * A skeletal model in Bedrock geometry convention (what GeckoLib and Blockbench write):
 * pixel units, y up, feet at y = 0, cube origins and bone pivots absolute in the rest pose,
 * Euler rotations in degrees applied Z, then Y, then X about each pivot. Java `ModelPart`
 * layers are converted into the same form so one pipeline serves both.
 */
@Serializable
data class FaceUv(val u: Double, val v: Double, val w: Double, val h: Double)

@Serializable
data class RigCube(
    val origin: List<Double>,
    val size: List<Double>,
    val pivot: List<Double>? = null,
    val rotation: List<Double>? = null,
    val inflate: Double = 0.0,
    val mirror: Boolean = false,
    /** Box UV corner, when the cube uses box mapping. */
    val boxUv: List<Double>? = null,
    /** Per-face UVs, keyed north/east/south/west/up/down. */
    val faceUv: Map<String, FaceUv>? = null,
)

@Serializable
data class RigBone(
    val name: String,
    val parent: String? = null,
    val pivot: List<Double> = listOf(0.0, 0.0, 0.0),
    val rotation: List<Double> = listOf(0.0, 0.0, 0.0),
    val mirror: Boolean = false,
    val cubes: List<RigCube> = emptyList(),
)

@Serializable
data class RigModel(
    val identifier: String,
    val textureWidth: Int,
    val textureHeight: Int,
    val bones: List<RigBone>,
    /** Where it came from: `geckolib:<path>` or `java:<class>`. */
    val source: String,
    val warnings: List<String> = emptyList(),
) {
    fun bone(name: String) = bones.firstOrNull { it.name == name }
    fun children(name: String?) = bones.filter { it.parent == name }
    val cubeCount get() = bones.sumOf { it.cubes.size }

    /**
     * Box UVs as six face rectangles (Blockbench's layout for Bedrock box mapping): the side
     * strip is east, north, west, south from the left; up and down sit above north and west.
     */
    companion object {
        fun boxFaces(u: Double, v: Double, size: List<Double>): Map<String, FaceUv> {
            val (w, h, d) = Triple(size[0], size[1], size[2])
            return mapOf(
                "east" to FaceUv(u, v + d, d, h),
                "north" to FaceUv(u + d, v + d, w, h),
                "west" to FaceUv(u + d + w, v + d, d, h),
                "south" to FaceUv(u + d + w + d, v + d, w, h),
                "up" to FaceUv(u + d, v, w, d),
                "down" to FaceUv(u + d + w, v, w, d),
            )
        }
    }
}

@Serializable
enum class LoopMode { ONCE, LOOP, HOLD_ON_LAST_FRAME }

@Serializable
enum class Lerp { LINEAR, CATMULLROM, STEP }

/** One keyframe: three Molang expressions (numbers are expressions too). */
@Serializable
data class Keyframe(val time: Double, val pre: List<String>, val post: List<String>, val lerp: Lerp = Lerp.LINEAR)

@Serializable
data class Channel(val keyframes: List<Keyframe>)

@Serializable
data class BoneTrack(val rotation: Channel? = null, val position: Channel? = null, val scale: Channel? = null)

@Serializable
data class TimedEffect(val time: Double, val effect: String, val locator: String? = null)

@Serializable
data class RigAnimation(
    val name: String,
    val length: Double,
    val loop: LoopMode,
    val bones: Map<String, BoneTrack>,
    val sounds: List<TimedEffect> = emptyList(),
    val particles: List<TimedEffect> = emptyList(),
    val instructions: List<TimedEffect> = emptyList(),
    /** Expressions the evaluator could not compute exactly (variables, unknown queries). */
    val approximations: List<String> = emptyList(),
)

/** A bone's local transform at one instant: degrees, pixels and scale factors. */
data class BonePose(val rotation: DoubleArray, val position: DoubleArray, val scale: DoubleArray)
