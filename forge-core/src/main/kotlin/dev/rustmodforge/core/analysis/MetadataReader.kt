package dev.rustmodforge.core.analysis

import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.model.DependencyKind
import dev.rustmodforge.core.model.DependencySpec
import dev.rustmodforge.core.model.Loader
import dev.rustmodforge.core.model.ModMetadata
import dev.rustmodforge.core.util.MiniToml
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * A loader's metadata format. New loaders are added by implementing this and listing it in
 * [MetadataReader.plugins]; the first plugin that [accepts] an archive reads it.
 */
interface LoaderMetadataPlugin {
    val loader: Loader
    fun accepts(archive: SafeArchive): Boolean
    fun read(archive: SafeArchive, warnings: MutableList<String>): ModMetadata
}

object MetadataReader {
    val lenientJson = Json { ignoreUnknownKeys = true; isLenient = true; allowTrailingComma = true }

    val plugins: List<LoaderMetadataPlugin> = listOf(
        FabricPlugin(Loader.QUILT, "quilt.mod.json"),
        FabricPlugin(Loader.FABRIC, "fabric.mod.json"),
        ForgeTomlPlugin(Loader.NEOFORGE, "META-INF/neoforge.mods.toml"),
        ForgeTomlPlugin(Loader.FORGE, "META-INF/mods.toml"),
        LegacyForgePlugin,
        PackPlugin,
    )

    fun read(archive: SafeArchive, warnings: MutableList<String>): ModMetadata {
        for (p in plugins) if (p.accepts(archive)) return p.read(archive, warnings)
        warnings += "No mod metadata found (fabric.mod.json, mods.toml, neoforge.mods.toml, mcmod.info or pack.mcmeta)"
        val stem = archive.source.nameWithoutExtension
        return ModMetadata(modId = sanitizeId(stem), name = stem, version = "0.0.0", loader = Loader.UNKNOWN)
    }

    fun manifestAttributes(archive: SafeArchive): Map<String, String> {
        if (!archive.contains("META-INF/MANIFEST.MF")) return emptyMap()
        val out = LinkedHashMap<String, String>()
        var lastKey: String? = null
        for (line in archive.readText("META-INF/MANIFEST.MF").lines()) {
            if (line.startsWith(" ") && lastKey != null) {
                out[lastKey] = out[lastKey] + line.substring(1)
            } else {
                val i = line.indexOf(':')
                if (i > 0) { lastKey = line.substring(0, i).trim(); out[lastKey] = line.substring(i + 1).trim() }
            }
        }
        return out
    }

    /** `[a-z0-9_]{1,64}` as Horizon's manifest requires. */
    fun sanitizeId(raw: String): String {
        val s = raw.lowercase().map { if (it in 'a'..'z' || it in '0'..'9' || it == '_') it else '_' }.joinToString("")
            .replace(Regex("_+"), "_").trim('_')
        val id = if (s.isEmpty()) "converted_mod" else s
        return (if (id[0].isDigit()) "m_$id" else id).take(64)
    }

    private fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.contentOrNull

    private class FabricPlugin(override val loader: Loader, val file: String) : LoaderMetadataPlugin {
        override fun accepts(archive: SafeArchive) = archive.contains(file)
        override fun read(archive: SafeArchive, warnings: MutableList<String>): ModMetadata {
            val root = lenientJson.parseToJsonElement(archive.readText(file)) as JsonObject
            // Quilt nests everything under quilt_loader.
            val q = (root["quilt_loader"] as? JsonObject)
            val meta = q?.get("metadata") as? JsonObject
            val id = (q?.get("id") ?: root["id"]).str() ?: archive.source.nameWithoutExtension
            val version = (q?.get("version") ?: root["version"]).str() ?: "0.0.0"
            val name = (meta?.get("name") ?: root["name"]).str() ?: id
            val desc = (meta?.get("description") ?: root["description"]).str() ?: ""
            val authors = when (val a = meta?.get("contributors") ?: root["authors"]) {
                is JsonArray -> a.mapNotNull { (it as? JsonObject)?.get("name").str() ?: it.str() }
                is JsonObject -> a.keys.toList()
                else -> emptyList()
            }
            val license = when (val l = meta?.get("license") ?: root["license"]) {
                is JsonArray -> l.mapNotNull { it.str() }.joinToString(", ")
                else -> l.str() ?: ""
            }
            val deps = ArrayList<DependencySpec>()
            fun addMap(key: String, kind: DependencyKind) {
                val m = root[key] as? JsonObject ?: return
                for ((dep, v) in m) {
                    val range = when (v) {
                        is JsonArray -> v.mapNotNull { it.str() }.joinToString(" || ")
                        else -> v.str() ?: "*"
                    }
                    deps += DependencySpec(dep, range, kind, declaredIn = file)
                }
            }
            addMap("depends", DependencyKind.REQUIRED)
            addMap("recommends", DependencyKind.OPTIONAL)
            addMap("suggests", DependencyKind.OPTIONAL)
            addMap("breaks", DependencyKind.INCOMPATIBLE)
            addMap("conflicts", DependencyKind.INCOMPATIBLE)
            (q?.get("depends") as? JsonArray)?.forEach { d ->
                when (d) {
                    is JsonPrimitive -> deps += DependencySpec(d.content, "*", DependencyKind.REQUIRED, declaredIn = file)
                    is JsonObject -> deps += DependencySpec(
                        d["id"].str() ?: return@forEach,
                        d["versions"].let { v -> if (v is JsonArray) v.mapNotNull { it.str() }.joinToString(" || ") else v.str() ?: "*" },
                        if (d["optional"]?.jsonPrimitive?.contentOrNull == "true") DependencyKind.OPTIONAL else DependencyKind.REQUIRED,
                        declaredIn = file,
                    )
                    else -> {}
                }
            }
            val jars = (root["jars"] as? JsonArray)?.mapNotNull { (it as? JsonObject)?.get("file").str() } ?: emptyList()
            jars.forEach { deps += DependencySpec(it.substringAfterLast('/').removeSuffix(".jar"), "*", DependencyKind.EMBEDDED, declaredIn = file) }
            val entrypoints = ((q?.get("entrypoints") ?: root["entrypoints"]) as? JsonObject)?.flatMap { (side, v) ->
                val list = if (v is JsonArray) v.toList() else listOf(v)
                list.mapNotNull { e -> ((e as? JsonObject)?.get("value") ?: e).str()?.let { "$side:$it" } }
            } ?: emptyList()
            val mixins = when (val m = root["mixins"] ?: root["mixin"]) {
                is JsonArray -> m.mapNotNull { ((it as? JsonObject)?.get("config") ?: it).str() }
                else -> listOfNotNull(m.str())
            }
            val aw = listOfNotNull(root["accessWidener"].str())
            val mc = deps.firstOrNull { it.id == "minecraft" }?.versionRange ?: ""
            return ModMetadata(
                modId = id, name = name, version = version, description = desc, authors = authors,
                license = license, loader = loader, minecraftVersion = mc,
                loaderVersion = deps.firstOrNull { it.id == "fabricloader" || it.id == "quilt_loader" }?.versionRange ?: "",
                dependencies = deps, entrypoints = entrypoints, mixinConfigs = mixins, accessWideners = aw,
                embeddedJars = jars, declaredModIds = listOf(id),
            )
        }
    }

    private class ForgeTomlPlugin(override val loader: Loader, val file: String) : LoaderMetadataPlugin {
        override fun accepts(archive: SafeArchive) = archive.contains(file)

        @Suppress("UNCHECKED_CAST")
        override fun read(archive: SafeArchive, warnings: MutableList<String>): ModMetadata {
            val toml = MiniToml.parse(archive.readText(file))
            val manifest = manifestAttributes(archive)
            val mods = (toml["mods"] as? List<Map<String, Any?>>).orEmpty()
            val first = mods.firstOrNull() ?: emptyMap()
            val modId = first["modId"]?.toString() ?: archive.source.nameWithoutExtension
            fun expand(v: String?) = v?.replace("\${file.jarVersion}", manifest["Implementation-Version"] ?: "0.0.0")
            val deps = ArrayList<DependencySpec>()
            val depTable = toml["dependencies"] as? Map<String, Any?> ?: emptyMap()
            var neoForgeDeclared = false
            for ((owner, list) in depTable) {
                for (d in (list as? List<Map<String, Any?>>).orEmpty()) {
                    val depId = d["modId"]?.toString() ?: continue
                    if (depId == "neoforge") neoForgeDeclared = true
                    val type = d["type"]?.toString()?.lowercase()
                    val kind = when {
                        type == "incompatible" || type == "discouraged" -> DependencyKind.INCOMPATIBLE
                        type == "optional" -> DependencyKind.OPTIONAL
                        type == "required" -> DependencyKind.REQUIRED
                        d["mandatory"] == false -> DependencyKind.OPTIONAL
                        else -> DependencyKind.REQUIRED
                    }
                    deps += DependencySpec(depId, d["versionRange"]?.toString() ?: "*", kind,
                        d["side"]?.toString()?.lowercase() ?: "both", "$file ($owner)")
                }
            }
            val mixins = ((toml["mixins"] as? List<Map<String, Any?>>)?.mapNotNull { it["config"]?.toString() } ?: emptyList()) +
                (manifest["MixinConfigs"]?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList())
            val jarJar = archive.entries.map { it.path }.filter { it.startsWith("META-INF/jarjar/") && it.endsWith(".jar") }
            jarJar.forEach { deps += DependencySpec(it.substringAfterLast('/').removeSuffix(".jar"), "*", DependencyKind.EMBEDDED, declaredIn = "META-INF/jarjar") }
            val mc = deps.firstOrNull { it.id == "minecraft" }?.versionRange ?: ""
            val actualLoader = if (loader == Loader.FORGE && neoForgeDeclared) Loader.NEOFORGE else loader
            return ModMetadata(
                modId = modId,
                name = first["displayName"]?.toString() ?: modId,
                version = expand(first["version"]?.toString()) ?: "0.0.0",
                description = first["description"]?.toString()?.trim() ?: "",
                authors = first["authors"]?.toString()?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList(),
                license = toml["license"]?.toString() ?: "",
                loader = actualLoader,
                minecraftVersion = mc,
                loaderVersion = toml["loaderVersion"]?.toString() ?: "",
                dependencies = deps,
                entrypoints = emptyList(),
                mixinConfigs = mixins.distinct(),
                accessWideners = listOfNotNull("META-INF/accesstransformer.cfg".takeIf { archive.contains(it) }),
                embeddedJars = jarJar,
                declaredModIds = mods.mapNotNull { it["modId"]?.toString() },
            )
        }
    }

    private object LegacyForgePlugin : LoaderMetadataPlugin {
        override val loader = Loader.LEGACY_FORGE
        override fun accepts(archive: SafeArchive) = archive.contains("mcmod.info")
        override fun read(archive: SafeArchive, warnings: MutableList<String>): ModMetadata {
            val el = lenientJson.parseToJsonElement(archive.readText("mcmod.info"))
            val list = (el as? JsonArray) ?: ((el as? JsonObject)?.get("modList") as? JsonArray) ?: JsonArray(emptyList())
            val first = list.firstOrNull() as? JsonObject
            val id = first?.get("modid").str() ?: archive.source.nameWithoutExtension
            warnings += "Legacy Forge (pre-1.13) mod: its code targets a Minecraft that differs from Horizon's 26.3 in almost every API"
            return ModMetadata(
                modId = id, name = first?.get("name").str() ?: id, version = first?.get("version").str() ?: "0.0.0",
                description = first?.get("description").str() ?: "",
                authors = (first?.get("authorList") as? JsonArray)?.mapNotNull { it.str() } ?: emptyList(),
                loader = loader, minecraftVersion = first?.get("mcversion").str() ?: "",
                declaredModIds = listOf(id),
            )
        }
    }

    private object PackPlugin : LoaderMetadataPlugin {
        override val loader = Loader.DATA_OR_RESOURCE_PACK
        override fun accepts(archive: SafeArchive) = archive.contains("pack.mcmeta")
        override fun read(archive: SafeArchive, warnings: MutableList<String>): ModMetadata {
            val el = runCatching { lenientJson.parseToJsonElement(archive.readText("pack.mcmeta")) as JsonObject }.getOrNull()
            val pack = el?.get("pack") as? JsonObject
            val format = pack?.get("pack_format").str()?.toIntOrNull()
            val stem = archive.source.nameWithoutExtension
            return ModMetadata(
                modId = sanitizeId(stem), name = stem, version = "1.0.0",
                description = (pack?.get("description") as? JsonPrimitive)?.contentOrNull ?: "",
                loader = loader, minecraftVersion = format?.let { PackFormats.describe(it) } ?: "",
            )
        }
    }
}

/** Pack format numbers to the Java versions that use them; a hint, since mod jars mix both kinds. */
object PackFormats {
    private val data = mapOf(
        4 to "1.13–1.14.4", 5 to "1.15–1.16.1", 6 to "1.16.2–1.16.5", 7 to "1.17.x", 8 to "1.18–1.18.1",
        9 to "1.18.2", 10 to "1.19–1.19.3", 12 to "1.19.4", 15 to "1.20–1.20.1", 18 to "1.20.2",
        26 to "1.20.3–1.20.4", 41 to "1.20.5–1.20.6", 48 to "1.21–1.21.1", 57 to "1.21.2–1.21.3",
        61 to "1.21.4", 71 to "1.21.5", 80 to "1.21.6", 81 to "1.21.7–1.21.8",
    )
    fun describe(format: Int) = data[format]?.let { "pack_format $format (data pack: $it)" } ?: "pack_format $format"
}
