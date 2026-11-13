package dev.rustmodforge.core.geo

import dev.rustmodforge.core.analysis.MetadataReader
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull

/** Reads Bedrock/GeckoLib `.geo.json` geometry and `.animation.json` animations. */
object GeoParser {
    private fun JsonElement?.num(): Double? = (this as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() }
    private fun JsonElement?.vec(default: List<Double>? = null): List<Double>? =
        (this as? JsonArray)?.map { it.num() ?: 0.0 }?.takeIf { it.size == 3 } ?: default

    fun parseGeometry(text: String, source: String): List<RigModel> {
        val root = MetadataReader.lenientJson.parseToJsonElement(text) as? JsonObject ?: return emptyList()
        val out = ArrayList<RigModel>()
        (root["minecraft:geometry"] as? JsonArray)?.forEach { g ->
            val o = g as? JsonObject ?: return@forEach
            val d = o["description"] as? JsonObject
            out += model(d?.get("identifier")?.let { (it as JsonPrimitive).content } ?: "geometry.unknown",
                d?.get("texture_width").num()?.toInt() ?: 64, d?.get("texture_height").num()?.toInt() ?: 64,
                o["bones"] as? JsonArray, source)
        }
        // Legacy 1.8.0: "geometry.name": { texturewidth, textureheight, bones }
        for ((k, v) in root) {
            if (!k.startsWith("geometry.") || v !is JsonObject) continue
            out += model(k.substringBefore(':'), v["texturewidth"].num()?.toInt() ?: 64, v["textureheight"].num()?.toInt() ?: 64,
                v["bones"] as? JsonArray, source)
        }
        return out
    }

    private fun model(id: String, tw: Int, th: Int, bones: JsonArray?, source: String): RigModel {
        val warnings = ArrayList<String>()
        val list = bones?.mapNotNull { b ->
            val o = b as? JsonObject ?: return@mapNotNull null
            val name = (o["name"] as? JsonPrimitive)?.content ?: return@mapNotNull null
            val cubes = (o["cubes"] as? JsonArray)?.mapNotNull { c -> cube(c as? JsonObject, name, warnings) } ?: emptyList()
            if (o["poly_mesh"] != null) warnings += "bone $name has a poly_mesh, which has no block-model equivalent; it is left out"
            if (o["texture_meshes"] != null) warnings += "bone $name has texture_meshes; left out"
            RigBone(
                name = name, parent = (o["parent"] as? JsonPrimitive)?.contentOrNull,
                pivot = o["pivot"].vec(listOf(0.0, 0.0, 0.0))!!, rotation = (o["rotation"] ?: o["bind_pose_rotation"]).vec(listOf(0.0, 0.0, 0.0))!!,
                mirror = (o["mirror"] as? JsonPrimitive)?.booleanOrNull ?: false, cubes = cubes,
            )
        } ?: emptyList()
        return RigModel(id, tw, th, list, "geckolib:$source", warnings)
    }

    private fun cube(o: JsonObject?, bone: String, warnings: MutableList<String>): RigCube? {
        o ?: return null
        val origin = o["origin"].vec() ?: return null
        val size = o["size"].vec() ?: return null
        val uv = o["uv"]
        var box: List<Double>? = null
        var faces: Map<String, FaceUv>? = null
        when (uv) {
            is JsonArray -> box = uv.map { it.num() ?: 0.0 }.take(2)
            is JsonObject -> faces = uv.mapNotNull { (face, f) ->
                val fo = f as? JsonObject ?: return@mapNotNull null
                val p = (fo["uv"] as? JsonArray)?.map { it.num() ?: 0.0 } ?: return@mapNotNull null
                val s = (fo["uv_size"] as? JsonArray)?.map { it.num() ?: 0.0 } ?: listOf(0.0, 0.0)
                face to FaceUv(p[0], p[1], s[0], s[1])
            }.toMap()
            null -> box = listOf(0.0, 0.0)
            else -> warnings += "a cube of $bone has an unreadable uv"
        }
        return RigCube(
            origin = origin, size = size, pivot = o["pivot"].vec(), rotation = o["rotation"].vec(),
            inflate = o["inflate"].num() ?: 0.0, mirror = (o["mirror"] as? JsonPrimitive)?.booleanOrNull ?: false,
            boxUv = box, faceUv = faces,
        )
    }

    fun parseAnimations(text: String): List<RigAnimation> {
        val root = MetadataReader.lenientJson.parseToJsonElement(text) as? JsonObject ?: return emptyList()
        val anims = root["animations"] as? JsonObject ?: return emptyList()
        return anims.mapNotNull { (name, a) -> (a as? JsonObject)?.let { animation(name, it) } }
    }

    private fun animation(name: String, o: JsonObject): RigAnimation {
        val loop = when (val l = o["loop"]) {
            is JsonPrimitive -> when {
                l.booleanOrNull == true -> LoopMode.LOOP
                l.contentOrNull == "hold_on_last_frame" -> LoopMode.HOLD_ON_LAST_FRAME
                else -> LoopMode.ONCE
            }
            else -> LoopMode.ONCE
        }
        val approximations = LinkedHashSet<String>()
        val bones = LinkedHashMap<String, BoneTrack>()
        (o["bones"] as? JsonObject)?.forEach { (bone, t) ->
            val to = t as? JsonObject ?: return@forEach
            bones[bone] = BoneTrack(
                rotation = channel(to["rotation"], 0.0, approximations),
                position = channel(to["position"], 0.0, approximations),
                scale = channel(to["scale"], 1.0, approximations),
            )
        }
        var length = o["animation_length"].num() ?: 0.0
        if (length <= 0.0) {
            length = bones.values.flatMap { listOfNotNull(it.rotation, it.position, it.scale) }.flatMap { it.keyframes }.maxOfOrNull { it.time } ?: 0.0
        }
        fun effects(key: String, field: String): List<TimedEffect> {
            val e = o[key] as? JsonObject ?: return emptyList()
            return e.flatMap { (time, v) ->
                val list = if (v is JsonArray) v.toList() else listOf(v)
                list.mapNotNull { item ->
                    val io = item as? JsonObject
                    val effect = (io?.get(field) as? JsonPrimitive)?.contentOrNull ?: (item as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                    TimedEffect(time.toDoubleOrNull() ?: 0.0, effect, (io?.get("locator") as? JsonPrimitive)?.contentOrNull)
                }
            }.sortedBy { it.time }
        }
        return RigAnimation(name, length, loop, bones, effects("sound_effects", "effect"), effects("particle_effects", "effect"),
            effects("timeline", "instruction"), approximations.toList())
    }

    private fun values3(e: JsonElement?, default: Double): List<String>? = when (e) {
        is JsonArray -> e.map { (it as? JsonPrimitive)?.content ?: default.toString() }.let { if (it.size == 1) listOf(it[0], it[0], it[0]) else it.take(3) }
        is JsonPrimitive -> listOf(e.content, e.content, e.content)
        is JsonObject -> values3(e["vector"], default)
        else -> null
    }

    private fun channel(e: JsonElement?, default: Double, approximations: MutableSet<String>): Channel? {
        e ?: return null
        values3(e, default)?.takeIf { e !is JsonObject || e.containsKey("vector") }?.let { return Channel(listOf(Keyframe(0.0, it, it))) }
        val o = e as? JsonObject ?: return null
        val frames = o.mapNotNull { (time, v) ->
            val t = time.toDoubleOrNull() ?: return@mapNotNull null
            when (v) {
                is JsonObject -> {
                    val pre = values3(v["pre"] ?: v["post"] ?: v["vector"], default) ?: return@mapNotNull null
                    val post = values3(v["post"] ?: v["pre"] ?: v["vector"], default) ?: pre
                    val lerp = when ((v["lerp_mode"] as? JsonPrimitive)?.contentOrNull) {
                        "catmullrom" -> Lerp.CATMULLROM
                        "step" -> Lerp.STEP
                        "bezier" -> { approximations += "bezier keyframes are interpolated as Catmull-Rom"; Lerp.CATMULLROM }
                        else -> Lerp.LINEAR
                    }
                    Keyframe(t, pre, post, lerp)
                }
                else -> values3(v, default)?.let { Keyframe(t, it, it) }
            }
        }.sortedBy { it.time }
        return Channel(frames)
    }
}

/** Evaluates bone poses of an animation at a time, with Molang and interpolation. */
class AnimationSampler(private val animation: RigAnimation, groundSpeed: Double = 0.0) {
    private val molang = Molang(mapOf("query.ground_speed" to groundSpeed, "query.is_on_ground" to 1.0, "query.health" to 20.0,
        "query.max_health" to 20.0, "query.is_alive" to 1.0, "query.yaw_speed" to 0.0, "query.head_x_rotation" to 0.0,
        "query.head_y_rotation" to 0.0))
    private val timed = HashMap<Double, Molang>()

    val approximations: Set<String> get() = molang.unknown + timed.values.flatMap { it.unknown }

    private fun evalAt(expr: String, t: Double, default: Double): Double {
        expr.toDoubleOrNull()?.let { return it }
        val m = timed.getOrPut(t) {
            Molang(mapOf("query.anim_time" to t, "query.life_time" to t, "query.time_stamp" to t * 20,
                "query.modified_distance_moved" to t * 4, "query.distance_moved" to t * 4, "query.ground_speed" to 4.0,
                "query.is_on_ground" to 1.0, "query.health" to 20.0, "query.max_health" to 20.0, "query.is_alive" to 1.0))
        }
        return runCatching { m.eval(expr) }.getOrDefault(default)
    }

    private fun vec(exprs: List<String>, t: Double, default: Double) = DoubleArray(3) { evalAt(exprs.getOrElse(it) { exprs.first() }, t, default) }

    fun channel(ch: Channel?, t: Double, default: Double): DoubleArray {
        val k = ch?.keyframes ?: return DoubleArray(3) { default }
        if (k.isEmpty()) return DoubleArray(3) { default }
        if (k.size == 1 || t <= k.first().time) return vec(k.first().pre, t, default)
        if (t >= k.last().time) return vec(k.last().post, t, default)
        val i = k.indexOfLast { it.time <= t }
        val a = k[i]; val b = k[i + 1]
        val span = b.time - a.time
        val f = if (span <= 0) 1.0 else (t - a.time) / span
        val from = vec(a.post, t, default); val to = vec(b.pre, t, default)
        return when {
            a.lerp == Lerp.STEP -> from
            a.lerp == Lerp.CATMULLROM || b.lerp == Lerp.CATMULLROM -> {
                val p0 = if (i > 0) vec(k[i - 1].post, t, default) else from
                val p3 = if (i + 2 < k.size) vec(k[i + 2].pre, t, default) else to
                DoubleArray(3) { catmull(p0[it], from[it], to[it], p3[it], f) }
            }
            else -> DoubleArray(3) { from[it] + (to[it] - from[it]) * f }
        }
    }

    fun pose(bone: String, t: Double): BonePose {
        val track = animation.bones[bone]
        return BonePose(channel(track?.rotation, t, 0.0), channel(track?.position, t, 0.0), channel(track?.scale, t, 1.0))
    }

    private fun catmull(p0: Double, p1: Double, p2: Double, p3: Double, t: Double): Double {
        val t2 = t * t; val t3 = t2 * t
        return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }
}
