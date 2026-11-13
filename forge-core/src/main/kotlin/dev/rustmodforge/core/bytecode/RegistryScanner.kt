package dev.rustmodforge.core.bytecode

import dev.rustmodforge.core.model.Registration
import dev.rustmodforge.core.model.RegistryKind
import org.objectweb.asm.Opcodes
import org.objectweb.asm.Type
import org.objectweb.asm.tree.ClassNode
import org.objectweb.asm.tree.MethodNode

/**
 * Finds what a mod registers: Forge/NeoForge `DeferredRegister.register("name", supplier)`,
 * Fabric `Registry.register(registry, id, value)`, and mods' own `register(String, ...)`
 * wrappers around either. The registry kind comes from the registry constant used, or failing
 * that from what the registered value is (an Entity class, an Item, a SoundEvent...).
 */
class RegistryScanner(
    private val scanner: ClassScanner,
    private val modId: String,
    /** Namespaces the jar's resources use besides the mod id. */
    private val extraNamespaces: Set<String> = emptySet(),
) {
    private fun isDeferred(owner: String) = owner.startsWith("net/minecraftforge/registries/DeferredRegister") ||
        owner.startsWith("net/neoforged/neoforge/registries/DeferredRegister") || owner == "dev/architectury/registry/registries/DeferredRegister"
    private val registryOwners = setOf(
        "net/minecraft/core/Registry", "net/minecraft/core/registries/BuiltInRegistries", "net/minecraft/core/registries/Registries",
        "net/minecraftforge/registries/ForgeRegistries", "net/neoforged/neoforge/registries/NeoForgeRegistries",
        "net/minecraft/class_2378", "net/minecraft/class_7923", "net/minecraft/class_7924",
        "net/minecraft/registry/Registry", "net/minecraft/registry/Registries", "net/minecraft/registry/RegistryKeys",
        "net/minecraftforge/registries/ForgeRegistries\$Keys",
    )
    private val registerNames = setOf("register", "registerItem", "registerBlock", "registerSimpleItem", "registerSimpleBlock", "method_10230", "method_10226", "method_39197", "m_122961_", "m_122965_")

    private val drFieldKinds = HashMap<String, RegistryKind>()
    private val helperKinds = HashMap<String, RegistryKind?>()

    fun scan(): List<Registration> {
        val candidates = scanner.headers.values.filter { h ->
            h.references.any { isDeferred(it) || it in registryOwners }
        }.map { it.name }
        val nodes = candidates.mapNotNull { scanner.node(it) }
        // 1. Which DeferredRegister field holds which registry.
        for (cn in nodes) for (m in cn.methods) collectDeferredFields(cn, m)
        // 2. Mod helpers that register a String-named entry.
        for (cn in nodes) for (m in cn.methods) {
            val args = Type.getArgumentTypes(m.desc)
            if (args.isEmpty() || args[0].descriptor != "Ljava/lang/String;") continue
            val ev = Events.of(m)
            val reg = ev.indexOfFirst { it is Ev.Invoke && it.name in registerNames && (isDeferred(it.owner) || it.owner in registryOwners) }
            if (reg >= 0 && ev.take(reg).none { it is Ev.Str && !looksLikeNamespace(it.value) }) {
                helperKinds["${cn.name}.${m.name}${m.desc}"] = kindNear(ev, reg, 0)
            }
        }
        // 3. Every register call, including through helpers, anywhere a candidate or helper is used.
        val users = scanner.headers.values.filter { h ->
            h.name in candidates || helperKinds.keys.any { k -> h.references.contains(k.substringBefore('(')) }
        }.mapNotNull { scanner.node(it.name) }
        val found = LinkedHashMap<String, Registration>()
        for (cn in users) for (m in cn.methods) {
            val helperKey = "${cn.name}.${m.name}${m.desc}"
            if (helperKey in helperKinds) continue // the helper's body itself, with no literal name
            for (r in registrationsIn(cn, m)) found.putIfAbsent("${r.kind}:${r.id}", r)
        }
        return found.values.toList()
    }

    private fun collectDeferredFields(cn: ClassNode, m: MethodNode) {
        val ev = Events.of(m)
        for ((i, e) in ev.withIndex()) {
            if (e !is Ev.PutStatic) continue
            val create = (i - 1 downTo (i - 8).coerceAtLeast(0)).map { ev[it] }
                .firstOrNull { it is Ev.Invoke && isDeferred(it.owner) && it.name.startsWith("create") } as? Ev.Invoke ?: continue
            val kind = when (create.name) {
                "createItems" -> RegistryKind.ITEM
                "createBlocks" -> RegistryKind.BLOCK
                "createEntities" -> RegistryKind.ENTITY_TYPE
                else -> kindNear(ev, i, (i - 8).coerceAtLeast(0))
            } ?: continue
            drFieldKinds["${e.owner}.${e.name}"] = kind
        }
    }

    /** The registry a `GETSTATIC Registries.X` (or a known DeferredRegister field) before [at] names. */
    private fun kindNear(ev: List<Ev>, at: Int, floor: Int): RegistryKind? {
        for (j in at - 1 downTo floor) {
            val e = ev[j] as? Ev.GetStatic ?: continue
            drFieldKinds["${e.owner}.${e.name}"]?.let { return it }
            if (e.owner in registryOwners) kindFromRegistryName(e.name)?.let { return it }
        }
        return null
    }

    private fun registrationsIn(cn: ClassNode, m: MethodNode): List<Registration> {
        val ev = Events.of(m)
        val out = ArrayList<Registration>()
        var boundary = 0
        for ((i, e) in ev.withIndex()) {
            if (e !is Ev.Invoke) continue
            val key = "${e.owner}.${e.name}${e.desc}"
            val viaHelper = key in helperKinds
            val direct = e.name in registerNames && (isDeferred(e.owner) || e.owner in registryOwners)
            if (!viaHelper && !direct) continue
            val window = ev.subList(boundary, i)
            val strings = window.filterIsInstance<Ev.Str>().map { it.value }
            val name = pickId(strings)
            boundary = i + 1
            if (name == null) continue
            var kind = if (viaHelper) helperKinds[key] else kindNear(ev, i, (i - window.size).coerceAtLeast(0))
            val value = valueClass(cn, window)
            val details = LinkedHashMap<String, String>()
            entityDetails(cn, window, details)
            if (kind == null || kind == RegistryKind.OTHER) kind = inferKind(value, window, details) ?: RegistryKind.OTHER
            val field = (ev.getOrNull(i + 1) as? Ev.PutStatic)?.let { "${it.owner.substringAfterLast('/')}.${it.name}" }
            out += Registration(
                kind = kind, id = name, declaringClass = cn.name.replace('/', '.'),
                valueClass = value?.replace('/', '.'), field = field, details = details,
                evidence = "${cn.name.substringAfterLast('/')}.${m.name}: ${if (viaHelper) "${e.name}(\"${name.substringAfter(':')}\")" else "${e.owner.substringAfterLast('/')}.${e.name}"}",
            )
        }
        return out
    }

    private fun looksLikeNamespace(s: String) = s.matches(Regex("[a-z0-9_.-]{1,64}"))

    /** `"ns", "path"` (an Identifier) or a single `"path"` in the mod's namespace. */
    private fun pickId(strings: List<String>): String? {
        val valid = strings.filter { it.matches(Regex("[a-z0-9_.:/-]{1,128}")) }
        if (valid.isEmpty()) return null
        // An Identifier is built from (namespace, path) before the value is: the first pair counts.
        if (valid.size >= 2 && (valid[0] == modId || valid[0] in extraNamespaces) && !valid[1].contains(':')) {
            return "${valid[0]}:${valid[1]}"
        }
        val first = valid.first()
        return if (first.contains(':')) first else "$modId:$first"
    }

    private fun valueClass(cn: ClassNode, window: List<Ev>): String? {
        for (e in window) {
            if (e is Ev.Indy) {
                val h = e.impl ?: continue
                if (h.tag == Opcodes.H_NEWINVOKESPECIAL && !Vanilla.isMinecraft(h.owner)) return h.owner
                if (h.owner == cn.name && h.name.startsWith("lambda$")) {
                    val lambda = cn.methods.firstOrNull { it.name == h.name && it.desc == h.desc } ?: continue
                    valueFromBody(Events.of(lambda))?.let { return it }
                }
            }
        }
        return valueFromBody(window)
    }

    private fun valueFromBody(ev: List<Ev>): String? {
        ev.filterIsInstance<Ev.Indy>().mapNotNull { it.impl }.firstOrNull { it.tag == Opcodes.H_NEWINVOKESPECIAL && scanner.headers.containsKey(it.owner) }?.let { return it.owner }
        return ev.filterIsInstance<Ev.New>().map { it.type }.firstOrNull { scanner.headers.containsKey(it) }
            ?: ev.filterIsInstance<Ev.New>().map { it.type }.firstOrNull { Vanilla.classConcept(it) != null }
    }

    private fun entityDetails(cn: ClassNode, window: List<Ev>, details: MutableMap<String, String>) {
        val bodies = ArrayList<List<Ev>>()
        bodies += window
        window.filterIsInstance<Ev.Indy>().mapNotNull { it.impl }.filter { it.owner == cn.name && it.name.startsWith("lambda$") }.forEach { h ->
            cn.methods.firstOrNull { it.name == h.name && it.desc == h.desc }?.let { bodies += Events.of(it) }
        }
        for (ev in bodies) {
            for ((i, e) in ev.withIndex()) {
                if (e is Ev.Invoke && (e.name == "sized" || e.name == "m_20699_" || e.name == "method_17687" || e.name == "dimensions")) {
                    val nums = Events.numbersBetween(ev, (i - 6).coerceAtLeast(0), i)
                    if (nums.size >= 2) { details["width"] = Events.fmt(nums[nums.size - 2]); details["height"] = Events.fmt(nums.last()) }
                }
                if (e is Ev.GetStatic && Vanilla.mobCategories.containsKey(e.name) && (e.owner.endsWith("MobCategory") || e.owner.endsWith("SpawnGroup") || e.owner == "net/minecraft/class_1311")) {
                    details["category"] = Vanilla.mobCategories.getValue(e.name)
                }
                if (e is Ev.Invoke && (e.owner.contains("EntityType\$Builder") || e.owner.contains("FabricEntityTypeBuilder") || e.owner == "net/minecraft/class_1299\$class_1300")) {
                    details["builder"] = "EntityType"
                }
            }
        }
    }

    private fun inferKind(value: String?, window: List<Ev>, details: Map<String, String>): RegistryKind? {
        if (details["builder"] == "EntityType") return RegistryKind.ENTITY_TYPE
        if (value != null) {
            if (scanner.extendsConcept(value, "Entity")) return RegistryKind.ENTITY_TYPE
            if (scanner.extendsConcept(value, "Item") || Vanilla.classConcept(value)?.endsWith("Item") == true) return RegistryKind.ITEM
            if (scanner.extendsConcept(value, "Block") || Vanilla.classConcept(value)?.endsWith("Block") == true) return RegistryKind.BLOCK
            if (scanner.extendsConcept(value, "BlockEntity")) return RegistryKind.BLOCK_ENTITY
        }
        val calls = window.filterIsInstance<Ev.Invoke>()
        if (calls.any { it.owner.endsWith("SoundEvent") || it.owner == "net/minecraft/class_3414" || it.name == "createVariableRangeEvent" }) return RegistryKind.SOUND_EVENT
        if (window.any { it is Ev.New && (it.type.endsWith("SoundEvent") || it.type == "net/minecraft/class_3414") }) return RegistryKind.SOUND_EVENT
        return null
    }

    companion object {
        fun kindFromRegistryName(name: String): RegistryKind? {
            val n = name.uppercase()
            return when {
                n.startsWith("ENTITY_TYPE") || n == "ENTITIES" -> RegistryKind.ENTITY_TYPE
                n.startsWith("BLOCK_ENTITY") -> RegistryKind.BLOCK_ENTITY
                n == "ITEM" || n == "ITEMS" -> RegistryKind.ITEM
                n == "BLOCK" || n == "BLOCKS" -> RegistryKind.BLOCK
                n.startsWith("SOUND_EVENT") || n == "SOUNDS" -> RegistryKind.SOUND_EVENT
                n.startsWith("PARTICLE_TYPE") -> RegistryKind.PARTICLE_TYPE
                n.startsWith("MOB_EFFECT") || n == "STATUS_EFFECT" || n == "EFFECTS" -> RegistryKind.MOB_EFFECT
                n.startsWith("CREATIVE_MODE_TAB") || n == "ITEM_GROUP" -> RegistryKind.CREATIVE_TAB
                n.startsWith("MENU") || n == "SCREEN_HANDLER" -> RegistryKind.MENU
                n.startsWith("RECIPE_SERIALIZER") -> RegistryKind.RECIPE_SERIALIZER
                n.startsWith("ENCHANTMENT") -> RegistryKind.ENCHANTMENT
                n.startsWith("ATTRIBUTE") -> RegistryKind.ATTRIBUTE
                else -> null
            }
        }
    }
}
