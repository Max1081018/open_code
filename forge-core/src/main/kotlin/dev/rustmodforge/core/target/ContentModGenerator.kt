package dev.rustmodforge.core.target

import dev.rustmodforge.core.analysis.MetadataReader
import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.compat.HorizonCompat
import dev.rustmodforge.core.model.EntityInfo
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.model.RegistryKind
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.model.TraitKind
import dev.rustmodforge.core.report.FeatureResult
import dev.rustmodforge.core.report.FeatureStatus
import dev.rustmodforge.core.util.JsonTree

/**
 * Writes a Horizon content mod (`.hmod` tree, API 0.2): the jar's assets and data upgraded to
 * 26.3 shapes, kept inside the namespaces a content mod may hold, plus `data/<id>/horizon/`
 * declarations for its blocks, items and entity types. Every skipped file is reported.
 */
class ContentModGenerator(
    private val analysis: ModAnalysis,
    private val archive: SafeArchive,
    private val out: OutputTree,
    private val includeWorldgen: Boolean = false,
    /** Whether the target declares living entity types (upstream yes, Horizon Android no). */
    private val livingEntityTypes: Boolean = true,
) {
    companion object {
        /** The tag that marks a tagged vanilla body as one of the mod's creatures (Android route). */
        fun creatureTag(modId: String, entity: String) = "$modId.e.$entity"
        fun bodyFor(hostile: Boolean) = if (hostile) "minecraft:zombie" else "minecraft:pig"
    }

    val features = ArrayList<FeatureResult>()
    val warnings = ArrayList<String>()
    val id: String = MetadataReader.sanitizeId(analysis.metadata.modId)
    private val reserved = setOf("minecraft", "c", "horizon")
    private val loaderNamespaces = setOf("forge", "neoforge", "fabric", "quilt")
    private val pathOk = Regex("[a-z0-9_.-]+(/[a-z0-9_.-]+)+")

    /** Namespaces besides [id] the mod's files live in, listed in the manifest. */
    val extraNamespaces: List<String> = analysis.resources
        .filter { it.path.startsWith("assets/") || it.path.startsWith("data/") }
        .map { it.namespace }
        .filter { it.isNotEmpty() && it != id && it !in reserved && it !in loaderNamespaces && it.matches(Regex("[a-z0-9_.-]{1,64}")) }
        .distinct().sorted()

    private val owned: Set<String> get() = setOf(id) + extraNamespaces
    private var copied = 0
    private val skipped = LinkedHashMap<String, MutableList<String>>()

    /** Whether the mod has content of its own: a .hmod with nothing but a manifest does nothing. */
    fun hasOwnContent() = out.list().any { it.startsWith("assets/") || it.startsWith("data/") }

    private fun skip(reason: String, path: String) { skipped.getOrPut(reason) { ArrayList() } += path }

    fun generate() {
        copyResources()
        addItemDefinitions()
        declareEntities()
        declareItemsAndBlocks()
        ensureNames()
        writeManifest()
        summarize()
    }

    private fun copyResources() {
        for (r in analysis.resources) {
            val path = r.path
            if (!(path.startsWith("assets/") || path.startsWith("data/"))) continue
            val parts = path.split('/')
            if (parts.size < 3) continue
            val (root, ns) = parts[0] to parts[1]
            val rest = parts.drop(2).joinToString("/")
            var target = DataUpgrader.renamePath(path)
            when {
                root == "assets" && ns == "minecraft" && rest.startsWith("atlases/") -> {}
                root == "assets" && ns == "minecraft" -> { skip("vanilla's own assets, which a content mod may not hold: they are carried in the resource pack instead", path); continue }
                root == "data" && (ns == "minecraft" || ns == "c") && target.removePrefix("data/$ns/").startsWith("tags/") -> {}
                root == "data" && ns in loaderNamespaces && rest.startsWith("tags/") -> target = DataUpgrader.renamePath("data/c/$rest")
                root == "data" && (ns == "minecraft" || ns in loaderNamespaces) -> { skip("vanilla's own data other than tags, which a content mod may not hold: it is carried in the data pack instead", path); continue }
                ns !in owned -> { skip("files in a namespace the mod cannot claim", path); continue }
            }
            if (!target.matches(pathOk)) { skip("paths vanilla does not read (upper case or invalid characters)", path); continue }
            if (r.kind == ResourceKind.WORLDGEN && !includeWorldgen) { skip("world generation JSON (1.x worldgen differs from 26.3; run Horizon's upgrade-datapack on it)", path); continue }
            if (!livingEntityTypes && r.kind == ResourceKind.BIOME_MODIFIER && spawnsModEntity(path)) {
                skip("biome modifiers spawning the mod's creatures (on Horizon Android they are spawned by the mod's functions)", path); continue
            }
            if (r.kind == ResourceKind.LANG && path.endsWith(".lang")) {
                out.putJson(target.removeSuffix(".lang").lowercase() + ".json", legacyLang(archive.readText(path))); copied++; continue
            }
            if (path.endsWith(".json") || path.endsWith(".mcmeta")) {
                val parsed = runCatching { JsonTree.parse(archive.readText(path)) }.getOrNull()
                if (parsed == null) { skip("JSON that does not parse", path); continue }
                upgrade(r.kind, parsed, path)
                out.putJson(target, parsed)
            } else {
                out.copyFrom(archive, path, target)
            }
            copied++
        }
    }

    private fun spawnsModEntity(path: String): Boolean {
        val o = JsonTree.obj(runCatching { JsonTree.parse(archive.readText(path)) }.getOrNull()) ?: return false
        return (o["type"] as? String)?.endsWith("add_spawns") == true && JsonTree.write(o["spawners"]).contains("\"$id:")
    }

    private val recipesKept = ArrayList<String>()

    private fun upgrade(kind: ResourceKind, v: Any?, path: String) {
        when (kind) {
            ResourceKind.RECIPE -> JsonTree.obj(v)?.let { if (!DataUpgrader.upgradeRecipe(it)) recipesKept += path }
            ResourceKind.LOOT_TABLE -> DataUpgrader.upgradeLoot(v)
            ResourceKind.ADVANCEMENT -> JsonTree.obj(v)?.let { DataUpgrader.upgradeAdvancement(it) }
            ResourceKind.BLOCK_MODEL, ResourceKind.BLOCKSTATE -> DataUpgrader.upgradeAssets(v)
            else -> {}
        }
        if (path.startsWith("data/")) DataUpgrader.renameIds(v)
    }

    private fun legacyLang(text: String): Map<String, String> = text.lines().mapNotNull { line ->
        val l = line.trim()
        if (l.isEmpty() || l.startsWith("#") || !l.contains('=')) null else l.substringBefore('=') to l.substringAfter('=')
    }.toMap()

    /** 1.21.4 moved item models behind `assets/<ns>/items/<name>.json` definitions. */
    private fun addItemDefinitions() {
        var added = 0
        for (ns in owned) {
            val prefix = "assets/$ns/models/item/"
            for (p in out.list().filter { it.startsWith(prefix) && it.endsWith(".json") }) {
                val name = p.removePrefix(prefix).removeSuffix(".json")
                val def = "assets/$ns/items/$name.json"
                if (!out.exists(def)) {
                    out.putJson(def, JsonTree.of("model" to JsonTree.of("type" to "minecraft:model", "model" to "$ns:item/$name")))
                    added++
                }
            }
        }
        if (added > 0) warnings += "Added $added item model definitions (assets/<ns>/items/) that 1.21.4+ needs"
    }

    fun isHostile(e: EntityInfo) = e.category == "monster" || e.vanillaBase in setOf("Monster", "Zombie", "AbstractSkeleton", "Spider", "EnderMan", "Creeper") ||
        e.traits.any { it.kind == TraitKind.CHASE_PLAYER } || e.goals.any { it.goal == "MeleeAttackGoal" }

    /** The vanilla living template an entity is declared from. */
    fun templateFor(e: EntityInfo): String? = when {
        e.vanillaBase in setOf("Projectile", "ThrowableItemProjectile") -> null
        e.vanillaBase in setOf("Entity") -> null
        isHostile(e) -> "minecraft:zombie"
        else -> "minecraft:wandering_trader"
    }

    private fun declareEntities() {
        for (e in analysis.entities) {
            val ns = e.id.substringBefore(':'); val name = e.id.substringAfter(':')
            if (ns != id) {
                features += FeatureResult("Entities", "Entity type ${e.id}", FeatureStatus.UNSUPPORTED,
                    reason = "Horizon declares entity types only in the manifest id's namespace ($id); this one is in $ns")
                continue
            }
            if (!livingEntityTypes) {
                if (templateFor(e) == null) {
                    features += FeatureResult("Entities", "Entity type ${e.id}", FeatureStatus.UNSUPPORTED,
                        reason = "a ${e.vanillaBase} has no counterpart here: Horizon Android declares only snowball-like projectiles, and those need one of the mod's items")
                } else {
                    val body = bodyFor(isHostile(e))
                    features += FeatureResult("Entities", "Entity type ${e.id}", FeatureStatus.PARTIAL,
                        "a tagged $body (tag ${creatureTag(id, name)}) managed by the mod's functions",
                        "Horizon Android declares no living mob types (only snowball-like projectiles at revision ${HorizonCompat.ANDROID_REVISION.take(8)}): it is a $body underneath (its collision, pathfinding and melee), " +
                            "/summon ${e.id} does not exist (use /function $id:summon/$name), and its attributes are set by /attribute when it first ticks")
                }
                continue
            }
            val template = templateFor(e)
            if (template == null) {
                features += FeatureResult("Entities", "Entity type ${e.id}", FeatureStatus.UNSUPPORTED,
                    reason = "A ${e.vanillaBase} has no living template; thrown projectiles need one of the mod's items as their item (not resolvable from the jar)")
                continue
            }
            val allowed = HorizonCompat.templateAttributes.getValue(template)
            val attrs = e.attributes.filterKeys { it in allowed }
            val dropped = e.attributes.keys - allowed
            val decl = JsonTree.of("template" to template)
            if (attrs.isNotEmpty()) decl["attributes"] = LinkedHashMap(attrs)
            out.putJson("data/$id/horizon/entity_type/$name.json", decl)
            val why = buildList {
                add("copies $template's class: its size, collision and base behaviour")
                if (dropped.isNotEmpty()) add("attributes $template does not have were left out: ${dropped.joinToString()}")
            }.joinToString("; ")
            features += FeatureResult("Entities", "Entity type ${e.id}", FeatureStatus.PARTIAL, "content entity_type from $template", why)
            features += FeatureResult("Entities", "Attributes of ${e.id}",
                if (dropped.isEmpty() && e.attributes.isNotEmpty()) FeatureStatus.IMPLEMENTED else if (e.attributes.isEmpty()) FeatureStatus.PARTIAL else FeatureStatus.PARTIAL,
                "attributes ${attrs.entries.joinToString { "${it.key.removePrefix("minecraft:")}=${it.value}" }}",
                if (e.attributes.isEmpty()) "no default attributes were found in the bytecode; the template's apply" else dropped.joinToString { "$it not on the template" })
        }
    }

    private fun declareItemsAndBlocks() {
        val blocks = analysis.registrations.filter { it.kind == RegistryKind.BLOCK && it.id.startsWith("$id:") }
        val blockPaths = blocks.map { it.id.substringAfter(':') }.toSet()
        for (b in blocks) {
            val name = b.id.substringAfter(':')
            val info = analysis.blocks.firstOrNull { it.id == b.id }
            val hasModel = out.exists("assets/$id/blockstates/$name.json")
            out.putJson("data/$id/horizon/block/$name.json", JsonTree.of("template" to "minecraft:stone", "item" to true))
            features += FeatureResult("Blocks", "Block ${b.id}", FeatureStatus.PARTIAL, "content block from minecraft:stone",
                buildString {
                    append("hardness, sounds and shape are stone's (Java block properties are code)")
                    if (info?.hasBlockEntity == true) append("; its block entity logic needs a native mod")
                    if (!hasModel) append("; no blockstate file in the jar, it renders as missing")
                })
        }
        val eggs = analysis.registrations.filter { it.kind == RegistryKind.ITEM && it.id.startsWith("$id:") && it.id.substringAfter(':') !in blockPaths }
        for (i in eggs) {
            val name = i.id.substringAfter(':')
            val info = analysis.items.firstOrNull { it.id == i.id }
            val entity = analysis.entities.firstOrNull { name == "${it.id.substringAfter(':')}_spawn_egg" }
            val (template, extra, note) = when {
                entity != null || info?.vanillaBase == "SpawnEggItem" -> Triple("minecraft:zombie_spawn_egg",
                    entity?.let {
                        if (livingEntityTypes) JsonTree.of("minecraft:entity_data" to JsonTree.of("id" to it.id))
                        else JsonTree.of("minecraft:entity_data" to JsonTree.of("id" to bodyFor(isHostile(it)), "Tags" to listOf(creatureTag(id, it.id.substringAfter(':')))))
                    }, "spawn egg for ${entity?.id ?: "an unresolved entity"}")
                info?.vanillaBase == "SwordItem" -> Triple("minecraft:iron_sword", null, "iron sword's damage and durability")
                else -> Triple("minecraft:paper", null, "plain item; Java item behaviour (use, tooltip code) is not data")
            }
            val decl = JsonTree.of("template" to template)
            if (extra != null) decl["components"] = extra
            out.putJson("data/$id/horizon/item/$name.json", decl)
            features += FeatureResult("Items", "Item ${i.id}", FeatureStatus.PARTIAL, "content item from $template", note)
        }
    }

    /** Lang files must name each declared entity, or the game shows its raw key. */
    private fun ensureNames() {
        val path = "assets/$id/lang/en_us.json"
        val lang = if (out.exists(path)) JsonTree.obj(JsonTree.parse(out.readText(path))) ?: LinkedHashMap() else LinkedHashMap()
        var changed = false
        for (e in analysis.entities.filter { it.id.startsWith("$id:") }) {
            val key = "entity.$id.${e.id.substringAfter(':')}"
            if (!lang.containsKey(key)) { lang[key] = e.id.substringAfter(':').split('_').joinToString(" ") { it.replaceFirstChar(Char::uppercase) }; changed = true }
        }
        if (changed) out.putJson(path, lang)
    }

    fun writeManifest(extraCapabilities: List<String> = emptyList(), experimental: List<String> = emptyList()) {
        val m = analysis.metadata
        fun q(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ").trim() + "\""
        val caps = (listOf("registries") + extraCapabilities).distinct()
        val text = buildString {
            appendLine("# Generated by RustMod Forge from ${analysis.sourceFile} (${m.loader}, Minecraft ${m.minecraftVersion.ifEmpty { "?" }}).")
            appendLine("id = ${q(id)}")
            appendLine("name = ${q(m.name.ifBlank { id })}")
            appendLine("version = ${q(m.version.ifBlank { "0.0.0" })}")
            appendLine("description = ${q("Reconstructed for Horizon by RustMod Forge. ${m.description}".take(400))}")
            appendLine("authors = [${m.authors.joinToString(", ") { q(it) }}]")
            appendLine("api = \"0.2\"")
            appendLine("side = \"both\"")
            appendLine("capabilities = [${caps.joinToString(", ") { q(it) }}]")
            if (experimental.isNotEmpty()) appendLine("experimental = [${experimental.joinToString(", ") { q(it) }}]")
            if (extraNamespaces.isNotEmpty()) appendLine("namespaces = [${extraNamespaces.joinToString(", ") { q(it) }}]")
        }
        out.putText("horizon-mod.toml", text)
    }

    private fun summarize() {
        val kinds = analysis.resources.groupBy { it.kind }
        fun count(k: ResourceKind) = kinds[k]?.size ?: 0
        fun row(name: String, k: ResourceKind, route: String) {
            val n = count(k)
            if (n == 0) return
            val lost = skipped.values.flatten().count { p -> analysis.resources.firstOrNull { it.path == p }?.kind == k }
            val status = if (lost == 0) FeatureStatus.IMPLEMENTED else if (lost < n) FeatureStatus.PARTIAL else FeatureStatus.UNSUPPORTED
            features += FeatureResult("Assets and data", "$name ($n)", status, route, if (lost > 0) "$lost left out, see warnings" else "")
        }
        row("Textures", ResourceKind.TEXTURE, "copied")
        row("Block and item models", ResourceKind.BLOCK_MODEL, "copied, 26.3 typed values")
        row("Block states", ResourceKind.BLOCKSTATE, "copied")
        row("Sounds", ResourceKind.SOUND, "copied with sounds.json")
        row("Languages", ResourceKind.LANG, "copied")
        row("Recipes", ResourceKind.RECIPE, "upgraded to 26.3 ingredients")
        row("Loot tables", ResourceKind.LOOT_TABLE, "upgraded to 26.3 conditions and modifiers")
        row("Advancements", ResourceKind.ADVANCEMENT, "copied, criteria upgraded")
        row("Tags", ResourceKind.TAG, "copied, folders renamed for 1.21+")
        row("Functions", ResourceKind.FUNCTION, "copied")
        row("Structures", ResourceKind.STRUCTURE_NBT, "copied")
        row("Biome modifiers", ResourceKind.BIOME_MODIFIER, "copied (Horizon reads NeoForge/Forge biome modifiers)")
        row("World generation", ResourceKind.WORLDGEN, "copied")
        if (count(ResourceKind.PARTICLE_DEFINITION) > 0) features += FeatureResult("Assets and data", "Particle definitions (${count(ResourceKind.PARTICLE_DEFINITION)})",
            FeatureStatus.PARTIAL, "files copied", "custom particle types are registered in code; only vanilla particles can be spawned without a native mod")
        if (count(ResourceKind.SHADER) > 0) features += FeatureResult("Assets and data", "Shaders (${count(ResourceKind.SHADER)})", FeatureStatus.UNSUPPORTED,
            reason = "GLSL core shaders do not run on Horizon's wgpu renderer")
        if (analysis.metadata.iconPath.isNotEmpty()) features += FeatureResult("Assets and data", "Mod icon", FeatureStatus.NOT_APPLICABLE,
            "kept for the resource pack's pack.png",
            "a .hmod may hold only its manifest, assets/ and data/, so the Mods list shows no icon for a mod installed from a file; " +
                "the launcher shows icons for registry mods and for packs")
        if (recipesKept.isNotEmpty()) warnings += "${recipesKept.size} recipes are custom types or have conditions and were copied unchanged: ${recipesKept.take(5).joinToString()}"
        for ((reason, paths) in skipped) warnings += "Left out ${paths.size} file(s): $reason — e.g. ${paths.take(3).joinToString()}"
        warnings += "Copied $copied asset/data files into the content mod"
    }
}
