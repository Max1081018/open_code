package dev.rustmodforge.core.ai

import dev.rustmodforge.core.model.BehaviourTrait
import dev.rustmodforge.core.model.TraitKind
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** A configured AI backend. Keys are the user's own and are stored encrypted by the app, never in projects. */
@Serializable
data class AiConfig(
    val kind: Kind,
    val baseUrl: String,
    val model: String,
    val apiKey: String = "",
    val maxOutputTokens: Int = 2048,
    /** Hard cap for one conversion; calls stop once it is reached. */
    val tokenBudget: Int = 200_000,
) {
    @Serializable
    enum class Kind { OPENAI_COMPATIBLE, ANTHROPIC }
}

data class AiReply(val text: String, val inputTokens: Int, val outputTokens: Int, val cached: Boolean)

interface AiProvider {
    fun complete(system: String, user: String, maxTokens: Int): AiReply
}

class AiException(message: String) : Exception(message)

private fun post(url: String, headers: Map<String, String>, body: String): String {
    val conn = URL(url).openConnection() as HttpURLConnection
    conn.requestMethod = "POST"
    conn.doOutput = true
    conn.connectTimeout = 20_000
    conn.readTimeout = 180_000
    conn.setRequestProperty("Content-Type", "application/json")
    headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
    conn.outputStream.use { it.write(body.toByteArray()) }
    val code = conn.responseCode
    val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: ""
    if (code !in 200..299) throw AiException("HTTP $code: ${text.take(400)}")
    return text
}

/** Any `/chat/completions` endpoint (OpenAI, OpenRouter, Groq, local servers). */
class OpenAiCompatibleProvider(private val c: AiConfig) : AiProvider {
    override fun complete(system: String, user: String, maxTokens: Int): AiReply {
        val body = buildJsonObject {
            put("model", c.model)
            put("max_tokens", maxTokens)
            put("temperature", 0.1)
            put("messages", buildJsonArray {
                add(buildJsonObject { put("role", "system"); put("content", system) })
                add(buildJsonObject { put("role", "user"); put("content", user) })
            })
        }.toString()
        val headers = if (c.apiKey.isNotBlank()) mapOf("Authorization" to "Bearer ${c.apiKey}") else emptyMap()
        val r = Json.parseToJsonElement(post(c.baseUrl.trimEnd('/') + "/chat/completions", headers, body)).jsonObject
        val text = r["choices"]?.jsonArray?.firstOrNull()?.jsonObject?.get("message")?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull
            ?: throw AiException("no message in the reply")
        val usage = r["usage"] as? JsonObject
        return AiReply(text, usage?.get("prompt_tokens")?.jsonPrimitive?.intOrNull ?: 0, usage?.get("completion_tokens")?.jsonPrimitive?.intOrNull ?: 0, false)
    }
}

/** Anthropic's Messages API. */
class AnthropicProvider(private val c: AiConfig) : AiProvider {
    override fun complete(system: String, user: String, maxTokens: Int): AiReply {
        val body = buildJsonObject {
            put("model", c.model)
            put("max_tokens", maxTokens)
            put("system", system)
            put("messages", buildJsonArray { add(buildJsonObject { put("role", "user"); put("content", user) }) })
        }.toString()
        val r = Json.parseToJsonElement(post(c.baseUrl.trimEnd('/') + "/v1/messages",
            mapOf("x-api-key" to c.apiKey, "anthropic-version" to "2023-06-01"), body)).jsonObject
        val text = r["content"]?.jsonArray?.filterIsInstance<JsonObject>()?.filter { it["type"]?.jsonPrimitive?.contentOrNull == "text" }
            ?.joinToString("") { it["text"]?.jsonPrimitive?.contentOrNull ?: "" } ?: throw AiException("no content in the reply")
        val usage = r["usage"] as? JsonObject
        return AiReply(text, usage?.get("input_tokens")?.jsonPrimitive?.int ?: 0, usage?.get("output_tokens")?.jsonPrimitive?.int ?: 0, false)
    }
}

/**
 * The context-efficient layer: one class (or one compiler error) per request, a cache keyed by
 * the exact prompt so a resumed conversion never pays twice, a token budget per conversion,
 * and answers constrained to a small JSON shape that is validated before it is used.
 */
class AiAssistant(private val config: AiConfig, private val cacheDir: File, private val provider: AiProvider = providerFor(config)) {
    var inputTokens = 0; private set
    var outputTokens = 0; private set
    var calls = 0; private set
    var cacheHits = 0; private set
    val log = ArrayList<String>()

    private fun key(s: String) = MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    fun ask(system: String, user: String, purpose: String): String? {
        val k = key(config.model + "\n" + system + "\n" + user)
        val f = File(cacheDir, "$k.txt")
        if (f.exists()) { cacheHits++; log += "$purpose: cached"; return f.readText() }
        if (inputTokens + outputTokens >= config.tokenBudget) { log += "$purpose: skipped, token budget of ${config.tokenBudget} reached"; return null }
        return try {
            val r = provider.complete(system, user, config.maxOutputTokens)
            calls++; inputTokens += r.inputTokens; outputTokens += r.outputTokens
            cacheDir.mkdirs(); f.writeText(r.text)
            log += "$purpose: ${r.inputTokens} in / ${r.outputTokens} out tokens"
            r.text
        } catch (e: Exception) {
            log += "$purpose: failed (${e.message})"
            null
        }
    }

    /**
     * Classifies a custom Java goal the rules did not recognise into the behaviours RustMod Forge
     * can rebuild. Only the class's own disassembly is sent, trimmed to [maxChars].
     */
    fun classifyGoal(className: String, disassembly: String, maxChars: Int = 12_000): List<BehaviourTrait> {
        val kinds = TraitKind.entries.joinToString { it.name }
        val system = "You analyse Minecraft Java mod bytecode for a tool that rebuilds behaviours on another engine. " +
            "Answer with JSON only: {\"traits\":[{\"kind\":KIND,\"params\":{name:number}}]} using only these kinds: $kinds. " +
            "Use params distance, keep_distance, duration_ticks where the code has those constants. Return an empty list when unsure. Never invent behaviour the code does not show."
        val user = "Class $className (ASM disassembly, possibly trimmed):\n" + disassembly.take(maxChars)
        val answer = ask(system, user, "classify $className") ?: return emptyList()
        return parseTraits(answer, className)
    }

    fun parseTraits(answer: String, className: String): List<BehaviourTrait> {
        val json = answer.substringAfter('{', "").let { "{$it" }.substringBeforeLast('}') + "}"
        val root = runCatching { Json.parseToJsonElement(json).jsonObject }.getOrNull() ?: return emptyList()
        return (root["traits"] as? JsonArray)?.mapNotNull { t ->
            val o = t as? JsonObject ?: return@mapNotNull null
            val kind = runCatching { TraitKind.valueOf(o["kind"]?.jsonPrimitive?.content ?: "") }.getOrNull() ?: return@mapNotNull null
            val params = (o["params"] as? JsonObject)?.mapNotNull { (k, v) -> (v as? JsonPrimitive)?.contentOrNull?.toDoubleOrNull()?.let { k to dev.rustmodforge.core.bytecode.Events.fmt(it) } }?.toMap() ?: emptyMap()
            BehaviourTrait(kind, params, listOf("${className.substringAfterLast('.')}: classified with AI assistance (${config.model})"))
        } ?: emptyList()
    }

    /**
     * Asks for a corrected version of one marked region of generated Rust, given the compiler's
     * errors. Only that region is sent and only that region can be replaced.
     */
    fun repairRegion(region: String, errors: String, apiNotes: String): String? {
        val system = "You fix Rust compile errors in generated code for the Horizon Minecraft engine. Use only the APIs listed in the notes. " +
            "Reply with the full corrected region between <region> and </region>, nothing else."
        val user = "API notes:\n$apiNotes\n\nCompiler errors:\n${errors.take(6000)}\n\n<region>\n$region\n</region>"
        val answer = ask(system, user, "repair") ?: return null
        return answer.substringAfter("<region>", "").substringBefore("</region>").trim().takeIf { it.isNotEmpty() }
    }

    fun usageSummary() = "$calls AI calls ($cacheHits answered from cache), $inputTokens input and $outputTokens output tokens, model ${config.model}"

    companion object {
        fun providerFor(c: AiConfig): AiProvider = when (c.kind) {
            AiConfig.Kind.OPENAI_COMPATIBLE -> OpenAiCompatibleProvider(c)
            AiConfig.Kind.ANTHROPIC -> AnthropicProvider(c)
        }
    }
}
