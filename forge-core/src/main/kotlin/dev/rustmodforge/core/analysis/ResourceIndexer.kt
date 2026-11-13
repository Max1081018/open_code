package dev.rustmodforge.core.analysis

import dev.rustmodforge.core.archive.ArchiveEntry
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.model.ResourceRef

/** Classifies every archive entry by what it is to Minecraft (and so to Horizon). */
object ResourceIndexer {
    private val metadataFiles = setOf(
        "fabric.mod.json", "quilt.mod.json", "mcmod.info", "pack.mcmeta", "pack.png",
        "META-INF/mods.toml", "META-INF/neoforge.mods.toml", "META-INF/MANIFEST.MF", "META-INF/accesstransformer.cfg",
    )

    fun index(entries: List<ArchiveEntry>, mixinConfigs: Collection<String>): List<ResourceRef> =
        entries.map { e -> classify(e.path, mixinConfigs).let { (kind, ns) -> ResourceRef(e.path, kind, ns, e.size) } }

    fun classify(path: String, mixinConfigs: Collection<String> = emptyList()): Pair<ResourceKind, String> {
        if (path.endsWith(".class")) return ResourceKind.CLASS to ""
        if (path in metadataFiles) return ResourceKind.METADATA to ""
        if ((path.startsWith("META-INF/jars/") || path.startsWith("META-INF/jarjar/")) && path.endsWith(".jar")) return ResourceKind.NESTED_JAR to ""
        if (path in mixinConfigs || (!path.contains('/') && path.contains("mixins") && path.endsWith(".json"))) return ResourceKind.MIXIN_CONFIG to ""
        if (path.endsWith(".accesswidener") || path.endsWith(".aw")) return ResourceKind.ACCESS_WIDENER to ""
        if (path.startsWith("META-INF/")) return ResourceKind.METADATA to ""
        val parts = path.split('/')
        if (parts.size < 3) return ResourceKind.OTHER to ""
        val ns = parts[1]
        val rest = parts.drop(2).joinToString("/")
        val dir = parts[2]
        return when (parts[0]) {
            "assets" -> assetKind(dir, rest, path) to ns
            "data" -> dataKind(dir, rest, path) to ns
            else -> ResourceKind.OTHER to ""
        }
    }

    private fun assetKind(dir: String, rest: String, path: String): ResourceKind = when {
        path.endsWith(".geo.json") -> ResourceKind.GEO_MODEL
        path.endsWith(".animation.json") || (dir == "animations" && path.endsWith(".json")) -> ResourceKind.GECKO_ANIMATION
        // GeckoLib 5 moved its files under assets/<ns>/geckolib/.
        dir == "geckolib" && rest.startsWith("geckolib/models/") -> ResourceKind.GEO_MODEL
        dir == "geckolib" && rest.startsWith("geckolib/animations/") -> ResourceKind.GECKO_ANIMATION
        dir == "geo" && path.endsWith(".json") -> ResourceKind.GEO_MODEL
        dir == "animation_controllers" -> ResourceKind.BEDROCK_ANIMATION_CONTROLLER
        dir == "textures" && path.endsWith(".png") -> ResourceKind.TEXTURE
        dir == "textures" && path.endsWith(".mcmeta") -> ResourceKind.TEXTURE_META
        dir == "models" && path.endsWith(".json") -> ResourceKind.BLOCK_MODEL
        dir == "items" && path.endsWith(".json") -> ResourceKind.ITEM_MODEL_DEFINITION
        dir == "blockstates" -> ResourceKind.BLOCKSTATE
        rest == "sounds.json" -> ResourceKind.SOUND_DEFINITIONS
        dir == "sounds" && (path.endsWith(".ogg") || path.endsWith(".wav") || path.endsWith(".mp3")) -> ResourceKind.SOUND
        dir == "lang" -> ResourceKind.LANG
        dir == "particles" -> ResourceKind.PARTICLE_DEFINITION
        dir == "shaders" || dir == "post_effect" -> ResourceKind.SHADER
        dir == "font" -> ResourceKind.FONT
        dir == "atlases" -> ResourceKind.ATLAS
        else -> ResourceKind.OTHER_ASSET
    }

    private fun dataKind(dir: String, rest: String, path: String): ResourceKind = when {
        dir == "recipe" || dir == "recipes" -> ResourceKind.RECIPE
        dir == "loot_table" || dir == "loot_tables" -> ResourceKind.LOOT_TABLE
        dir == "advancement" || dir == "advancements" -> ResourceKind.ADVANCEMENT
        dir == "tags" -> ResourceKind.TAG
        dir == "worldgen" -> ResourceKind.WORLDGEN
        (dir == "structure" || dir == "structures") && path.endsWith(".nbt") -> ResourceKind.STRUCTURE_NBT
        (dir == "neoforge" || dir == "forge" || dir == "fabric") && rest.contains("biome_modifier") -> ResourceKind.BIOME_MODIFIER
        (dir == "function" || dir == "functions") && path.endsWith(".mcfunction") -> ResourceKind.FUNCTION
        dir == "damage_type" -> ResourceKind.DAMAGE_TYPE
        dir == "predicate" || dir == "predicates" -> ResourceKind.PREDICATE
        dir == "item_modifier" || dir == "item_modifiers" -> ResourceKind.ITEM_MODIFIER
        else -> ResourceKind.OTHER_DATA
    }
}
