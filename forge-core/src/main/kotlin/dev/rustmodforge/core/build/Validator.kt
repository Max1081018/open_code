package dev.rustmodforge.core.build

import dev.rustmodforge.core.compat.HorizonCompat
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.util.JsonTree
import dev.rustmodforge.core.util.MiniToml
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

/** A problem a check found; errors stop the export, warnings are reported. */
data class Issue(val error: Boolean, val path: String, val message: String) {
    override fun toString() = "${if (error) "error" else "warning"}: $path: $message"
}

/**
 * Checks a packed mod against the rules Horizon's readers apply (docs/api/mod-files.md,
 * `horizon_mods::manifest`) and that every file reference inside it resolves. It is RustMod
 * Forge's own re-implementation; where Horizon's `cargo horizon-mod check` is available (the
 * desktop/CI build), the pipeline runs that too.
 */
object Validator {
    private val idRe = Regex("[a-z0-9_]{1,64}")
    private val nsRe = Regex("[a-z0-9_.-]{1,64}")
    private val contentPathRe = Regex("(assets|data)/[a-z0-9_.-]+(/[a-z0-9_.-]+)+")
    private val manifestKeys = setOf("id", "name", "version", "description", "authors", "api", "side", "capabilities", "namespaces", "experimental")
    private val capabilities = setOf("game-read", "chat", "hud", "storage", "command", "registries", "ui", "render", "input", "players", "world", "recipes")
    private val experimentalCaps = setOf("ui", "render", "input", "recipes")
    private val serverCaps = setOf("storage", "players", "world")
    private val reserved = setOf("minecraft", "c", "horizon")

    /** Vanilla command roots Horizon's command tree has (`horizon-command`'s vanilla tree). */
    private val commandRoots = setOf("advancement", "attribute", "bossbar", "clear", "clone", "damage", "data", "datapack", "defaultgamemode",
        "difficulty", "effect", "enchant", "execute", "experience", "xp", "fill", "fillbiome", "forceload", "function", "gamemode", "gamerule", "give",
        "item", "kill", "list", "locate", "loot", "me", "msg", "tell", "w", "particle", "place", "playsound", "random", "recipe", "reload", "return",
        "ride", "say", "schedule", "scoreboard", "seed", "setblock", "setworldspawn", "spawnpoint", "spectate", "spreadplayers", "stopsound", "summon",
        "tag", "team", "teammsg", "tm", "teleport", "tp", "tellraw", "time", "title", "trigger", "weather", "worldborder")

    fun validateHmod(file: File, target: TargetId): List<Issue> {
        val issues = ArrayList<Issue>()
        fun err(p: String, m: String) { issues += Issue(true, p, m) }
        fun warn(p: String, m: String) { issues += Issue(false, p, m) }
        if (file.length() > 64L shl 20) err(file.name, "larger than the 64 MiB a registry file may be")
        ZipFile(file).use { zip ->
            val entries = zip.entries().toList().filter { !it.isDirectory }
            val names = entries.map { it.name }
            val set = HashSet<String>()
            for (e in entries) {
                val n = e.name
                if (!set.add(n)) err(n, "listed twice")
                if (n.startsWith("/") || n.contains('\\') || n.contains(':') || n.split('/').any { it.isEmpty() || it == "." || it == ".." }) err(n, "not a relative /-separated path")
                if (e.method != ZipEntry.STORED && e.method != ZipEntry.DEFLATED) err(n, "compression method ${e.method} is not stored or deflate")
                val top = n.substringBefore('/')
                if (n != "horizon-mod.toml" && n != "mod.wasm" && top != "assets" && top != "data") err(n, "a .hmod may hold only horizon-mod.toml, mod.wasm, assets/ and data/")
                if ((top == "assets" || top == "data") && !n.matches(contentPathRe)) err(n, "content paths are assets/ or data/ then lower-case [a-z0-9_.-] parts")
                if (e.size > 16L shl 20) err(n, "larger than 16 MiB")
            }
            if (entries.size > 65_536) err(file.name, "more than 65,536 files")
            if (entries.sumOf { it.size } > 512L shl 20) err(file.name, "more than 512 MiB of content")
            val manifestEntry = zip.getEntry("horizon-mod.toml")
            if (manifestEntry == null) { err("horizon-mod.toml", "missing"); return issues }
            val manifest = try { MiniToml.parse(zip.getInputStream(manifestEntry).readBytes().decodeToString()) } catch (e: Exception) {
                err("horizon-mod.toml", "does not parse: ${e.message}"); return issues
            }
            (manifest.keys - manifestKeys).forEach { err("horizon-mod.toml", "unknown key $it (Horizon refuses unknown keys)") }
            if (target == TargetId.HORIZON_DESKTOP && manifest.containsKey("experimental")) err("horizon-mod.toml", "upstream Horizon has no `experimental` key")
            val id = manifest["id"] as? String ?: ""
            if (!id.matches(idRe)) err("horizon-mod.toml", "id \"$id\" is not [a-z0-9_]{1,64}")
            for (k in listOf("name", "version")) if ((manifest[k] as? String).isNullOrBlank()) err("horizon-mod.toml", "$k is required")
            val api = manifest["api"] as? String ?: ""
            val apis = HorizonCompat.profile(target).contentApis
            if (api !in apis) err("horizon-mod.toml", "api \"$api\" is not one this target runs (${apis.joinToString()})")
            val caps = (manifest["capabilities"] as? List<*>)?.map { it.toString() } ?: emptyList()
            caps.filter { it !in capabilities }.forEach { err("horizon-mod.toml", "unknown capability $it") }
            if ("registries" in caps && api != "0.2") err("horizon-mod.toml", "capability registries needs api = \"0.2\"")
            val side = manifest["side"] as? String ?: "client"
            if ((side == "server") != (api == "0.3")) err("horizon-mod.toml", "a server mod is side = \"server\" with api = \"0.3\", and only it")
            caps.filter { it != "storage" && (it in serverCaps) != (side == "server") }.forEach { err("horizon-mod.toml", "capability $it is for ${if (side == "server") "client" else "server"} mods") }
            val experimental = (manifest["experimental"] as? List<*>)?.map { it.toString() } ?: emptyList()
            caps.filter { it in experimentalCaps && it !in experimental }.forEach { err("horizon-mod.toml", "capability $it is experimental: add experimental = [\"$it\"]") }
            if (side != "both" && "registries" in caps) warn("horizon-mod.toml", "content mods meant for multiplayer say side = \"both\"")
            val namespaces = (manifest["namespaces"] as? List<*>)?.map { it.toString() } ?: emptyList()
            for (ns in namespaces) {
                if (!ns.matches(nsRe)) err("horizon-mod.toml", "namespace $ns is not [a-z0-9_.-]{1,64}")
                if (ns in reserved) err("horizon-mod.toml", "namespace $ns cannot be claimed")
                if (ns == id) err("horizon-mod.toml", "namespace $ns is the id")
            }
            if (namespaces.isNotEmpty() && "registries" !in caps) err("horizon-mod.toml", "namespaces need capability registries")
            if ("mod.wasm" in names && target == TargetId.HORIZON_DESKTOP) err("mod.wasm", "upstream Horizon no longer runs WebAssembly mods")
            val owned = setOf(id) + namespaces
            for (n in names.filter { it.startsWith("assets/") || it.startsWith("data/") }) {
                val (root, ns) = n.split('/').let { it[0] to it[1] }
                val rest = n.substringAfter("$root/$ns/")
                val ok = ns in owned || (root == "data" && (ns == "minecraft" || ns == "c") && rest.startsWith("tags/")) ||
                    (root == "assets" && ns == "minecraft" && rest.startsWith("atlases/"))
                if (!ok) err(n, "outside the namespaces this mod may hold (${owned.joinToString()}, vanilla/c tags, vanilla atlases)")
                if (root == "data" && rest.startsWith("horizon/") && ns != id) err(n, "declarations go in data/$id/horizon/ only")
                if (root == "data" && rest.startsWith("horizon/")) {
                    val kind = rest.removePrefix("horizon/").substringBefore('/')
                    val known = mutableSetOf("block", "item", "mob_effect", "creative_tab", "entity_type", "menu")
                    if (HorizonCompat.profile(target).fluids) known += "fluid"
                    if (kind !in known) err(n, "${HorizonCompat.profile(target).name} reads no data/<id>/horizon/$kind/")
                }
            }
            // Content and references.
            val text = { n: String -> zip.getInputStream(zip.getEntry(n)).readBytes().decodeToString() }
            val nameSet = names.toSet()
            fun resource(kind: String, ref: String, ext: String): String? {
                val ns = if (ref.contains(':')) ref.substringBefore(':') else "minecraft"
                if (ns == "minecraft") return null // vanilla's own: Horizon has it
                return "assets/$ns/$kind/${ref.substringAfter(':').removePrefix("#")}$ext"
            }
            for (n in names.filter { it.endsWith(".json") || it.endsWith(".mcmeta") }) {
                val json = try { JsonTree.parse(text(n)) } catch (e: Exception) { err(n, "JSON does not parse: ${e.message}"); continue }
                when {
                    n.contains("/models/") -> {
                        JsonTree.obj(JsonTree.obj(json)?.get("textures"))?.values?.forEach { t ->
                            val ref = t as? String ?: return@forEach
                            if (ref.startsWith("#")) return@forEach
                            resource("textures", ref, ".png")?.let { if (it !in nameSet) err(n, "texture $ref has no $it") }
                        }
                        (JsonTree.obj(json)?.get("parent") as? String)?.let { ref -> resource("models", ref, ".json")?.let { if (it !in nameSet) warn(n, "parent $ref is not in the mod") } }
                    }
                    n.contains("/items/") && n.startsWith("assets/") -> collectModels(json).forEach { ref ->
                        resource("models", ref, ".json")?.let { if (it !in nameSet) err(n, "model $ref has no $it") }
                    }
                    n.endsWith("/sounds.json") -> JsonTree.obj(json)?.forEach { (event, v) ->
                        JsonTree.list(JsonTree.obj(v)?.get("sounds"))?.forEach { s ->
                            val ref = (s as? String) ?: (JsonTree.obj(s)?.get("name") as? String) ?: return@forEach
                            if (JsonTree.obj(s)?.get("type") == "event") return@forEach
                            resource("sounds", ref, ".ogg")?.let { if (it !in nameSet) err(n, "sound $event plays $ref but $it is missing") }
                        }
                    }
                    n.contains("/horizon/entity_type/") -> {
                        val o = JsonTree.obj(json)
                        val template = o?.get("template") as? String
                        val profile = HorizonCompat.profile(target)
                        if (template !in profile.livingTemplates && template != "minecraft:snowball") err(n, "template $template is not one ${profile.name} copies")
                        o?.keys?.filter { it !in profile.entityTypeFields }?.forEach { err(n, "field $it is not read by ${profile.name}") }
                        val allowed = HorizonCompat.templateAttributes[template] ?: emptySet()
                        JsonTree.obj(o?.get("attributes"))?.keys?.filter { it !in allowed }?.forEach { err(n, "attribute $it is not one of $template's") }
                    }
                }
            }
            // Functions: commands Horizon has, and functions that exist.
            val functions = names.filter { it.endsWith(".mcfunction") }.map { p -> p.removePrefix("data/").replaceFirst("/function/", ":").removeSuffix(".mcfunction") }.toSet()
            for (n in names.filter { it.endsWith(".mcfunction") }) {
                text(n).lines().forEachIndexed { i, raw ->
                    val line = raw.trim()
                    if (line.isEmpty() || line.startsWith("#")) return@forEachIndexed
                    val root = line.removePrefix("$").substringBefore(' ')
                    if (root !in commandRoots) err("$n:${i + 1}", "unknown command $root")
                    Regex("function ([a-z0-9_.-]+:[a-z0-9_/.-]+)").findAll(line).forEach { m ->
                        val ref = m.groupValues[1]
                        if (ref.substringBefore(':') in owned && ref !in functions) err("$n:${i + 1}", "calls $ref, which is not in the mod")
                    }
                    Regex("predicate ([a-z0-9_.-]+:[a-z0-9_/.-]+)").findAll(line).forEach { m ->
                        val ref = m.groupValues[1]
                        if (ref.substringBefore(':') in owned && "data/${ref.substringBefore(':')}/predicate/${ref.substringAfter(':')}.json" !in nameSet) err("$n:${i + 1}", "uses predicate $ref, which is not in the mod")
                    }
                }
            }
            for (tag in listOf("data/minecraft/tags/function/tick.json", "data/minecraft/tags/function/load.json").filter { it in nameSet }) {
                JsonTree.list(JsonTree.obj(JsonTree.parse(text(tag)))?.get("values"))?.forEach { v ->
                    val ref = v as? String ?: return@forEach
                    if (ref.substringBefore(':') in owned && ref !in functions) err(tag, "lists $ref, which is not in the mod")
                }
            }
        }
        return issues
    }

    private fun collectModels(v: Any?): List<String> = when (v) {
        is Map<*, *> -> (listOfNotNull((v["model"] as? String)?.takeIf { v["type"] == "minecraft:model" })) + v.values.flatMap { collectModels(it) }
        is List<*> -> v.flatMap { collectModels(it) }
        else -> emptyList()
    }

    /**
     * A generated resource or data pack, by the rules the game applies when it reads one
     * (`horizon_client_render::packs::validate_pack_range`, `PackFormat.IntermediaryFormat`):
     * `pack.mcmeta` at the root, a format range that covers this build, lower-case resource
     * paths, and no entry outside `assets/`, `data/` and the pack's own root files.
     */
    fun validatePack(file: File, kind: dev.rustmodforge.core.target.PackGenerator.PackKind): List<Issue> {
        val issues = ArrayList<Issue>()
        fun err(p: String, m: String) { issues += Issue(true, p, m) }
        fun warn(p: String, m: String) { issues += Issue(false, p, m) }
        // Past these formats the game makes min_format and max_format mandatory and refuses
        // supported_formats (resource packs: 64, data packs: 81).
        val lastPreMinor = if (kind == dev.rustmodforge.core.target.PackGenerator.PackKind.DATA) 81 else 64
        ZipFile(file).use { zip ->
            val entries = zip.entries().toList().filter { !it.isDirectory }
            val names = entries.map { it.name }
            if (names.isEmpty()) err(file.name, "the pack is empty")
            for (e in entries) {
                val n = e.name
                if (n.startsWith("/") || n.contains('\\') || n.split('/').any { it.isEmpty() || it == "." || it == ".." }) err(n, "not a relative /-separated path")
                val top = n.substringBefore('/')
                if (top != "assets" && top != "data" && n.contains('/')) err(n, "a pack holds only assets/, data/ and its own root files")
                if ((top == "assets" || top == "data") && !n.matches(contentPathRe)) err(n, "resource paths are lower-case [a-z0-9_.-] parts")
            }
            val meta = zip.getEntry("pack.mcmeta")
            if (meta == null) { err("pack.mcmeta", "missing: the launcher refuses a pack without it"); return issues }
            val parsed = runCatching { JsonTree.obj(JsonTree.parse(zip.getInputStream(meta).readBytes().decodeToString())) }.getOrNull()
            val pack = JsonTree.obj(parsed?.get("pack"))
            if (pack == null) { err("pack.mcmeta", "has no \"pack\" section"); return issues }
            val format = (pack["pack_format"] as? Number)?.toInt()
            val min = (pack["min_format"] as? Number)?.toInt()
            val max = (pack["max_format"] as? Number)?.toInt()
            if (format == null) err("pack.mcmeta", "pack_format is missing")
            val supported = JsonTree.list(pack["supported_formats"])?.mapNotNull { (it as? Number)?.toInt() }
            // The engine refuses supported_formats only when the whole range is past the old
            // window, and requires it when the range reaches into that window.
            if (supported != null && min != null && min > lastPreMinor) {
                err("pack.mcmeta", "supported_formats is refused when min_format ($min) is past $lastPreMinor")
            }
            if (min != null && min <= lastPreMinor) {
                when {
                    supported == null || supported.size != 2 -> err("pack.mcmeta", "min_format $min reaches into the versions that need supported_formats: add [\"$min\", $lastPreMinor]")
                    supported[0] != min -> err("pack.mcmeta", "supported_formats starts at ${supported[0]} but min_format is $min")
                    max != null && supported[1] != max && supported[1] != lastPreMinor ->
                        err("pack.mcmeta", "supported_formats ends at ${supported[1]}, which is neither max_format ($max) nor $lastPreMinor")
                    else -> {}
                }
            }
            if ((min == null) != (max == null)) err("pack.mcmeta", "min_format and max_format are declared together")
            if (format != null && format > lastPreMinor && min == null) {
                err("pack.mcmeta", "format $format is newer than $lastPreMinor, so min_format and max_format are mandatory")
            }
            if (min != null && max != null) {
                if (min > max) err("pack.mcmeta", "min_format ($min) is greater than max_format ($max)")
                if (min < 15) err("pack.mcmeta", "a multi-version pack cannot support a minimum below 15")
                if (format != null && (format < min || format > max)) err("pack.mcmeta", "pack_format $format is outside min_format..max_format")
                if (max < kind.format || min > kind.format) err("pack.mcmeta", "the newest Horizon reads format ${kind.format}, which is outside $min..$max")
            }
            if (!names.contains("pack.png")) warn("pack.png", "no icon: the pack shows the default one in the launcher's list")
            if (names.none { it.startsWith("${kind.root}/") }) err(file.name, "nothing under ${kind.root}/: the pack would change nothing")
        }
        return issues
    }

    /**
     * The same checks on a folder that is still being written, for the agent: the tree is packed
     * to a temporary file and validated as the launcher would read it.
     */
    fun validateTree(dir: File, target: TargetId): List<Issue> = onPacked(dir, "hmod") { validateHmod(it, target) }

    fun validateNativeTree(dir: File, modId: String): List<Issue> = onPacked(dir, "hnmod") { validateHnmod(it) }

    private fun onPacked(dir: File, suffix: String, check: (File) -> List<Issue>): List<Issue> {
        if (dir.walkTopDown().none { it.isFile }) return emptyList()
        val tmp = File.createTempFile("rmf-validate", ".$suffix")
        return try {
            Packager.pack(dir, tmp)
            check(tmp)
        } catch (e: Exception) {
            listOf(Issue(true, dir.name, "could not be packed for validation: ${e.message}"))
        } finally {
            tmp.delete()
        }
    }

    fun validateHnmod(file: File): List<Issue> {
        val issues = ArrayList<Issue>()
        fun err(p: String, m: String) { issues += Issue(true, p, m) }
        ZipFile(file).use { zip ->
            val names = zip.entries().toList().filter { !it.isDirectory }.map { it.name }
            if (names.size > 512) err(file.name, "more than 512 native entries")
            val manifest = zip.getEntry("horizon-native.json")?.let { JsonTree.obj(JsonTree.parse(zip.getInputStream(it).readBytes().decodeToString())) }
            if (manifest == null) { err("horizon-native.json", "missing"); return issues }
            (manifest.keys - setOf("schema", "id", "version", "game", "horizon", "mixins", "hooks")).forEach { err("horizon-native.json", "unknown field $it") }
            if ((manifest["schema"] as? Number)?.toInt() != 1) err("horizon-native.json", "schema must be 1")
            val id = manifest["id"] as? String ?: ""
            if (!id.matches(idRe)) err("horizon-native.json", "id is not [a-z0-9_]{1,64}")
            for (k in listOf("horizon", "mixins")) if (!(manifest[k] as? String ?: "").matches(Regex("[0-9a-f]{40}"))) err("horizon-native.json", "$k must be a 40-character commit")
            if (manifest["game"] != HorizonCompat.MINECRAFT) err("horizon-native.json", "game must be ${HorizonCompat.MINECRAFT}")
            val bundle = "mixins/$id/"
            if ("${bundle}horizon-mixin.toml" !in names) err(bundle, "horizon-mixin.toml missing")
            for (n in names) {
                if (n == "horizon-native.json") continue
                if (!n.startsWith(bundle)) { err(n, "native files live under $bundle"); continue }
                val rel = n.removePrefix(bundle)
                val base = rel.substringAfterLast('/')
                val okType = rel.endsWith(".rs") || rel.endsWith(".toml") || rel.startsWith("data/") || rel.split('/').getOrNull(1) == "data" ||
                    listOf("README", "LICENSE", "LICENCE", "COPYING", "NOTICE", ".gitignore").any { base.startsWith(it) }
                if (!okType) err(n, "a bundle holds only .rs/.toml files, data/ and licence files")
            }
            zip.getEntry("${bundle}horizon-mixin.toml")?.let { e ->
                val toml = runCatching { MiniToml.parse(zip.getInputStream(e).readBytes().decodeToString()) }.getOrElse { err(e.name, "does not parse: ${it.message}"); return issues }
                @Suppress("UNCHECKED_CAST") val mod = toml["mod"] as? Map<String, Any?>
                if (mod?.get("id") != id) err(e.name, "[mod] id must be $id")
                if (mod?.get("version") != manifest["version"]) err(e.name, "[mod] version must match horizon-native.json")
                @Suppress("UNCHECKED_CAST") val compat = toml["compatibility"] as? Map<String, Any?>
                if (compat != null && compat["horizon_revision"] != manifest["horizon"]) err(e.name, "horizon_revision must match horizon-native.json")
            }
        }
        return issues
    }
}
