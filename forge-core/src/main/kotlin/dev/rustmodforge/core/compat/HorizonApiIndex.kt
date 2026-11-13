package dev.rustmodforge.core.compat

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The searchable Horizon API knowledge base: hook points, `Host` helpers, goal types and their
 * constructors, the structs goals read, `mod_api` exports and the modding documentation, all
 * extracted from Horizon's source by `tools/build-horizon-api-index.py` and stamped with the
 * revision. The reconstruction agent cites this and nothing else, so it cannot invent an API:
 * what is not here does not exist at the pinned revision.
 */
@Serializable
data class ApiSource(val repository: String = "", val revision: String = "", val native_hooks_api: Int? = null, val generated_by: String = "")

@Serializable
data class ApiHook(
    val kind: String = "hook", val name: String, val version: Int = 1, val side: String = "", val contract: String = "",
    val neoforge: String = "", val trait_method: String = "", val event_type: String = "", val signature: String = "",
    val doc: String = "", val file: String = "",
)

@Serializable
data class ApiHelper(val kind: String = "helper", val name: String, val host_method: String = "", val signature: String = "", val doc: String = "", val file: String = "")

@Serializable
data class ApiGoal(val kind: String = "goal", val name: String, val path: String = "", val doc: String = "", val constructors: List<String> = emptyList(), val file: String = "")

@Serializable
data class ApiStruct(val kind: String = "struct", val name: String, val file: String = "", val fields: List<String> = emptyList(), val methods: List<String> = emptyList())

@Serializable
data class ApiExport(val kind: String = "export", val name: String, val path: String = "")

@Serializable
data class ApiDoc(val kind: String = "doc", val name: String, val file: String = "", val text: String = "")

@Serializable
data class GoalTrait(val methods: List<String> = emptyList(), val flags: Map<String, Int> = emptyMap())

@Serializable
data class ApiIndexData(
    val source: ApiSource = ApiSource(),
    val goal_trait: GoalTrait = GoalTrait(),
    val hooks: List<ApiHook> = emptyList(),
    val helpers: List<ApiHelper> = emptyList(),
    val goals: List<ApiGoal> = emptyList(),
    val structs: List<ApiStruct> = emptyList(),
    val exports: List<ApiExport> = emptyList(),
    val docs: List<ApiDoc> = emptyList(),
)

/** One search hit, rendered compactly for a model's context window. */
data class ApiHit(val kind: String, val name: String, val score: Int, val text: String)

object HorizonApiIndex {
    val data: ApiIndexData by lazy {
        val text = HorizonApiIndex::class.java.getResourceAsStream("/rustmodforge/horizon-api.json")?.bufferedReader()?.readText()
            ?: error("horizon-api.json missing from the engine's resources")
        Json { ignoreUnknownKeys = true }.decodeFromString(ApiIndexData.serializer(), text)
    }

    val revision: String get() = data.source.revision

    fun hook(name: String) = data.hooks.firstOrNull { it.name == name }
    fun goal(name: String) = data.goals.firstOrNull { it.name == name }
    fun hasHook(name: String) = hook(name) != null
    fun hasHelper(name: String) = data.helpers.any { it.name == name }

    private fun tokens(q: String) = q.lowercase().split(Regex("[^a-z0-9_]+")).filter { it.length >= 2 }.distinct()

    private fun score(terms: List<String>, name: String, body: String): Int {
        val n = name.lowercase(); val b = body.lowercase()
        var s = 0
        for (t in terms) {
            if (n == t) s += 40
            else if (n.contains(t)) s += 18
            if (b.contains(t)) s += 6 + minOf(6, b.windowed(t.length).count { it == t })
        }
        return s
    }

    /**
     * Keyword search across everything, best first. Each hit is a compact paragraph: what it is,
     * the exact signature or constructor, and the doc comment, so a model gets the real contract
     * rather than a name to guess from.
     */
    fun search(query: String, limit: Int = 8, kinds: Set<String> = setOf("hook", "helper", "goal", "struct", "export", "doc")): List<ApiHit> {
        val terms = tokens(query)
        if (terms.isEmpty()) return emptyList()
        val hits = ArrayList<ApiHit>()
        if ("hook" in kinds) for (h in data.hooks) {
            val s = score(terms, h.name, h.doc + " " + h.neoforge + " " + h.signature)
            if (s > 0) hits += ApiHit("hook", h.name, s, renderHook(h))
        }
        if ("helper" in kinds) for (h in data.helpers) {
            val s = score(terms, h.name, h.doc + " " + h.signature)
            if (s > 0) hits += ApiHit("helper", h.name, s, "Host helper `host.${h.name}` — ${h.signature.ifEmpty { "(signature in ${h.file})" }}\n${h.doc.take(500)}")
        }
        if ("goal" in kinds) for (g in data.goals) {
            val s = score(terms, g.name, g.doc + " " + g.constructors.joinToString())
            if (s > 0) hits += ApiHit("goal", g.name, s, "Goal `${g.path}` — ${g.constructors.joinToString("; ").ifEmpty { "unit struct (no constructor)" }}\n${g.doc.take(400)}")
        }
        if ("struct" in kinds) for (st in data.structs) {
            val s = score(terms, st.name, st.fields.joinToString() + " " + st.methods.joinToString())
            if (s > 0) hits += ApiHit("struct", st.name, s, "struct ${st.name} (${st.file})\nfields: ${st.fields.joinToString(", ")}\nmethods: ${st.methods.joinToString(", ").take(1500)}")
        }
        if ("export" in kinds) for (e in data.exports) {
            val s = score(terms, e.name, e.path)
            if (s > 0) hits += ApiHit("export", e.name, s / 2, "`horizon_client::mod_api::${e.name}` re-exports `${e.path}`")
        }
        if ("doc" in kinds) for (d in data.docs) {
            val s = score(terms, d.name, d.text)
            if (s > 0) hits += ApiHit("doc", d.name, s / 2, "Documentation (${d.file} › ${d.name}):\n${d.text.take(1400)}")
        }
        return hits.sortedByDescending { it.score }.take(limit)
    }

    private fun renderHook(h: ApiHook): String = buildString {
        append("Hook point `${h.name}` v${h.version}")
        if (h.side.isNotEmpty()) append(" (${h.side})")
        if (h.contract.isNotEmpty()) append(", contract ${h.contract}")
        if (h.neoforge.isNotEmpty()) append(", NeoForge: ${h.neoforge}")
        append("\nTrait method: fn ${h.trait_method}(&self, [host,] event: &mut ${h.event_type}<'_>)")
        if (h.contract == "cancel") append(" -> Flow")
        if (h.signature.isNotEmpty()) append("\nGame signature: ${h.signature}")
        if (h.doc.isNotEmpty()) append("\n${h.doc.take(700)}")
    }

    /** The fixed facts every Rust generation prompt carries: the Goal trait and the flags. */
    fun goalContract(): String = buildString {
        appendLine("horizon_client::mobs::goals::Goal trait methods: ${data.goal_trait.methods.joinToString()}.")
        appendLine("Flags: ${data.goal_trait.flags.entries.joinToString { "${it.key}=${it.value}" }} (u8, OR them).")
        appendLine("Required: fn flags(&self) -> u8; fn can_use(&mut self, m: &mut Mob, cx: &mut Cx) -> bool; fn box_clone(&self) -> Box<dyn Goal>.")
        appendLine("Optional with defaults: can_continue, start, stop, tick (all (&mut self, m: &mut Mob, cx: &mut Cx)), interruptable, every_tick.")
        appendLine("Vanilla goals available: ${data.goals.joinToString { g -> g.constructors.firstOrNull() ?: g.name }}.")
    }
}
