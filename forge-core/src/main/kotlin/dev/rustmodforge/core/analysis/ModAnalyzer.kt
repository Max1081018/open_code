package dev.rustmodforge.core.analysis

import dev.rustmodforge.core.archive.ArchiveLimits
import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.bytecode.ClassScanner
import dev.rustmodforge.core.bytecode.EntityScanner
import dev.rustmodforge.core.bytecode.JavaLayer
import dev.rustmodforge.core.bytecode.JavaModelScanner
import dev.rustmodforge.core.bytecode.RegistryScanner
import dev.rustmodforge.core.bytecode.BehaviourScanner
import dev.rustmodforge.core.model.BlockInfo
import dev.rustmodforge.core.model.DependencyEdge
import dev.rustmodforge.core.model.DependencyGraph
import dev.rustmodforge.core.model.EntityInfo
import dev.rustmodforge.core.model.ItemInfo
import dev.rustmodforge.core.model.MixinInfo
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.model.RegistryKind
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.model.SoundEventInfo
import dev.rustmodforge.core.model.SpawnInfo
import dev.rustmodforge.core.pipeline.CancellationToken
import dev.rustmodforge.core.pipeline.NoProgress
import dev.rustmodforge.core.pipeline.ProgressListener
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import org.objectweb.asm.Type
import org.objectweb.asm.tree.AnnotationNode
import java.io.File
import java.security.MessageDigest

/** Everything analysis found that later stages need beyond [ModAnalysis] (kept out of the saved IR). */
class AnalysisExtras(val javaLayers: List<JavaLayer>)

/**
 * Inspects one mod jar (and the jars nested in it) without running any of its code, producing
 * the [ModAnalysis] every later stage works from.
 */
class ModAnalyzer(
    private val limits: ArchiveLimits = ArchiveLimits(),
    private val progress: ProgressListener = NoProgress,
    private val cancel: CancellationToken = CancellationToken(),
    /** Where nested jars are unpacked (inside the project's own folder). */
    private val scratch: File? = null,
) {
    var lastExtras: AnalysisExtras = AnalysisExtras(emptyList())
        private set

    fun analyze(file: File, depth: Int = 0): ModAnalysis {
        val stage = "Analysis"
        progress.onProgress(stage, 0f, "Hashing ${file.name}")
        val sha = sha256(file)
        cancel.check()
        SafeArchive.open(file, limits).use { archive ->
            val warnings = ArrayList<String>()
            progress.onProgress(stage, 0.05f, "Reading mod metadata")
            val metadata = MetadataReader.read(archive, warnings)
            cancel.check()
            progress.onProgress(stage, 0.1f, "Indexing ${archive.entries.size} files")
            val resources = ResourceIndexer.index(archive.entries, metadata.mixinConfigs)
            val sounds = readSounds(archive, resources, warnings)
            cancel.check()

            val scanner = ClassScanner(archive)
            scanner.scanHeaders({ done, total ->
                progress.onProgress(stage, 0.15f + 0.35f * done / total.coerceAtLeast(1), "Reading bytecode: $done/$total classes")
            }, { cancel.isCancelled })
            cancel.check()

            progress.onProgress(stage, 0.55f, "Finding registrations")
            val namespaces = resources.mapNotNull { it.namespace.takeIf { n -> n.isNotEmpty() && n != "minecraft" } }.toSet()
            val registrations = RegistryScanner(scanner, metadata.modId, namespaces).scan()
            cancel.check()

            progress.onProgress(stage, 0.65f, "Reconstructing entities and behaviours")
            var entities = EntityScanner(scanner, registrations, metadata.modId).scan()
            cancel.check()

            progress.onProgress(stage, 0.75f, "Linking models, textures and animations")
            val javaLayers = scanner.headers.values.filter { h -> h.references.any { it.contains("LayerDefinition") || it.contains("class_5607") || it.contains("TexturedModelData") } }
                .mapNotNull { scanner.node(it.name) }.flatMap { JavaModelScanner.scan(it) }
            entities = entities.map { linkAssets(it, entities.size, resources, scanner, javaLayers) }
            entities = attachJumpscares(entities, scanner)
            entities = attachSpawns(entities, archive, resources, warnings)
            cancel.check()

            val items = registrations.filter { it.kind == RegistryKind.ITEM }.map { r ->
                ItemInfo(r.id, r.valueClass, r.valueClass?.let { scanner.vanillaBase(it.replace('.', '/'), listOf("SwordItem", "SpawnEggItem", "BlockItem", "Item")) } ?: "Item")
            }
            val blocks = registrations.filter { it.kind == RegistryKind.BLOCK }.map { r ->
                val cls = r.valueClass?.replace('.', '/')
                BlockInfo(r.id, r.valueClass, cls?.let { scanner.vanillaBase(it, listOf("BaseEntityBlock", "Block")) } ?: "Block",
                    hasBlockEntity = cls != null && scanner.extendsConcept(cls, "BaseEntityBlock"))
            }

            progress.onProgress(stage, 0.85f, "Reading mixins and unsupported APIs")
            val mixins = readMixins(archive, metadata.mixinConfigs, scanner, warnings)
            val unsupported = scanner.unsupportedApis().let { list ->
                if (mixins.isEmpty() || list.any { it.api == "Mixins" }) list
                else listOf(dev.rustmodforge.core.model.ApiUsage("Mixins", mixins.map { it.mixinClass },
                    "Mixins patch Minecraft's Java classes; Horizon is Rust and has no Java classes to patch")) + list
            }
            val graph = buildGraph(registrations, entities, mixins)

            val nested = ArrayList<ModAnalysis>()
            if (depth < limits.maxNestingDepth && scratch != null) {
                for (jar in resources.filter { it.kind == ResourceKind.NESTED_JAR }) {
                    cancel.check()
                    progress.onProgress(stage, 0.9f, "Analysing nested ${jar.path.substringAfterLast('/')}")
                    try {
                        val out = archive.extractTo(jar.path, File(scratch, "nested-$depth"), jar.path.substringAfterLast('/'))
                        nested += ModAnalyzer(limits, NoProgress, cancel, scratch).analyze(out, depth + 1)
                    } catch (e: Exception) {
                        warnings += "nested jar ${jar.path} could not be analysed: ${e.message}"
                    }
                }
            }
            lastExtras = AnalysisExtras(javaLayers)
            progress.onProgress(stage, 1f, "Analysis complete")
            return ModAnalysis(
                sourceFile = file.name, sha256 = sha, metadata = metadata, resources = resources, classes = scanner.summaries(),
                registrations = registrations, entities = entities, items = items, blocks = blocks, sounds = sounds,
                geoModels = resources.filter { it.kind == ResourceKind.GEO_MODEL }.map { it.path },
                animations = resources.filter { it.kind == ResourceKind.GECKO_ANIMATION }.map { it.path },
                mixins = mixins, unsupportedApis = unsupported, graph = graph, nested = nested, warnings = warnings,
            )
        }
    }

    private fun readSounds(archive: SafeArchive, resources: List<dev.rustmodforge.core.model.ResourceRef>, warnings: MutableList<String>): List<SoundEventInfo> {
        val out = ArrayList<SoundEventInfo>()
        for (r in resources.filter { it.kind == ResourceKind.SOUND_DEFINITIONS }) {
            val root = runCatching { MetadataReader.lenientJson.parseToJsonElement(archive.readText(r.path)) as JsonObject }.getOrNull()
            if (root == null) { warnings += "${r.path} is not valid JSON"; continue }
            for ((event, v) in root) {
                val o = v as? JsonObject ?: continue
                val files = (o["sounds"] as? JsonArray)?.mapNotNull { s ->
                    when (s) {
                        is JsonPrimitive -> s.contentOrNull
                        is JsonObject -> (s["name"] as? JsonPrimitive)?.contentOrNull
                        else -> null
                    }
                } ?: emptyList()
                out += SoundEventInfo("${r.namespace}:$event", files, (o["subtitle"] as? JsonPrimitive)?.contentOrNull)
            }
        }
        return out
    }

    /** Finds an entity's GeckoLib geometry, texture and animations, or its Java model layer. */
    private fun linkAssets(
        e: EntityInfo, entityCount: Int, resources: List<dev.rustmodforge.core.model.ResourceRef>,
        scanner: ClassScanner, javaLayers: List<JavaLayer>,
    ): EntityInfo {
        val path = e.id.substringAfter(':')
        val simple = e.className.substringAfterLast('.').lowercase()
        fun pick(kind: ResourceKind, vararg filters: (String) -> Boolean): String? {
            val list = resources.filter { it.kind == kind }.map { it.path }
            for (f in filters) list.firstOrNull { f(it.substringAfterLast('/').lowercase()) }?.let { return it }
            return if (entityCount == 1 && list.size == 1) list.first() else null
        }
        val stem: (String) -> String = { it.substringBefore('.') }
        val geo = pick(ResourceKind.GEO_MODEL, { stem(it) == path }, { stem(it) == simple }, { it.startsWith(path) })
        val anim = pick(ResourceKind.GECKO_ANIMATION, { stem(it) == path }, { stem(it) == simple }, { it.startsWith(path) })
        val texture = resources.filter { it.kind == ResourceKind.TEXTURE && it.path.contains("/entity") || it.kind == ResourceKind.TEXTURE && it.path.contains("/textures/") }
            .map { it.path }.let { list ->
                list.firstOrNull { it.substringAfterLast('/').removeSuffix(".png") == path } ?: list.firstOrNull { it.substringAfterLast('/').removeSuffix(".png") == simple }
                    ?: list.firstOrNull { it.contains("/entity/") && it.substringAfterLast('/').startsWith(path) && !it.contains("glow") }
            }
        // Java model: a layer whose class is named after the entity (TheManModel), else the only one.
        val layer = javaLayers.firstOrNull { it.ownerClass.substringAfterLast('/').lowercase().startsWith(simple) }
            ?: javaLayers.singleOrNull()?.takeIf { entityCount == 1 }
        val renderer = scanner.headers.values.firstOrNull { h ->
            (scanner.extendsConcept(h.name, "EntityRenderer") || scanner.extendsConcept(h.name, "GeoEntityRenderer")) &&
                h.name.substringAfterLast('/').lowercase().startsWith(simple)
        }?.name?.replace('/', '.')
        return e.copy(
            geoModel = geo, animationFile = anim, texture = texture,
            javaModelLayer = if (geo == null) layer?.let { "${it.ownerClass.replace('/', '.')}.${it.method}" } else null,
            rendererClass = renderer,
            usesGeckoLib = e.usesGeckoLib || geo != null,
        )
    }

    private fun attachJumpscares(entities: List<EntityInfo>, scanner: ClassScanner): List<EntityInfo> {
        val client = scanner.headers.values.filter { h ->
            h.references.any { it.contains("GuiGraphics") || it.contains("class_332") || it.contains("RenderGuiOverlayEvent") || it.contains("HudRenderCallback") || it.contains("RenderGuiEvent") } ||
                scanner.extendsConcept(h.name, "Screen")
        }.mapNotNull { scanner.node(it.name) }
        val scares = BehaviourScanner(emptyList()).jumpscares(client, scanner)
        if (scares.isEmpty()) return entities
        return entities.mapIndexed { i, e ->
            val related = client.any { cn -> scanner.headers[cn.name]?.references?.any { it == e.className.replace('.', '/') } == true }
            if (related || (entities.size == 1 && i == 0) || (e.category == "monster" && entities.count { it.category == "monster" } == 1)) e.copy(traits = e.traits + scares) else e
        }
    }

    private fun attachSpawns(entities: List<EntityInfo>, archive: SafeArchive, resources: List<dev.rustmodforge.core.model.ResourceRef>, warnings: MutableList<String>): List<EntityInfo> {
        val spawns = HashMap<String, SpawnInfo>()
        for (r in resources.filter { it.kind == ResourceKind.BIOME_MODIFIER }) {
            val o = runCatching { MetadataReader.lenientJson.parseToJsonElement(archive.readText(r.path)) as JsonObject }.getOrNull() ?: continue
            if ((o["type"] as? JsonPrimitive)?.contentOrNull?.endsWith("add_spawns") != true) continue
            val biomes = when (val b = o["biomes"]) { is JsonPrimitive -> listOf(b.content); is JsonArray -> b.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }; else -> emptyList() }
            val list: List<JsonElement> = when (val s = o["spawners"]) { is JsonArray -> s.toList(); is JsonObject -> listOf(s); else -> emptyList() }
            for (s in list.filterIsInstance<JsonObject>()) {
                val type = (s["type"] as? JsonPrimitive)?.contentOrNull ?: continue
                spawns[type] = SpawnInfo("", biomes, (s["weight"] as? JsonPrimitive)?.intOrNull, (s["minCount"] as? JsonPrimitive)?.intOrNull,
                    (s["maxCount"] as? JsonPrimitive)?.intOrNull, r.path)
            }
        }
        return entities.map { e -> spawns[e.id]?.let { e.copy(spawn = it.copy(category = e.category)) } ?: e }
    }

    private fun readMixins(archive: SafeArchive, configs: List<String>, scanner: ClassScanner, warnings: MutableList<String>): List<MixinInfo> {
        val out = ArrayList<MixinInfo>()
        val all = (configs + archive.entries.map { it.path }.filter { !it.contains('/') && it.contains("mixins") && it.endsWith(".json") }).distinct()
        for (cfg in all) {
            if (!archive.contains(cfg)) { warnings += "mixin config $cfg is declared but missing"; continue }
            val o = runCatching { MetadataReader.lenientJson.parseToJsonElement(archive.readText(cfg)) as JsonObject }.getOrNull() ?: continue
            val pkg = (o["package"] as? JsonPrimitive)?.contentOrNull ?: ""
            val names = listOf("mixins", "client", "server").flatMap { k -> (o[k] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList() }
            for (n in names) {
                val cls = "$pkg.$n".trim('.').replace('.', '/')
                val node = scanner.node(cls)
                val ann = (node?.invisibleAnnotations.orEmpty() + node?.visibleAnnotations.orEmpty()).firstOrNull { it.desc == "Lorg/spongepowered/asm/mixin/Mixin;" }
                val targets = ann?.let { annotationTargets(it) } ?: emptyList()
                val injections = node?.methods?.flatMap { m ->
                    (m.invisibleAnnotations.orEmpty() + m.visibleAnnotations.orEmpty()).filter { it.desc.startsWith("Lorg/spongepowered/asm/mixin/injection/") || it.desc.contains("/Overwrite;") }
                        .map { a -> "${a.desc.substringAfterLast('/').removeSuffix(";")} ${m.name}" }
                } ?: emptyList()
                out += MixinInfo(cfg, cls.replace('/', '.'), targets, injections)
            }
        }
        return out
    }

    private fun annotationTargets(a: AnnotationNode): List<String> {
        val out = ArrayList<String>()
        val values = a.values ?: return out
        var i = 0
        while (i + 1 < values.size) {
            val key = values[i] as String
            val v = values[i + 1]
            if (key == "value" && v is List<*>) out += v.filterIsInstance<Type>().map { it.className }
            if (key == "targets" && v is List<*>) out += v.filterIsInstance<String>()
            i += 2
        }
        return out
    }

    private fun buildGraph(registrations: List<dev.rustmodforge.core.model.Registration>, entities: List<EntityInfo>, mixins: List<MixinInfo>): DependencyGraph {
        val nodes = LinkedHashSet<String>()
        val edges = ArrayList<DependencyEdge>()
        fun edge(a: String, b: String, rel: String) { nodes += a; nodes += b; edges += DependencyEdge(a, b, rel) }
        for (r in registrations) {
            edge("registry:${r.kind.name.lowercase()}:${r.id}", "class:${r.declaringClass}", "registered by")
            r.valueClass?.let { edge("registry:${r.kind.name.lowercase()}:${r.id}", "class:$it", "instance of") }
        }
        for (e in entities) {
            val n = "entity:${e.id}"
            edge(n, "class:${e.className}", "implemented by")
            e.geoModel?.let { edge(n, "asset:$it", "model") }
            e.texture?.let { edge(n, "asset:$it", "texture") }
            e.animationFile?.let { edge(n, "asset:$it", "animations") }
            e.javaModelLayer?.let { edge(n, "class:$it", "model layer") }
            e.rendererClass?.let { edge(n, "class:$it", "renderer") }
            e.goals.filter { it.custom }.forEach { edge(n, "class:${it.goal}", "custom goal") }
            listOfNotNull(e.sounds.ambient, e.sounds.hurt, e.sounds.death, e.sounds.step).plus(e.sounds.other).forEach { edge(n, "sound:$it", "sound") }
        }
        for (m in mixins) for (t in m.targets) edge("class:${m.mixinClass}", "minecraft:$t", "mixes into")
        return DependencyGraph(nodes.toList(), edges)
    }

    companion object {
        fun sha256(file: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) { val n = input.read(buf); if (n < 0) break; md.update(buf, 0, n) }
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }
    }
}
