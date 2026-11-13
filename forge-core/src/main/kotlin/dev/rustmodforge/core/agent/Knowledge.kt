package dev.rustmodforge.core.agent

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** What one agent step did, for the app's live view and for the report. */
@Serializable
data class AgentStep(
    val time: Long,
    /** The phase a person reads: "Analysing Java class", "Retrieving Horizon API", … */
    val phase: String,
    val tool: String,
    val detail: String,
    val ok: Boolean = true,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val model: String = "",
)

/** A fact the agent established, kept so later steps and later runs do not re-derive it. */
@Serializable
data class Note(val key: String, val text: String, val time: Long = 0)

/**
 * The project's shared knowledge base. Every agent writes what it learned here and reads what
 * the others left, so a class is analysed once, a resumed conversion keeps its findings, and the
 * context sent to a model stays small.
 */
class Knowledge(private val dir: File) {
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true; encodeDefaults = true }
    private val notesFile = File(dir, "knowledge.json")
    private val stepsFile = File(dir, "agent-steps.jsonl")

    private val notes = LinkedHashMap<String, Note>()

    init {
        dir.mkdirs()
        if (notesFile.exists()) runCatching {
            json.decodeFromString(kotlinx.serialization.builtins.ListSerializer(Note.serializer()), notesFile.readText())
                .forEach { notes[it.key] = it }
        }
    }

    val keys: Set<String> get() = notes.keys

    fun note(key: String): String? = notes[key]?.text

    @Synchronized
    fun remember(key: String, text: String) {
        notes[key] = Note(key, text.take(4000), System.currentTimeMillis())
        runCatching { notesFile.writeText(json.encodeToString(kotlinx.serialization.builtins.ListSerializer(Note.serializer()), notes.values.toList())) }
    }

    /** Everything known, as a compact block for a prompt (newest last, bounded). */
    fun digest(maxChars: Int = 3000): String {
        if (notes.isEmpty()) return "(nothing recorded yet)"
        val text = notes.values.joinToString("\n") { "- ${it.key}: ${it.text}" }
        return if (text.length <= maxChars) text else "…\n" + text.takeLast(maxChars)
    }

    @Synchronized
    fun step(step: AgentStep) {
        runCatching { stepsFile.appendText(json.encodeToString(AgentStep.serializer(), step).replace("\n", " ") + "\n") }
    }

    fun steps(): List<AgentStep> = if (!stepsFile.exists()) emptyList() else
        stepsFile.readLines().mapNotNull { l -> runCatching { json.decodeFromString(AgentStep.serializer(), l) }.getOrNull() }

    companion object {
        fun stepsOf(dir: File): List<AgentStep> = Knowledge(dir).steps()
    }
}
