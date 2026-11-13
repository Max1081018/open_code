package dev.rustmodforge.core.target

import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.report.FeatureResult
import dev.rustmodforge.core.report.FeatureStatus
import dev.rustmodforge.core.util.JsonTree

/**
 * A mod's changes to **vanilla's own** files. A content mod may not hold them (its files live in
 * its own namespaces), so a jar that replaces vanilla sounds, textures, models, languages, loot
 * tables or recipes would convert to a `.hmod` that does nothing at all — which is what a
 * "better sounds" style mod is made of.
 *
 * Horizon reads those the way Minecraft does: as a **resource pack** (`resourcepacks/`, which
 * merges `assets/minecraft/sounds.json` and the rest over vanilla) and as a **data pack**
 * (`<world>/datapacks/`). This writes those two packs beside the content mod, so the parts of a
 * mod that are really pack content actually apply in the game.
 */
class PackGenerator(
    private val analysis: ModAnalysis,
    private val archive: SafeArchive,
    private val out: OutputTree,
    private val kind: PackKind,
    private val modId: String,
    private val ownNamespaces: Set<String>,
    /** True when no content mod is written, so the pack must carry the mod's own files too. */
    private val packIsTheWholeMod: Boolean,
) {
    /**
     * A pack declares a **range** of formats rather than one number, because the installed
     * launcher decides what it reads and a pack whose only format is newer than the build is
     * marked too new and never applies. The engine's own rules
     * (`packs::validate_pack_range`): with a minimum at or below `lastPreMinor` the pack must
     * also carry `supported_formats`, whose top is either the maximum or `lastPreMinor`, and
     * `pack_format` must lie inside the range. `main` is therefore inside the old window so an
     * older build reading only `pack_format` and `supported_formats` accepts it too, while
     * `max` reaches past the current format for new builds.
     */
    enum class PackKind(val root: String, val label: String, val format: Int, val main: Int, val min: Int, val max: Int, val lastPreMinor: Int) {
        RESOURCE("assets", "resource pack", 97, main = 64, min = 15, max = 99, lastPreMinor = 64),
        DATA("data", "data pack", 121, main = 81, min = 15, max = 140, lastPreMinor = 81),
    }

    val features = ArrayList<FeatureResult>()
    val warnings = ArrayList<String>()
    private val pathOk = Regex("(assets|data)/[a-z0-9_.-]+(/[a-z0-9_.-]+)+")
    private var copied = 0
    private val skipped = LinkedHashMap<String, MutableList<String>>()

    /** The jar's files that replace vanilla's own, which only a pack can carry. */
    private val overrides: List<String> = analysis.resources.filter { r ->
        val p = r.path.split('/')
        p.size >= 3 && p[0] == kind.root && p[1] == "minecraft" && when (kind) {
            // Atlas sources and vanilla tags merge from a content mod, so they stay there.
            PackKind.RESOURCE -> !r.path.removePrefix("assets/minecraft/").startsWith("atlases/")
            PackKind.DATA -> !DataUpgrader.renamePath(r.path).removePrefix("data/minecraft/").startsWith("tags/")
        }
    }.map { it.path }

    /** Nothing of vanilla's is touched: the content mod covers this jar on its own. */
    fun isEmpty() = overrides.isEmpty()

    /**
     * Writes the pack. Besides vanilla's files it carries the mod's own files of the same root
     * when they are referenced from an override (a vanilla `sounds.json` pointing at the mod's
     * `.ogg` files), so the pack resolves on its own.
     */
    fun generate() {
        val referenced = referencedNamespaces()
        val include = analysis.resources.filter { r ->
            val p = r.path.split('/')
            if (p.size < 3 || p[0] != kind.root) return@filter false
            val ns = p[1]
            when {
                r.path in overrides -> true
                ns == "minecraft" -> false
                ns !in ownNamespaces -> false
                kind == PackKind.DATA && p.getOrNull(2) == "horizon" -> false // content-mod declarations
                else -> packIsTheWholeMod || ns in referenced
            }
        }
        for (r in include) {
            val target = DataUpgrader.renamePath(r.path)
            if (!target.matches(pathOk)) { skip("paths vanilla does not read (upper case or invalid characters)", r.path); continue }
            if (kind == PackKind.DATA && r.kind == ResourceKind.WORLDGEN) {
                skip("world generation JSON (1.x worldgen is not 26.3's; run Horizon's upgrade-datapack on the original)", r.path); continue
            }
            if (r.kind == ResourceKind.LANG && r.path.endsWith(".lang")) {
                out.putJson(target.removeSuffix(".lang").lowercase() + ".json", legacyLang(archive.readText(r.path))); copied++; continue
            }
            if (r.path.endsWith(".json") || r.path.endsWith(".mcmeta")) {
                val parsed = runCatching { JsonTree.parse(archive.readText(r.path)) }.getOrNull()
                if (parsed == null) { skip("JSON that does not parse", r.path); continue }
                upgrade(r.kind, parsed, r.path)
                out.putJson(target, parsed)
            } else {
                out.copyFrom(archive, r.path, target)
            }
            copied++
        }
        writeMeta()
        summarize()
    }

    /** Namespaces the overridden files point at, so the pack brings those files along. */
    private fun referencedNamespaces(): Set<String> {
        val re = Regex("\"([a-z0-9_.-]+):[a-z0-9_./-]+\"")
        val out = HashSet<String>()
        for (p in overrides.filter { it.endsWith(".json") || it.endsWith(".mcmeta") }) {
            val text = runCatching { archive.readText(p) }.getOrNull() ?: continue
            re.findAll(text).forEach { out += it.groupValues[1] }
        }
        return out - "minecraft"
    }

    private fun upgrade(resource: ResourceKind, v: Any?, path: String) {
        when (resource) {
            ResourceKind.RECIPE -> JsonTree.obj(v)?.let { DataUpgrader.upgradeRecipe(it) }
            ResourceKind.LOOT_TABLE -> DataUpgrader.upgradeLoot(v)
            ResourceKind.ADVANCEMENT -> JsonTree.obj(v)?.let { DataUpgrader.upgradeAdvancement(it) }
            ResourceKind.BLOCK_MODEL, ResourceKind.BLOCKSTATE, ResourceKind.ITEM_MODEL_DEFINITION -> DataUpgrader.upgradeAssets(v)
            else -> {}
        }
        if (path.startsWith("data/")) DataUpgrader.renameIds(v)
    }

    private fun legacyLang(text: String): Map<String, String> = text.lines().mapNotNull { line ->
        val l = line.trim()
        if (l.isEmpty() || l.startsWith("#") || !l.contains('=')) null else l.substringBefore('=') to l.substringAfter('=')
    }.toMap()

    /**
     * `pack.mcmeta` in the shape this Horizon validates (`packs::validate_pack_range`): past
     * format 64 (resources) and 81 (data) `min_format` and `max_format` are mandatory and
     * `supported_formats` is refused.
     */
    private fun writeMeta() {
        val m = analysis.metadata
        val description = "${m.name.ifBlank { modId }} ${m.version} — ${kind.label} by RustMod Forge"
        out.putJson("pack.mcmeta", JsonTree.of(
            "pack" to JsonTree.of(
                "description" to description.take(256),
                "pack_format" to kind.main,
                "supported_formats" to listOf(kind.min, kind.lastPreMinor),
                "min_format" to kind.min,
                "max_format" to kind.max,
            ),
        ))
        features += FeatureResult("Assets and data", "${kind.label.replaceFirstChar(Char::uppercase)} version range", FeatureStatus.IMPLEMENTED,
            "declares formats ${kind.min} to ${kind.max}",
            "so the pack applies whatever Horizon build is installed, not only the newest")
        // A pack's icon is its own pack.png; a .hmod may hold no such file, so this is where a
        // converted mod keeps its logo.
        val icon = m.iconPath.takeIf { it.isNotEmpty() && archive.contains(it) }
        if (icon != null) {
            out.copyFrom(archive, icon, "pack.png")
            features += FeatureResult("Assets and data", "${kind.label.replaceFirstChar(Char::uppercase)} icon", FeatureStatus.IMPLEMENTED,
                "the mod's ${icon.substringAfterLast('/')} as the pack's pack.png")
        }
    }

    private fun skip(reason: String, path: String) { skipped.getOrPut(reason) { ArrayList() } += path }

    private fun summarize() {
        val byKind = overrides.mapNotNull { p -> analysis.resources.firstOrNull { it.path == p } }.groupBy { it.kind }
        val names = mapOf(
            ResourceKind.SOUND to "Vanilla sounds replaced", ResourceKind.SOUND_DEFINITIONS to "Vanilla sound events (sounds.json)",
            ResourceKind.TEXTURE to "Vanilla textures replaced", ResourceKind.BLOCK_MODEL to "Vanilla models replaced",
            ResourceKind.ITEM_MODEL_DEFINITION to "Vanilla item models replaced", ResourceKind.BLOCKSTATE to "Vanilla block states replaced",
            ResourceKind.LANG to "Vanilla text replaced", ResourceKind.FONT to "Vanilla fonts replaced",
            ResourceKind.RECIPE to "Vanilla recipes changed", ResourceKind.LOOT_TABLE to "Vanilla loot tables changed",
            ResourceKind.ADVANCEMENT to "Vanilla advancements changed", ResourceKind.FUNCTION to "Functions",
            ResourceKind.PARTICLE_DEFINITION to "Vanilla particles changed",
        )
        val lost = skipped.values.flatten().toSet()
        for ((k, list) in byKind) {
            val label = names[k] ?: "Vanilla ${k.name.lowercase().replace('_', ' ')} changed"
            val dropped = list.count { it.path in lost }
            features += FeatureResult(
                "Assets and data", "$label (${list.size})",
                if (dropped == 0) FeatureStatus.IMPLEMENTED else if (dropped < list.size) FeatureStatus.PARTIAL else FeatureStatus.UNSUPPORTED,
                "carried in the ${kind.label}, which Horizon applies over vanilla",
                if (dropped == 0) "" else "$dropped left out, see warnings",
            )
        }
        if (kind == PackKind.RESOURCE && byKind.keys.any { it == ResourceKind.SHADER }) {
            features += FeatureResult("Assets and data", "Vanilla core shaders replaced", FeatureStatus.UNSUPPORTED,
                reason = "GLSL core shaders do not run on Horizon's wgpu renderer")
        }
        for ((reason, paths) in skipped) warnings += "[${kind.label}] left out ${paths.size} file(s): $reason — e.g. ${paths.take(3).joinToString()}"
        warnings += "[${kind.label}] carried $copied file(s), ${overrides.size} of them vanilla's own"
    }
}
