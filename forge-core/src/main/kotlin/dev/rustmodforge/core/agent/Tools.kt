package dev.rustmodforge.core.agent

import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.build.BuildBackend
import dev.rustmodforge.core.build.Issue
import dev.rustmodforge.core.bytecode.Disassembler
import dev.rustmodforge.core.compat.HorizonApiIndex
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.target.OutputTree
import dev.rustmodforge.core.util.JsonTree
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/** What the tools act on. Nothing here loads or runs the imported mod's Java code. */
class AgentContext(
    val analysis: ModAnalysis,
    val archive: SafeArchive,
    val modId: String,
    val target: TargetId,
    val knowledge: Knowledge,
    /** The content mod being written (`.hmod` tree). */
    val content: OutputTree,
    /** The native mod being written, on targets that have one. */
    val native: OutputTree? = null,
    val backend: BuildBackend? = null,
    /** Runs the engine's validators over the current trees. */
    val validator: () -> List<Issue> = { emptyList() },
)

/** The outcome of one tool call: text for the model, plus whether it changed the project. */
data class ToolResult(val text: String, val ok: Boolean = true, val wrote: String? = null)

/**
 * One operation the agent may ask for. The agent never runs code of its own: it names a tool and
 * the engine executes it, so every effect is one of these, with its arguments validated here.
 */
class Tool(
    val name: String,
    /** The phase a person reads in the progress view. */
    val phase: String,
    val args: String,
    val description: String,
    val run: (AgentContext, JsonObject) -> ToolResult,
)

object Tools {
    private const val MAX_TEXT = 6000

    private fun JsonObject.str(k: String): String? = (this[k] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.int(k: String, default: Int): Int = (this[k] as? JsonPrimitive)?.intOrNull ?: default
    private fun trim(s: String, max: Int = MAX_TEXT) = if (s.length <= max) s else s.take(max) + "\n… truncated at $max characters; ask for a narrower part."

    /** Only these places may be written, so a generated file can never land outside the mod. */
    private fun nativeSourcePath(ctx: AgentContext, path: String): String? {
        val clean = path.removePrefix("./").trim()
        val allowed = clean.startsWith("mixins/${ctx.modId}/api/src/") && clean.endsWith(".rs") &&
            !clean.contains("..") && clean.matches(Regex("[A-Za-z0-9_./-]+"))
        return if (allowed) clean else null
    }

    private fun contentDataPath(ctx: AgentContext, path: String): String? {
        val clean = path.removePrefix("./").trim()
        val ok = (clean.startsWith("data/${ctx.modId}/") || clean.startsWith("assets/${ctx.modId}/")) &&
            !clean.contains("..") && clean.matches(Regex("[a-z0-9_./-]+")) &&
            (clean.endsWith(".json") || clean.endsWith(".mcfunction"))
        return if (ok) clean else null
    }

    val all: List<Tool> = listOf(
        Tool("list_classes", "Reading the mod's classes", "{\"filter\": \"optional substring\", \"limit\": 40}",
            "The mod's Java classes with the vanilla class each extends. Start here to find what implements a behaviour.") { ctx, a ->
            val filter = a.str("filter")?.lowercase()
            val list = ctx.analysis.classes.filter { filter == null || it.name.lowercase().contains(filter) }
            ToolResult(trim(list.take(a.int("limit", 40)).joinToString("\n") { c ->
                "${c.name}${c.vanillaBase?.let { " extends $it" } ?: ""} · ${c.methodCount} methods, ${c.fieldCount} fields"
            }.ifEmpty { "no class matches" } + "\n(${list.size} matched of ${ctx.analysis.classes.size})"))
        },

        Tool("class_detail", "Analysing a Java class", "{\"name\": \"com.example.Mob\"}",
            "One class's superclass, interfaces, methods and the Minecraft members it references.") { ctx, a ->
            val name = a.str("name") ?: return@Tool ToolResult("name is required", false)
            val c = ctx.analysis.classes.firstOrNull { it.name == name || it.name.endsWith(".$name") }
                ?: return@Tool ToolResult("no such class; use list_classes", false)
            ToolResult(trim("""
                class ${c.name}
                extends ${c.superName ?: "?"}${c.vanillaBase?.let { " (vanilla concept: $it)" } ?: ""}
                implements ${c.interfaces.joinToString().ifEmpty { "-" }}
                ${c.methodCount} methods, ${c.fieldCount} fields, ${c.size} bytes
            """.trimIndent()))
        },

        Tool("disassemble", "Reading bytecode", "{\"name\": \"com.example.Mob\", \"method\": \"optional method name\", \"limit\": 6000}",
            "The class's bytecode as ASM prints it (never executed). With `method`, only that method's body.") { ctx, a ->
            val name = a.str("name") ?: return@Tool ToolResult("name is required", false)
            val internal = name.replace('.', '/')
            val cached = ctx.knowledge.note("disasm:$name:${a.str("method") ?: ""}")
            if (cached != null) return@Tool ToolResult(cached)
            var text = Disassembler.disassemble(ctx.archive, internal, 200_000)
            val method = a.str("method")
            if (method != null) {
                val start = text.indexOf(" $method(")
                text = if (start < 0) "no method $method in $name" else {
                    val rest = text.substring(start)
                    val end = rest.indexOf("\n\n  ").let { if (it < 0) rest.length else it }
                    rest.take(end)
                }
            }
            ToolResult(trim(text, a.int("limit", MAX_TEXT)))
        },

        Tool("entity_report", "Reading the reconstructed entity", "{\"id\": \"mod:entity\"}",
            "What local analysis already found for an entity: vanilla base, size, default attributes, every AI goal with its arguments, and each recognised behaviour with the method that showed it.") { ctx, a ->
            val id = a.str("id")
            val e = ctx.analysis.entities.firstOrNull { it.id == id } ?: ctx.analysis.entities.firstOrNull()
                ?: return@Tool ToolResult("this mod has no entity", false)
            ToolResult(trim(buildString {
                appendLine("entity ${e.id} (class ${e.className}, extends ${e.vanillaBase}, category ${e.category.ifEmpty { "-" }})")
                if (e.width != null) appendLine("size ${e.width} x ${e.height}")
                appendLine("attributes: " + e.attributes.entries.joinToString { "${it.key}=${it.value}" }.ifEmpty { "none found" })
                appendLine("goals:")
                e.goals.forEach { g -> appendLine("  ${g.selector} ${g.priority}: ${g.goal}(${g.args.joinToString()})${if (g.custom) " [custom class]" else ""}") }
                appendLine("behaviours recognised:")
                e.traits.forEach { t -> appendLine("  ${t.kind} ${t.params} <- ${t.evidence.joinToString("; ")}") }
                appendLine("sounds: ambient=${e.sounds.ambient} hurt=${e.sounds.hurt} death=${e.sounds.death} other=${e.sounds.other}")
                appendLine("assets: geo=${e.geoModel} anim=${e.animationFile} texture=${e.texture} javaModel=${e.javaModelLayer}")
                if (e.unresolved.isNotEmpty()) appendLine("unresolved: ${e.unresolved.joinToString()}")
            }))
        },

        Tool("dependencies", "Inspecting dependencies", "{}",
            "The mod's declared dependencies and the internal graph edges (which class, asset or sound each entity needs).") { ctx, _ ->
            ToolResult(trim(buildString {
                appendLine("declared: " + ctx.analysis.metadata.dependencies.joinToString { "${it.id} ${it.versionRange} (${it.kind})" }.ifEmpty { "none" })
                appendLine("unsupported APIs: " + ctx.analysis.unsupportedApis.joinToString { it.api }.ifEmpty { "none" })
                appendLine("graph:")
                ctx.analysis.graph.edges.take(60).forEach { appendLine("  ${it.from} --${it.relation}--> ${it.to}") }
            }))
        },

        Tool("read_resource", "Reading a mod resource", "{\"path\": \"assets/mod/geo/x.geo.json\", \"limit\": 4000}",
            "A file from the imported jar, as text. For models, animations, sounds.json and data files.") { ctx, a ->
            val path = a.str("path") ?: return@Tool ToolResult("path is required", false)
            if (!ctx.archive.contains(path)) return@Tool ToolResult("no such entry; resources are listed in the analysis", false)
            ToolResult(trim(runCatching { ctx.archive.readText(path) }.getOrElse { "unreadable: ${it.message}" }, a.int("limit", 4000)))
        },

        Tool("search_horizon_api", "Retrieving Horizon API documentation", "{\"query\": \"mob goals navigation\", \"kinds\": \"hook,helper,goal,struct,doc\", \"limit\": 6}",
            "Searches the Horizon API knowledge base built from the engine's own source at the pinned revision: hook points with signatures, Host helpers, goal types with constructors, the structs goals read, and the modding documentation. This is the only source of Horizon APIs; anything absent here does not exist.") { _, a ->
            val q = a.str("query") ?: return@Tool ToolResult("query is required", false)
            val kinds = (a.str("kinds") ?: "hook,helper,goal,struct,export,doc").split(',').map { it.trim() }.toSet()
            val hits = HorizonApiIndex.search(q, a.int("limit", 6), kinds)
            ToolResult(trim(if (hits.isEmpty()) "nothing in Horizon's API matches \"$q\" at revision ${HorizonApiIndex.revision.take(10)}. That API does not exist: say so and look for another way."
            else hits.joinToString("\n\n") { "[${it.kind}] ${it.name}\n${it.text}" }))
        },

        Tool("list_generated", "Reading generated files", "{\"filter\": \"optional substring\"}",
            "The files generated so far, in the content mod and the native mod.") { ctx, a ->
            val filter = a.str("filter")
            fun list(t: OutputTree?, label: String) = t?.list()?.filter { filter == null || it.contains(filter) }?.map { "$label/$it" } ?: emptyList()
            ToolResult(trim((list(ctx.content, "hmod") + list(ctx.native, "hnmod")).joinToString("\n").ifEmpty { "nothing generated yet" }))
        },

        Tool("read_generated", "Reading generated code", "{\"path\": \"hnmod/mixins/mod/api/src/lib.rs\", \"limit\": 6000}",
            "One generated file. Prefix the path with `hmod/` or `hnmod/`.") { ctx, a ->
            val raw = a.str("path") ?: return@Tool ToolResult("path is required", false)
            val (tree, path) = when {
                raw.startsWith("hnmod/") -> ctx.native to raw.removePrefix("hnmod/")
                raw.startsWith("hmod/") -> ctx.content to raw.removePrefix("hmod/")
                else -> ctx.content to raw
            }
            if (tree == null || !tree.exists(path)) return@Tool ToolResult("no such generated file; use list_generated", false)
            ToolResult(trim(tree.readText(path), a.int("limit", MAX_TEXT)))
        },

        Tool("write_rust", "Generating Rust", "{\"path\": \"mixins/<mod>/api/src/<name>.rs\", \"content\": \"…\"}",
            "Writes a Rust source file of the native mod. Only paths under `mixins/<mod>/api/src/` ending in `.rs`. The file is compiled later; nothing is kept unless it compiles.") { ctx, a ->
            val native = ctx.native ?: return@Tool ToolResult("this target has no native mod: Horizon Android loads .hmod only, so behaviour here is data and functions, not Rust.", false)
            val path = a.str("path")?.let { nativeSourcePath(ctx, it) }
                ?: return@Tool ToolResult("path must be mixins/${ctx.modId}/api/src/<name>.rs", false)
            val content = a.str("content") ?: return@Tool ToolResult("content is required", false)
            if (content.length > 60_000) return@Tool ToolResult("that file is too large; split it", false)
            native.putText(path, content)
            ToolResult("wrote $path (${content.length} characters)", wrote = "hnmod/$path")
        },

        Tool("write_content", "Generating content data", "{\"path\": \"data/<mod>/…json\", \"content\": \"…\"}",
            "Writes a data or asset file of the content mod (JSON or .mcfunction). JSON must parse. Only the mod's own namespace.") { ctx, a ->
            val path = a.str("path")?.let { contentDataPath(ctx, it) }
                ?: return@Tool ToolResult("path must be data/${ctx.modId}/… or assets/${ctx.modId}/… and end in .json or .mcfunction", false)
            val content = a.str("content") ?: return@Tool ToolResult("content is required", false)
            if (path.endsWith(".json") && runCatching { JsonTree.parse(content) }.isFailure) return@Tool ToolResult("that is not valid JSON", false)
            ctx.content.putText(path, content)
            ToolResult("wrote $path (${content.length} characters)", wrote = "hmod/$path")
        },

        Tool("validate", "Running validators", "{}",
            "Runs the engine's validators over what is generated: manifests, paths, references, declarations, commands. Returns the errors and warnings.") { ctx, _ ->
            val issues = ctx.validator()
            val errors = issues.filter { it.error }
            ToolResult(trim(if (issues.isEmpty()) "validation passed with no issues"
            else "${errors.size} errors, ${issues.size - errors.size} warnings\n" + issues.take(40).joinToString("\n") { it.toString() }), errors.isEmpty())
        },

        Tool("compile", "Compiling generated Rust", "{}",
            "Compiles the native mod against Horizon with the configured build backend and returns the compiler's own errors. Without a backend it reports that compilation did not run.") { ctx, _ ->
            val native = ctx.native ?: return@Tool ToolResult("no native mod on this target", false)
            val backend = ctx.backend
            if (backend == null || !backend.available()) {
                return@Tool ToolResult("no build backend is configured, so compilation did not run. A phone cannot compile Horizon; the user sets a build server in Settings. Keep the code simple and well-formed, and say in your summary that it is unverified.", false)
            }
            val r = backend.check(native.root, ctx.modId)
            val errors = r.diagnostics.filter { it.level == "error" }
            ToolResult(trim(when {
                !r.ran -> "compilation did not run: ${r.log.take(400)}"
                r.success -> "compiled with no errors (${r.diagnostics.count { it.level == "warning" }} warnings)"
                else -> "${errors.size} compile errors:\n" + errors.take(20).joinToString("\n") { "${it.file}:${it.line}: ${it.message}" }
            }), r.ran && r.success)
        },

        Tool("remember", "Recording a finding", "{\"key\": \"entity.watcher.ai\", \"text\": \"…\"}",
            "Stores a finding in the project's knowledge base so later steps and later runs do not derive it again. Keep it to one or two sentences.") { ctx, a ->
            val key = a.str("key") ?: return@Tool ToolResult("key is required", false)
            val text = a.str("text") ?: return@Tool ToolResult("text is required", false)
            ctx.knowledge.remember(key, text)
            ToolResult("recorded $key")
        },

        Tool("finish", "Finishing", "{\"summary\": \"what was reconstructed\", \"unsupported\": \"what could not be, and the exact missing capability\"}",
            "Ends the task. Use it when the work validates and compiles, or when a genuine technical blocker stops it.") { _, a ->
            ToolResult("finished: " + (a.str("summary") ?: "") + (a.str("unsupported")?.let { "\nunsupported: $it" } ?: ""))
        },
    )

    val byName: Map<String, Tool> = all.associateBy { it.name }

    /** The tool list as the prompt presents it. */
    fun manual(): String = all.joinToString("\n") { "- ${it.name} ${it.args}\n  ${it.description}" }
}
