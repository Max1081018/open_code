package dev.rustmodforge.core.bytecode

import dev.rustmodforge.core.model.EntityInfo
import dev.rustmodforge.core.model.EntitySounds
import dev.rustmodforge.core.model.GoalInfo
import dev.rustmodforge.core.model.GoalSelectorKind
import dev.rustmodforge.core.model.Registration
import dev.rustmodforge.core.model.RegistryKind
import dev.rustmodforge.core.model.TraitKind
import org.objectweb.asm.Type
import org.objectweb.asm.tree.ClassNode

/**
 * Reads each entity class: its vanilla base, default attributes (`createAttributes`), goals
 * (`registerGoals`), sounds, GeckoLib use and behaviours (via [BehaviourScanner]) from its own
 * methods, its mod superclasses, nested classes and the custom goals it adds.
 */
class EntityScanner(
    private val scanner: ClassScanner,
    private val registrations: List<Registration>,
    private val modId: String,
) {
    private val behaviour = BehaviourScanner(registrations)
    private val goalSelectorFields = setOf("goalSelector", "f_21345_", "field_6201")
    private val targetSelectorFields = setOf("targetSelector", "f_21346_", "field_6185")
    private val builderReturns = setOf(
        "net/minecraft/world/entity/ai/attributes/AttributeSupplier\$Builder", "net/minecraft/class_5132\$class_5133",
        "net/minecraft/entity/attribute/DefaultAttributeContainer\$Builder",
    )

    fun scan(): List<EntityInfo> {
        val registered = registrations.filter { it.kind == RegistryKind.ENTITY_TYPE }
        val byClass = registered.filter { it.valueClass != null }.associateBy { it.valueClass!!.replace('.', '/') }
        // Entity classes: registered ones, plus mob classes nobody registered in a way we could see.
        val classes = LinkedHashSet<String>()
        classes += byClass.keys.filter { scanner.headers.containsKey(it) }
        classes += scanner.headers.keys.filter { scanner.extendsConcept(it, "Mob") && (scanner.headers[it]!!.access and org.objectweb.asm.Opcodes.ACC_ABSTRACT) == 0 }
        val out = ArrayList<EntityInfo>()
        for (cls in classes) {
            val node = scanner.node(cls) ?: continue
            val reg = byClass[cls]
            val id = reg?.id ?: "$modId:${snake(cls.substringAfterLast('/'))}"
            out += scanEntity(node, id, reg)
        }
        // Registered types whose class we could not resolve still appear, marked unresolved.
        for (r in registered.filter { it.valueClass == null || !scanner.headers.containsKey(it.valueClass.replace('.', '/')) }) {
            if (out.any { it.id == r.id }) continue
            out += EntityInfo(
                id = r.id, className = r.valueClass ?: "?", vanillaBase = r.valueClass?.let { Vanilla.classConcept(it.replace('.', '/')) } ?: "Entity",
                category = r.details["category"] ?: "", width = r.details["width"]?.toDoubleOrNull(), height = r.details["height"]?.toDoubleOrNull(),
                unresolved = listOf("entity class of ${r.id} not found in the jar (registered by ${r.evidence})"),
            )
        }
        return out
    }

    private fun scanEntity(node: ClassNode, id: String, reg: Registration?): EntityInfo {
        val chain = scanner.superChain(node.name)
        val modSupers = chain.filter { scanner.headers.containsKey(it) }.mapNotNull { scanner.node(it) }
        val own = listOf(node) + modSupers
        val unresolved = ArrayList<String>()

        // Default attributes.
        val attributes = LinkedHashMap<String, Double>()
        for (cn in own) for (m in cn.methods) {
            if (Type.getReturnType(m.desc).sort != Type.OBJECT || Type.getReturnType(m.desc).internalName !in builderReturns) continue
            val ev = Events.of(m)
            for ((i, e) in ev.withIndex()) {
                if (e !is Ev.Invoke || !Vanilla.isMethod("attributeAdd", e.name) || e.owner !in builderReturns) continue
                val attr = (i - 1 downTo (i - 6).coerceAtLeast(0)).map { ev[it] }.firstOrNull { it is Ev.GetStatic } as? Ev.GetStatic ?: continue
                val attrIndex = (i - 1 downTo 0).first { ev[it] === attr }
                val attrId = Vanilla.attributes[attr.name]
                if (attrId == null) { unresolved += "attribute ${attr.owner.substringAfterLast('/')}.${attr.name}"; continue }
                if (e.argCount >= 2) Events.numbersBetween(ev, attrIndex + 1, i).lastOrNull()?.let { attributes.putIfAbsent(attrId, it) }
            }
        }

        // Goals.
        val goals = ArrayList<GoalInfo>()
        val customGoalClasses = LinkedHashSet<String>()
        for (cn in own) for (m in cn.methods) {
            if (!Vanilla.isMethod("registerGoals", m.name) || m.desc != "()V") continue
            val ev = Events.of(m)
            var selector: GoalSelectorKind? = null
            var start = 0
            for ((i, e) in ev.withIndex()) {
                if (e is Ev.GetField && e.name in goalSelectorFields) { selector = GoalSelectorKind.GOAL; start = i }
                if (e is Ev.GetField && e.name in targetSelectorFields) { selector = GoalSelectorKind.TARGET; start = i }
                if (e is Ev.Invoke && Vanilla.isMethod("addGoal", e.name) && e.desc.startsWith("(I") && selector != null) {
                    val window = ev.subList(start + 1, i)
                    val priority = (window.firstOrNull() as? Ev.Num)?.value?.toInt() ?: 0
                    val newType = window.filterIsInstance<Ev.New>().firstOrNull()?.type
                    if (newType == null) { selector = null; continue }
                    val newIdx = window.indexOfFirst { it is Ev.New }
                    val ctorIdx = window.indexOfLast { it is Ev.Invoke && it.name == "<init>" && it.owner == newType }.let { if (it < 0) window.size else it }
                    val args = window.subList(newIdx + 1, ctorIdx).mapNotNull {
                        when (it) {
                            is Ev.Num -> Events.fmt(it.value)
                            is Ev.Cls -> it.type.substringAfterLast('/')
                            else -> null
                        }
                    }
                    val targets = window.filterIsInstance<Ev.Cls>().map { Vanilla.classConcept(it.type) ?: it.type.substringAfterLast('/') }
                    val concept = Vanilla.goalConcept(newType)
                    val custom = concept == null
                    if (custom && scanner.headers.containsKey(newType)) customGoalClasses += newType
                    goals += GoalInfo(selector, priority, concept ?: newType.replace('/', '.'), custom, args, targets)
                    selector = null
                }
            }
        }

        // Nested classes (anonymous and inner goals) belong to the entity too.
        val nested = scanner.headers.keys.filter { it.startsWith(node.name + "$") }
        val behaviourClasses = (own + (customGoalClasses + nested).distinct().mapNotNull { scanner.node(it) })
        val goalClasses = behaviourClasses.map { it.name }.filter { scanner.extendsConcept(it, "Goal") }.toSet()
        val traits = behaviour.traitsOf(behaviourClasses, goalClasses).toMutableList()
        if (goals.any { it.goal == "NearestAttackableTargetGoal" && "Player" in it.targets } && goals.any { it.goal == "MeleeAttackGoal" }) {
            traits += dev.rustmodforge.core.model.BehaviourTrait(TraitKind.CHASE_PLAYER, emptyMap(), listOf("registerGoals: NearestAttackableTargetGoal(Player) + MeleeAttackGoal"))
        }

        // Sounds from the standard getters.
        fun soundFrom(concept: String): String? {
            for (cn in own) for (m in cn.methods) {
                if (!Vanilla.isMethod(concept, m.name)) continue
                for (gs in Events.of(m).filterIsInstance<Ev.GetStatic>()) {
                    val simple = "${gs.owner.substringAfterLast('/')}.${gs.name}"
                    registrations.firstOrNull { it.field == simple }?.let { return it.id }
                    if (gs.owner.endsWith("SoundEvents")) return "vanilla:${gs.name}"
                }
                // RegistryObject/Supplier fields: GETSTATIC then get().
                Events.of(m).filterIsInstance<Ev.GetStatic>().firstOrNull()?.let { return "field:${it.owner.substringAfterLast('/')}.${it.name}" }
            }
            return null
        }
        val sounds = EntitySounds(
            ambient = soundFrom("getAmbientSound"), hurt = soundFrom("getHurtSound"), death = soundFrom("getDeathSound"),
            step = soundFrom("playStepSound"),
            other = traits.filter { it.kind == TraitKind.PLAY_SOUND }.mapNotNull { it.params["sound"] }.distinct(),
        )

        val gecko = scanner.implementsConcept(node.name, "GeoEntity")
        val base = scanner.vanillaBase(node.name) ?: "Entity"
        return EntityInfo(
            id = id, className = node.name.replace('/', '.'), vanillaBase = base,
            superChain = chain.map { Vanilla.classConcept(it) ?: it.replace('/', '.') },
            category = reg?.details?.get("category") ?: if (base == "Monster" || scanner.extendsConcept(node.name, "Monster")) "monster" else "",
            width = reg?.details?.get("width")?.toDoubleOrNull(), height = reg?.details?.get("height")?.toDoubleOrNull(),
            attributes = attributes, goals = goals.sortedWith(compareBy({ it.selector }, { it.priority })),
            traits = traits, sounds = resolveFieldSounds(sounds), usesGeckoLib = gecko, unresolved = unresolved.distinct(),
        )
    }

    /** `field:ModSounds.X` → the registered id when a registration stored into that field. */
    private fun resolveFieldSounds(s: EntitySounds): EntitySounds {
        fun r(v: String?): String? {
            if (v == null || !v.startsWith("field:")) return v
            val f = v.removePrefix("field:")
            return registrations.firstOrNull { it.field == f }?.id ?: v
        }
        return s.copy(ambient = r(s.ambient), hurt = r(s.hurt), death = r(s.death), step = r(s.step))
    }

    companion object {
        fun snake(name: String) = name.replace(Regex("([a-z0-9])([A-Z])"), "$1_$2").lowercase().replace(Regex("[^a-z0-9_]"), "_")
    }
}
