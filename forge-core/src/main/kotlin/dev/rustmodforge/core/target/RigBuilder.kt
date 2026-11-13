package dev.rustmodforge.core.target

import dev.rustmodforge.core.geo.AnimationSampler
import dev.rustmodforge.core.geo.FaceUv
import dev.rustmodforge.core.geo.Mat4
import dev.rustmodforge.core.geo.Quat
import dev.rustmodforge.core.geo.RigAnimation
import dev.rustmodforge.core.geo.RigBone
import dev.rustmodforge.core.geo.RigCube
import dev.rustmodforge.core.geo.RigModel
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

/** An `item_display` transformation: translation (blocks), left rotation, scale. */
data class DisplayTransform(val translation: DoubleArray, val rotation: Quat, val scale: DoubleArray) {
    fun snbt(step: Int? = null): String {
        fun f(d: Double) = String.format(java.util.Locale.ROOT, "%.4f", d).trimEnd('0').trimEnd('.').let { if (it == "-0") "0" else it } + "f"
        val t = translation.joinToString(",") { f(it) }
        val r = listOf(rotation.x, rotation.y, rotation.z, rotation.w).joinToString(",") { f(it) }
        val s = scale.joinToString(",") { f(it) }
        val interp = step?.let { "start_interpolation:0,interpolation_duration:$it," } ?: ""
        return "{${interp}transformation:{translation:[$t],left_rotation:[$r],scale:[$s],right_rotation:[0f,0f,0f,1f]}}"
    }
}

/**
 * Turns a skeletal model into per-bone block models and poses. Each bone with cubes becomes an
 * item model whose geometry sits around the bone's pivot (scaled by [boneScale] when it would
 * exceed the -16..32 model bounds), and each pose becomes a display transformation that puts
 * that geometry where the bone is: (1/16)·F·M_bone·T(pivot)·S(16·k), F turning the model's
 * front (-z) to the entity's facing (+z).
 */
class RigBuilder(val model: RigModel) {
    private val facing = Mat4.rotY(180.0)
    private val facingQ = Quat.axis(0.0, 1.0, 0.0, 180.0)
    val approximations = ArrayList<String>()

    val drawnBones: List<RigBone> = model.bones.filter { it.cubes.isNotEmpty() }

    /** Geometry downscale per bone so every element fits in block-model bounds. */
    val boneScale: Map<String, Double> = drawnBones.associate { b ->
        var maxAbs = 0.0
        for (c in b.cubes) for (axis in 0..2) {
            val lo = c.origin[axis] - c.inflate - b.pivot[axis]
            val hi = c.origin[axis] + c.size[axis] + c.inflate - b.pivot[axis]
            maxAbs = max(maxAbs, max(abs(lo), abs(hi)))
        }
        b.name to max(1.0, ceil(maxAbs / 24.0 * 4) / 4)
    }

    /** The block model JSON (as a mutable tree) of one bone. */
    fun boneModel(bone: RigBone, texture: String, inflateExtra: Double = 0.0): MutableMap<String, Any?> {
        val k = boneScale.getValue(bone.name)
        val elements = ArrayList<Any?>()
        for (c in bone.cubes) elements += element(c, bone, k, inflateExtra)
        return linkedMapOf("textures" to linkedMapOf("0" to texture, "particle" to texture), "elements" to elements)
    }

    private fun element(c: RigCube, bone: RigBone, k: Double, extra: Double): MutableMap<String, Any?> {
        val inf = c.inflate + extra
        val from = DoubleArray(3) { 8 + (c.origin[it] - inf - bone.pivot[it]) / k }
        val to = DoubleArray(3) { 8 + (c.origin[it] + c.size[it] + inf - bone.pivot[it]) / k }
        val faces = c.faceUv ?: RigModel.boxFaces(c.boxUv?.getOrNull(0) ?: 0.0, c.boxUv?.getOrNull(1) ?: 0.0, c.size)
        val mirror = c.mirror || bone.mirror
        val faceJson = LinkedHashMap<String, Any?>()
        for (dir in listOf("north", "east", "south", "west", "up", "down")) {
            val source = if (mirror && dir == "east") faces["west"] else if (mirror && dir == "west") faces["east"] else faces[dir]
            val f = source ?: continue
            if (f.w == 0.0 && f.h == 0.0) continue
            faceJson[dir] = linkedMapOf("uv" to uv(f, mirror, dir == "down"), "texture" to "#0")
        }
        val el = linkedMapOf<String, Any?>("from" to from.toList(), "to" to to.toList(), "faces" to faceJson)
        c.rotation?.let { rot ->
            val axis = (0..2).maxByOrNull { abs(rot[it]) }!!
            val angle = rot[axis]
            if (abs(angle) > 1e-6) {
                val allowed = listOf(-45.0, -22.5, 0.0, 22.5, 45.0)
                val snapped = allowed.minByOrNull { abs(it - angle) }!!
                if (abs(snapped - angle) > 1.0 || (0..2).any { it != axis && abs(rot[it]) > 1e-6 }) {
                    approximations += "cube rotation ${rot.joinToString()} in bone ${bone.name} drawn as $snapped° about ${"xyz"[axis]} (block models allow one axis in 22.5° steps)"
                }
                if (snapped != 0.0) {
                    val pivot = c.pivot ?: bone.pivot
                    el["rotation"] = linkedMapOf("angle" to snapped, "axis" to "xyz"[axis].toString(),
                        "origin" to (0..2).map { 8 + (pivot[it] - bone.pivot[it]) / k })
                }
            }
        }
        return el
    }

    /** Block-model UVs are 0..16 over the texture whatever its size. */
    private fun uv(f: FaceUv, mirror: Boolean, flipV: Boolean): List<Double> {
        val su = 16.0 / model.textureWidth; val sv = 16.0 / model.textureHeight
        var u1 = f.u * su; var u2 = (f.u + f.w) * su
        var v1 = f.v * sv; var v2 = (f.v + f.h) * sv
        if (mirror) { val t = u1; u1 = u2; u2 = t }
        if (flipV) { val t = v1; v1 = v2; v2 = t }
        return listOf(u1, v1, u2, v2).map { Math.round(it * 1000) / 1000.0 }
    }

    /** Every drawn bone's display transformation for [animation] at [time] seconds (rest pose when null). */
    fun pose(animation: RigAnimation?, time: Double, sampler: AnimationSampler? = animation?.let { AnimationSampler(it) }): Map<String, DisplayTransform> {
        val world = HashMap<String, Mat4>()
        val rot = HashMap<String, Quat>()
        val scale = HashMap<String, DoubleArray>()
        fun resolve(b: RigBone) {
            if (b.name in world) return
            val parent = b.parent?.let { model.bone(it) }
            if (parent != null) resolve(parent)
            val p = sampler?.pose(b.name, time)
            val r = DoubleArray(3) { b.rotation[it] + (p?.rotation?.get(it) ?: 0.0) }
            val pos = p?.position ?: DoubleArray(3)
            val s = p?.scale ?: doubleArrayOf(1.0, 1.0, 1.0)
            val local = Mat4.translate(b.pivot[0] + pos[0], b.pivot[1] + pos[1], b.pivot[2] + pos[2]) * Mat4.rotZYX(r) *
                Mat4.scale(s[0], s[1], s[2]) * Mat4.translate(-b.pivot[0], -b.pivot[1], -b.pivot[2])
            world[b.name] = (parent?.let { world.getValue(it.name) } ?: Mat4()) * local
            rot[b.name] = ((parent?.let { rot.getValue(it.name) } ?: Quat.IDENTITY) * Quat.zyx(r)).normalized()
            val ps = parent?.let { scale.getValue(it.name) } ?: doubleArrayOf(1.0, 1.0, 1.0)
            scale[b.name] = DoubleArray(3) { ps[it] * s[it] }
        }
        model.bones.forEach { resolve(it) }
        return drawnBones.associate { b ->
            val k = boneScale.getValue(b.name)
            val pivotWorld = (facing * world.getValue(b.name)).apply(b.pivot.toDoubleArray())
            b.name to DisplayTransform(
                DoubleArray(3) { pivotWorld[it] / 16.0 },
                (facingQ * rot.getValue(b.name)).normalized(),
                DoubleArray(3) { scale.getValue(b.name)[it] * k },
            )
        }
    }
}
