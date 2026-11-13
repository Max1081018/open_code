package dev.rustmodforge.core.agent

import dev.rustmodforge.core.ai.AiPausedException
import dev.rustmodforge.core.ai.AiProvider
import dev.rustmodforge.core.compat.HorizonApiIndex
import dev.rustmodforge.core.pipeline.CancellationToken
import dev.rustmodforge.core.util.JsonTree
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import java.io.File

/** How the agent's run ended. */
enum class AgentOutcome { FINISHED, BUDGET_SPENT, PAUSED, BLOCKED, CANCELLED, NO_PROVIDER }

data class AgentRun(
    val outcome: AgentOutcome,
    val summary: String,
    val unsupported: String,
    val steps: List<AgentStep>,
    val filesWritten: List<String>,
    /** True only when the engine itself confirmed the result: validators, and the compiler where one ran. */
    val verified: Boolean,
    val verification: String,
    val inputTokens: Int,
    val outputTokens: Int,
)

/**
 * The reconstruction agent: a loop in which a model may only act through [Tools], and every
 * effect is executed by the engine. It reads the mod's bytecode and the Horizon API knowledge
 * base, writes Rust or content data, and is then held to the engine's own verdict — the
 * validators and the compiler. Work that does not validate is rolled back to the last state
 * that did, so a run can only improve the output or leave it as it was.
 *
 * The model never runs code: it names a tool, the engine performs it, and the result goes back
 * as text. Imported Java is parsed, never loaded.
 */
class ReconstructionAgent(
    private val provider: AiProvider?,
    private val ctx: AgentContext,
    /** Hard caps: a free model has little context and a rate limit. */
    private val maxSteps: Int = 24,
    private val tokenBudget: Int = 120_000,
    private val cancel: CancellationToken = CancellationToken(),
    private val cacheDir: File? = null,
    private val onStep: (AgentStep) -> Unit = {},
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val steps = ArrayList<AgentStep>()
    private val written = LinkedHashSet<String>()
    private var input = 0
    private var output = 0
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    private fun log(phase: String, tool: String, detail: String, ok: Boolean = true, inTok: Int = 0, outTok: Int = 0) {
        val s = AgentStep(clock(), phase, tool, detail.take(400), ok, inTok, outTok)
        steps += s
        ctx.knowledge.step(s)
        onStep(s)
    }

    private fun systemPrompt(task: String) = """
        You rebuild a Minecraft Java mod's behaviour on Horizon, a Rust engine. Java does not run on
        Horizon: you reconstruct what the original code *does* using Horizon's own APIs.

        You act only by naming one tool per reply. Reply with JSON and nothing else:
        {"thought": "one short sentence", "tool": "<name>", "args": { … }}

        Tools:
        ${Tools.manual()}

        Rules that are not negotiable:
        - Horizon's APIs are only what search_horizon_api returns, from the engine's source at
          revision ${HorizonApiIndex.revision.take(10)}. Never write a function, type, field or hook that it did not
          show you. If something you need does not exist, say so in finish's `unsupported` with the
          exact missing capability.
        - Look up an API with search_horizon_api before you write code that uses it.
        - Prefer the mod's real numbers (attributes, distances, speeds, timings) from entity_report
          and the bytecode over invented ones.
        - After writing code, run validate, and compile when the target has a native mod. Fix what
          they report. Do not claim anything works; the engine decides that.
        - Keep every reply small. Ask for one class or one method at a time.

        ${HorizonApiIndex.goalContract()}

        How to reconstruct a behaviour (not a line-by-line translation):
        1. entity_report, then disassemble the method or custom goal class behind the behaviour.
        2. Say what it does in your own words: what it senses, what state it changes, what it then does.
        3. search_horizon_api for each capability that needs: sensing, moving, timing, damage, sound.
        4. Write the smallest code that does the same thing with those APIs, keeping the mod's own numbers.
        5. validate, and compile where there is a native mod. Fix what they report, then finish.

        An example of one reply, and the only shape accepted:
        {"thought": "the stalk goal's distance is what I need", "tool": "disassemble", "args": {"name": "com.example.goal.StalkGoal", "method": "canUse", "limit": 2000}}

        What the project already knows:
        ${ctx.knowledge.digest()}

        Your task: $task
    """.trimIndent()

    /**
     * Runs the agent. [snapshot] is the state to return to if the run leaves the project worse
     * than it found it (its validator errors increase).
     */
    fun run(task: String): AgentRun {
        if (provider == null) {
            return AgentRun(AgentOutcome.NO_PROVIDER, "", "No AI provider is configured, so the AI reconstruction stage did not run; the built-in rules did the work.",
                emptyList(), emptyList(), false, "not run", 0, 0)
        }
        val before = ctx.validator().count { it.error }
        val snapshot = Snapshot.of(ctx)
        val conversation = StringBuilder()
        var summary = ""
        var unsupported = ""
        var outcome = AgentOutcome.BUDGET_SPENT
        var malformed = 0

        loop@ for (step in 1..maxSteps) {
            if (cancel.isCancelled) { outcome = AgentOutcome.CANCELLED; break }
            if (input + output >= tokenBudget) { outcome = AgentOutcome.BUDGET_SPENT; break }
            val user = if (conversation.isEmpty()) "Begin. Step 1 of at most $maxSteps."
            else {
                val full = conversation.toString()
                val tail = full.takeLast(12_000)
                val note = if (tail.length < full.length) "(earlier steps were trimmed; what you recorded with remember is in the system message)\n\n" else ""
                note + tail + "\n\nStep $step of at most $maxSteps. Your next action as JSON:"
            }

            val reply = try {
                provider.complete(systemPrompt(task), user, 1200)
            } catch (e: AiPausedException) {
                log("Paused", "ai", e.message ?: "paused", false)
                outcome = AgentOutcome.PAUSED
                break
            } catch (e: Exception) {
                log("AI request failed", "ai", e.message ?: e::class.java.simpleName, false)
                outcome = AgentOutcome.BLOCKED
                break
            }
            input += reply.inputTokens; output += reply.outputTokens

            val action = parse(reply.text)
            if (action == null) {
                malformed++
                log("Reading the model's reply", "ai", "the reply was not a single JSON action", false, reply.inputTokens, reply.outputTokens)
                if (malformed >= 3) { outcome = AgentOutcome.BLOCKED; break }
                conversation.append("\n\nYour reply was not a single JSON object with \"tool\" and \"args\". Reply with exactly that and nothing else.")
                continue
            }
            val tool = Tools.byName[action.tool]
            if (tool == null) {
                log("Reading the model's reply", action.tool, "no such tool", false, reply.inputTokens, reply.outputTokens)
                conversation.append("\n\nThere is no tool \"${action.tool}\". Available: ${Tools.byName.keys.joinToString()}.")
                continue
            }
            if (tool.name == "finish") {
                summary = (action.args["summary"] as? JsonPrimitive)?.contentOrNull ?: action.thought
                unsupported = (action.args["unsupported"] as? JsonPrimitive)?.contentOrNull ?: ""
                log(tool.phase, tool.name, summary, true, reply.inputTokens, reply.outputTokens)
                outcome = AgentOutcome.FINISHED
                break
            }

            val result = try {
                tool.run(ctx, action.args)
            } catch (e: Exception) {
                ToolResult("the tool failed: ${e.message}", false)
            }
            result.wrote?.let { written += it }
            // Keep enough of the result that the app's history shows the real reason, such as
            // the compiler's own error, not just a count.
            val headline = result.text.lines().filter { it.isNotBlank() }.take(2).joinToString(" ")
            log(tool.phase, tool.name, (action.thought.ifEmpty { "" } + " " + headline).trim(), result.ok, reply.inputTokens, reply.outputTokens)
            conversation.append("\n\n> ${tool.name}(${compact(action.args)})\n${result.text.take(5000)}")
        }

        // The engine's own verdict, never the model's.
        val after = ctx.validator()
        val afterErrors = after.count { it.error }
        var verified = written.isNotEmpty() && afterErrors == 0
        var verification = if (written.isEmpty()) "the agent wrote no files" else "validators: $afterErrors errors"
        if (afterErrors > before) {
            snapshot.restore(ctx)
            verification = "rolled back: the agent's files raised validator errors from $before to $afterErrors"
            verified = false
            written.clear()
            log("Rolling back", "validate", verification, false)
        } else if (written.any { it.startsWith("hnmod/") }) {
            val backend = ctx.backend
            if (backend != null && backend.available()) {
                val r = backend.check(ctx.native!!.root, ctx.modId)
                if (!r.success) {
                    snapshot.restore(ctx)
                    verification = "rolled back: the generated Rust did not compile (${r.diagnostics.count { it.level == "error" }} errors)"
                    verified = false
                    written.clear()
                    log("Rolling back", "compile", verification, false)
                } else {
                    verification = "validators clean and the Rust compiled"
                    verified = true
                }
            } else {
                verification = "validators clean; the Rust was not compiled (no build backend), so it is unverified"
                verified = false
            }
        }

        return AgentRun(outcome, summary, unsupported, steps, written.toList(), verified, verification, input, output)
    }

    private class Action(val thought: String, val tool: String, val args: JsonObject)

    /** One JSON action, tolerating a fenced block or prose around it. */
    private fun parse(text: String): Action? {
        val start = text.indexOf('{')
        if (start < 0) return null
        var depth = 0
        var end = -1
        var inString = false
        var escape = false
        for (i in start until text.length) {
            val c = text[i]
            when {
                escape -> escape = false
                c == '\\' && inString -> escape = true
                c == '"' -> inString = !inString
                inString -> {}
                c == '{' -> depth++
                c == '}' -> { depth--; if (depth == 0) { end = i; break } }
            }
        }
        if (end < 0) return null
        val o = runCatching { json.parseToJsonElement(text.substring(start, end + 1)).jsonObject }.getOrNull() ?: return null
        val tool = (o["tool"] as? JsonPrimitive)?.contentOrNull ?: return null
        val args = (o["args"] as? JsonObject) ?: JsonObject(emptyMap())
        return Action((o["thought"] as? JsonPrimitive)?.contentOrNull ?: "", tool, args)
    }

    private fun compact(args: JsonObject) = args.entries.joinToString { (k, v) ->
        val s = (v as? JsonPrimitive)?.contentOrNull ?: v.toString()
        "$k=" + if (s.length > 60) s.take(60) + "…" else s
    }

    /** The generated trees as they were, so a run that makes things worse changes nothing. */
    private class Snapshot(val content: Map<String, ByteArray>, val native: Map<String, ByteArray>?) {
        fun restore(ctx: AgentContext) {
            ctx.content.clear()
            content.forEach { (p, b) -> ctx.content.put(p, b) }
            if (native != null && ctx.native != null) {
                ctx.native.clear()
                native.forEach { (p, b) -> ctx.native.put(p, b) }
            }
        }
        companion object {
            fun of(ctx: AgentContext) = Snapshot(
                ctx.content.list().associateWith { ctx.content.file(it).readBytes() },
                ctx.native?.let { t -> t.list().associateWith { t.file(it).readBytes() } },
            )
        }
    }
}
