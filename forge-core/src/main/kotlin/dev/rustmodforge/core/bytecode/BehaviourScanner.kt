package dev.rustmodforge.core.bytecode

import dev.rustmodforge.core.model.BehaviourTrait
import dev.rustmodforge.core.model.Registration
import dev.rustmodforge.core.model.TraitKind
import org.objectweb.asm.tree.ClassNode
import org.objectweb.asm.tree.MethodNode
import kotlin.math.sqrt

/**
 * Recognises behaviours from what methods call and the constants they compare against.
 * Each rule needs specific evidence (for example a distance check *and* a discard in the same
 * method for "vanishes when approached"), and every trait records the methods that showed it,
 * so the report can point at the original code.
 */
class BehaviourScanner(private val registrations: List<Registration>) {

    /** What one method does, reduced to concepts. */
    class MethodFacts(val owner: String, val method: MethodNode, merged: List<Ev>? = null, labelOverride: String? = null) {
        val events = merged ?: Events.of(method)
        val concepts: Set<String> = events.filterIsInstance<Ev.Invoke>().flatMap { Vanilla.methodConcepts(it.name) }.toSet()
        val label = labelOverride ?: "${owner.substringAfterLast('/')}.${method.name}"
        fun has(c: String) = c in concepts
        fun numbersNear(concept: String, radius: Int = 8): List<Double> {
            val out = ArrayList<Double>()
            events.forEachIndexed { i, e ->
                if (e is Ev.Invoke && Vanilla.isMethod(concept, e.name)) out += Events.numbersBetween(events, i - radius, i + radius)
            }
            return out
        }
        fun staticNames(ownerSuffix: String) = events.filterIsInstance<Ev.GetStatic>().filter { it.owner.endsWith(ownerSuffix) }.map { it.name }
    }

    /**
     * [goalClasses] are judged as a whole (a goal finds the player in `canUse` and moves in
     * `tick`); other classes method by method, so unrelated code in a big entity class does not
     * combine into a behaviour it does not have.
     */
    fun traitsOf(classes: List<ClassNode>, goalClasses: Set<String> = emptySet()): List<BehaviourTrait> {
        val facts = classes.flatMap { cn ->
            val methods = cn.methods.filter { it.instructions.size() > 0 }
            val perMethod = methods.map { MethodFacts(cn.name, it) }
            if (cn.name in goalClasses && methods.isNotEmpty()) {
                val merged = methods.flatMap { Events.of(it) }
                perMethod + MethodFacts(cn.name, methods.first(), merged, "${cn.name.substringAfterLast('/')} (goal)")
            } else perMethod
        }
        val traits = ArrayList<BehaviourTrait>()
        fun add(kind: TraitKind, params: Map<String, String>, evidence: List<String>) {
            val existing = traits.indexOfFirst { it.kind == kind && it.params == params }
            if (existing >= 0) traits[existing] = traits[existing].copy(evidence = (traits[existing].evidence + evidence).distinct())
            else traits += BehaviourTrait(kind, params, evidence.distinct())
        }

        for (f in facts) {
            val distance = f.has("distanceToSqr") || f.has("distanceTo")
            val removes = f.has("discard") || f.has("teleportTo")
            val looksAt = f.has("lookVector") && f.has("vecDot")
            val dist = distanceParam(f)
            if (distance && removes && !looksAt) {
                add(TraitKind.VANISH_WHEN_APPROACHED, dist?.let { mapOf("distance" to it) } ?: emptyMap(),
                    listOf("${f.label}: distance check then ${if (f.has("discard")) "discard/remove" else "teleport"}"))
            }
            if (looksAt) {
                when {
                    removes -> add(TraitKind.VANISH_WHEN_LOOKED_AT, emptyMap(), listOf("${f.label}: player's look vector · direction, then discard/teleport"))
                    f.events.any { it is Ev.Invoke && (it.name == "stop" || it.name == "m_26573_" || it.name == "method_6340" || it.name == "setDeltaMovement" || it.name == "m_20256_" || it.name == "method_18799") } ->
                        add(TraitKind.FREEZE_WHEN_LOOKED_AT, emptyMap(), listOf("${f.label}: player's look vector · direction, then stops moving"))
                    else -> add(TraitKind.LINE_OF_SIGHT_CHECK, mapOf("kind" to "player_looking"), listOf("${f.label}: player's look vector · direction"))
                }
            }
            if (f.has("hasLineOfSight")) add(TraitKind.LINE_OF_SIGHT_CHECK, mapOf("kind" to "mob_sees_player"), listOf("${f.label}: hasLineOfSight"))
            if (f.has("getNearestPlayer") || f.has("getTarget")) {
                when {
                    f.has("navigationMoveTo") && distance -> add(TraitKind.STALK_PLAYER, dist?.let { mapOf("keep_distance" to it) } ?: emptyMap(),
                        listOf("${f.label}: finds the player, keeps a distance, paths toward them"))
                    f.has("lookAt") && !f.has("navigationMoveTo") -> add(TraitKind.WATCH_FROM_DISTANCE, dist?.let { mapOf("distance" to it) } ?: emptyMap(),
                        listOf("${f.label}: finds the player and turns to look without moving"))
                    f.has("teleportTo") -> add(TraitKind.TELEPORT_NEAR_PLAYER, dist?.let { mapOf("distance" to it) } ?: emptyMap(),
                        listOf("${f.label}: teleports relative to the player"))
                    else -> {}
                }
            }
            if (f.has("isNight") || timeOfDayCheck(f) == "night") add(TraitKind.NIGHT_ONLY, emptyMap(), listOf("${f.label}: night check"))
            else if (f.has("isDay") || timeOfDayCheck(f) == "day") add(TraitKind.DAY_ONLY, emptyMap(), listOf("${f.label}: day check"))
            if (f.has("addEffect")) {
                val effects = f.staticNames("MobEffects").mapNotNull { Vanilla.effects[it] }.ifEmpty { f.staticNames("StatusEffects").mapNotNull { Vanilla.effects[it] } }
                val ticks = f.numbersNear("addEffect").firstOrNull { it >= 20 }
                for (effect in effects.ifEmpty { listOf("unknown") }) {
                    add(TraitKind.APPLY_EFFECT_TO_PLAYER, buildMap { put("effect", effect); ticks?.let { put("duration_ticks", Events.fmt(it)) } },
                        listOf("${f.label}: addEffect"))
                }
            }
            if (f.has("playSound")) {
                for (s in soundsUsed(f)) add(TraitKind.PLAY_SOUND, mapOf("sound" to s, "context" to f.method.name), listOf("${f.label}: playSound"))
            }
            if (f.has("addParticle")) {
                val particles = f.staticNames("ParticleTypes").map { "minecraft:" + it.lowercase() }
                for (p in particles.ifEmpty { listOf("unknown") }) add(TraitKind.SPAWN_PARTICLES, mapOf("particle" to p), listOf("${f.label}: addParticle"))
            }
            if (f.has("setInvisible")) add(TraitKind.TOGGLE_INVISIBILITY, emptyMap(), listOf("${f.label}: setInvisible"))
            if (f.has("destroyBlock")) add(TraitKind.BREAK_BLOCKS, emptyMap(), listOf("${f.label}: destroyBlock"))
            if (Vanilla.isMethod("removeWhenFarAway", f.method.name) && returnsConstant(f) == 0.0) add(TraitKind.PERSISTENT, emptyMap(), listOf("${f.label}: returns false"))
            if (Vanilla.isMethod("requiresCustomPersistence", f.method.name) && returnsConstant(f) == 1.0) add(TraitKind.PERSISTENT, emptyMap(), listOf("${f.label}: returns true"))
            if (Vanilla.isMethod("removeWhenFarAway", f.method.name) && f.has("distanceToSqr")) add(TraitKind.DESPAWN_WHEN_FAR, dist?.let { mapOf("distance" to it) } ?: emptyMap(), listOf("${f.label}: distance-based despawn"))
            if (Vanilla.isMethod("doHurtTarget", f.method.name) && f.method.desc.contains("Entity")) {
                add(TraitKind.CUSTOM_MELEE, emptyMap(), listOf("${f.label}: overrides the melee hit"))
            }
            if (Vanilla.isMethod("isSunBurnTick", f.method.name)) add(TraitKind.FLEE_LIGHT, mapOf("burns" to (returnsConstant(f) != 0.0).toString()), listOf("${f.label}: sun burn rule"))
            if (f.events.any { it is Ev.Invoke && Vanilla.isMethod("spawnPlacementRegister", it.name) && it.owner.contains("SpawnPlacement") }) {
                add(TraitKind.CUSTOM_SPAWN_RULE, emptyMap(), listOf("${f.label}: SpawnPlacements.register"))
            }
            if (f.events.any { it is Ev.Invoke && (it.owner.contains("FogRenderer") || it.owner.contains("RenderFog") || it.name.contains("setFog")) } ||
                f.events.any { it is Ev.Invoke && it.owner.contains("ViewportEvent") }) {
                add(TraitKind.FOG_OR_DARKNESS, fogParams(f), listOf("${f.label}: changes the fog"))
            }
        }
        return traits
    }

    /** Client-side classes (screens, overlays) showing a full-screen image with a scare-like name. */
    fun jumpscares(classes: List<ClassNode>, scanner: ClassScanner): List<BehaviourTrait> {
        val out = ArrayList<BehaviourTrait>()
        for (cn in classes) {
            val strings = scanner.headers[cn.name]?.strings ?: emptyList()
            val textures = strings.filter { it.endsWith(".png") || it.contains("textures/") }
            val scary = textures.filter { s -> listOf("scare", "jump", "screamer", "face", "overlay").any { s.lowercase().contains(it) } }
            if (scary.isEmpty()) continue
            val blits = cn.methods.any { m -> Events.of(m).any { it is Ev.Invoke && Vanilla.isMethod("blit", it.name) } }
            if (!blits && !scanner.extendsConcept(cn.name, "Screen")) continue
            out += BehaviourTrait(TraitKind.JUMPSCARE_OVERLAY, mapOf("texture" to scary.first()), listOf("${cn.name.substringAfterLast('/')}: draws ${scary.first()} over the screen"))
        }
        return out
    }

    private fun distanceParam(f: MethodFacts): String? {
        val nums = (f.numbersNear("distanceToSqr") + f.numbersNear("distanceTo")).filter { it > 1.0 && it < 100_000 }
        if (nums.isEmpty()) return null
        val squared = f.has("distanceToSqr")
        val value = nums.max()
        return Events.fmt(if (squared && value > 16) Math.round(sqrt(value) * 10) / 10.0 else value)
    }

    /** `getDayTime() % 24000 > 13000`-style checks. */
    private fun timeOfDayCheck(f: MethodFacts): String? {
        if (!f.has("getDayTime")) return null
        val nums = f.numbersNear("getDayTime", 10)
        return when {
            nums.any { it in 12000.0..14000.0 } || nums.any { it in 22000.0..23999.0 } -> "night"
            nums.any { it in 0.0..1000.0 } && nums.any { it in 11000.0..12500.0 } -> "day"
            else -> null
        }
    }

    private fun soundsUsed(f: MethodFacts): List<String> {
        val out = ArrayList<String>()
        for (gs in f.events.filterIsInstance<Ev.GetStatic>()) {
            val simple = "${gs.owner.substringAfterLast('/')}.${gs.name}"
            val reg = registrations.firstOrNull { it.field == simple }
            when {
                reg != null -> out += reg.id
                gs.owner.endsWith("SoundEvents") -> out += "vanilla:${gs.name}"
            }
        }
        return out.distinct()
    }

    private fun returnsConstant(f: MethodFacts): Double? {
        val ev = f.events
        val ret = ev.indexOfFirst { it is Ev.Return }
        if (ret <= 0) return null
        return (ev[ret - 1] as? Ev.Num)?.value
    }

    private fun fogParams(f: MethodFacts): Map<String, String> {
        val nums = f.events.filterIsInstance<Ev.Num>().map { it.value }.filter { it > 0 && it < 512 }
        return if (nums.isEmpty()) emptyMap() else mapOf("near" to Events.fmt(nums.min()), "far" to Events.fmt(nums.max()))
    }
}
