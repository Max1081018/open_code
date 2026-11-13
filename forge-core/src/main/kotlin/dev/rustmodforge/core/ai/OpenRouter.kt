package dev.rustmodforge.core.ai

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

/** One model as OpenRouter's catalog lists it (`GET /api/v1/models`). */
@Serializable
data class CatalogModel(
    val id: String,
    val name: String = "",
    val contextLength: Int = 0,
    /** Price per prompt and completion token as the catalog gives them; "0" means free. */
    val promptPrice: String = "",
    val completionPrice: String = "",
) {
    /** Free on OpenRouter: priced at zero, or the `:free` variant / router. */
    val isFree: Boolean get() = id.endsWith(":free") || id == "openrouter/free" ||
        (promptPrice.toDoubleOrNull() == 0.0 && completionPrice.toDoubleOrNull() == 0.0)
}

/** One request, for the history the app shows. */
@Serializable
data class AiRequestRecord(
    val time: Long,
    val model: String,
    val purpose: String,
    val status: String,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val millis: Long = 0,
    val note: String = "",
)

/**
 * Every free model the user allowed is exhausted, or the service is down: the conversion must
 * stop here and keep its progress, never switch to a paid model on its own.
 */
class AiPausedException(message: String) : Exception(message)

/** Why a request failed, so the fallback can decide what to do. */
sealed class RequestFailure(message: String) : Exception(message) {
    class RateLimited(model: String, val retryAfterSeconds: Int?) : RequestFailure("$model is rate-limited")
    class Unauthorized(detail: String) : RequestFailure("the API key was refused: $detail")
    class ModelUnavailable(model: String, detail: String) : RequestFailure("$model is unavailable: $detail")
    class ServerError(model: String, code: Int) : RequestFailure("$model answered $code")
    class Timeout(model: String) : RequestFailure("$model timed out")
    class Malformed(model: String, detail: String) : RequestFailure("$model gave an unreadable answer: $detail")
}

/**
 * OpenRouter (`/api/v1/chat/completions`) with a preference list of free models and automatic
 * fallback. A model that answers 429 is rested for its `Retry-After` (or two minutes); a 5xx or
 * timeout is retried once on the same model, then the next one is tried; 401/403 stops at once.
 * When every allowed model is resting or failed, [AiPausedException] is thrown so the caller
 * pauses the conversion with its progress kept. Only free models are ever used unless the user
 * explicitly allows a paid one.
 */
class OpenRouterProvider(
    private val apiKey: String,
    preferredModels: List<String>,
    private val allowPaid: Boolean = false,
    private val baseUrl: String = "https://openrouter.ai/api/v1",
    private val historyFile: File? = null,
    private val connectTimeoutMs: Int = 20_000,
    private val readTimeoutMs: Int = 150_000,
    /** Replaceable in tests; production uses the real network. */
    private val transport: Transport = HttpTransport(),
    private val clock: () -> Long = System::currentTimeMillis,
) : AiProvider {
    interface Transport {
        /** Returns (HTTP status, body, headers) or throws IOException. */
        fun post(url: String, headers: Map<String, String>, body: String, connectMs: Int, readMs: Int): Response
        fun get(url: String, headers: Map<String, String>, connectMs: Int, readMs: Int): Response
    }
    data class Response(val code: Int, val body: String, val headers: Map<String, String> = emptyMap())

    class HttpTransport : Transport {
        private fun run(url: String, method: String, headers: Map<String, String>, body: String?, connectMs: Int, readMs: Int): Response {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.requestMethod = method
            conn.connectTimeout = connectMs
            conn.readTimeout = readMs
            headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
            if (body != null) {
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                conn.outputStream.use { it.write(body.toByteArray()) }
            }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: ""
            val hs = conn.headerFields.filterKeys { it != null }.mapKeys { it.key.lowercase() }.mapValues { it.value.joinToString(",") }
            return Response(code, text, hs)
        }
        override fun post(url: String, headers: Map<String, String>, body: String, connectMs: Int, readMs: Int) = run(url, "POST", headers, body, connectMs, readMs)
        override fun get(url: String, headers: Map<String, String>, connectMs: Int, readMs: Int) = run(url, "GET", headers, null, connectMs, readMs)
    }

    /** The user's order of preference; the catalog decides which of them exist and are free. */
    val preferred: List<String> = preferredModels.map { it.trim() }.filter { it.isNotEmpty() }.distinct()

    /** Models resting after a 429, until the given time. */
    private val resting = LinkedHashMap<String, Long>()
    private val failed = LinkedHashSet<String>()
    private var catalog: List<CatalogModel>? = null
    val history = ArrayList<AiRequestRecord>()
    var purpose: String = "request"
    val tokensByModel = LinkedHashMap<String, IntArray>()

    private fun headers() = buildMap {
        put("Authorization", "Bearer $apiKey")
        put("HTTP-Referer", "https://github.com/rustmod-forge")
        put("X-Title", "RustMod Forge")
    }

    /** The live catalog. Fetched once per provider; [refreshCatalog] re-reads it. */
    fun catalog(): List<CatalogModel> = catalog ?: refreshCatalog()

    fun refreshCatalog(): List<CatalogModel> {
        val r = try { transport.get("$baseUrl/models", headers(), connectTimeoutMs, 30_000) } catch (e: IOException) {
            throw RequestFailure.ServerError("catalog", 0).also { record("catalog", "failed", note = e.message ?: "network") }
        }
        if (r.code == 401 || r.code == 403) throw RequestFailure.Unauthorized(r.body.take(200))
        if (r.code !in 200..299) throw RequestFailure.ServerError("catalog", r.code)
        val data = runCatching { Json.parseToJsonElement(r.body).jsonObject["data"]?.jsonArray }.getOrNull()
            ?: throw RequestFailure.Malformed("catalog", r.body.take(200))
        val list = data.mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val pricing = o["pricing"] as? JsonObject
            CatalogModel(
                id = o["id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null,
                name = o["name"]?.jsonPrimitive?.contentOrNull ?: "",
                contextLength = o["context_length"]?.jsonPrimitive?.intOrNull ?: 0,
                promptPrice = pricing?.get("prompt")?.jsonPrimitive?.contentOrNull ?: "",
                completionPrice = pricing?.get("completion")?.jsonPrimitive?.contentOrNull ?: "",
            )
        }
        catalog = list
        record("catalog", "ok", note = "${list.size} models, ${list.count { it.isFree }} free")
        return list
    }

    /** Which preferred models the catalog has, and whether each is free. */
    fun availability(): List<Pair<String, String>> {
        val cat = runCatching { catalog() }.getOrElse { return preferred.map { it to "catalog unavailable: ${it}" } }
        return preferred.map { id ->
            val m = cat.firstOrNull { it.id == id }
            id to when {
                m == null -> "not in OpenRouter's catalog right now"
                m.isFree -> "available, free" + (if (m.contextLength > 0) ", ${m.contextLength / 1000}k context" else "")
                allowPaid -> "available, paid (allowed)"
                else -> "available but paid: skipped"
            }
        }
    }

    /**
     * The models to try, in order: the preferred ones the catalog lists (free unless paid is
     * allowed), then every other free model the catalog has as a last resort, with `openrouter/free`
     * (OpenRouter's own router over free models) first among those. Resting or failed models
     * are left out.
     */
    fun candidates(): List<String> {
        val cat = runCatching { catalog() }.getOrNull()
        val now = clock()
        fun usable(id: String): Boolean {
            if (id in failed) return false
            val until = resting[id]
            if (until != null && until > now) return false
            if (cat == null) return true
            val m = cat.firstOrNull { it.id == id } ?: return false
            return m.isFree || allowPaid
        }
        val ordered = ArrayList<String>()
        preferred.filter(::usable).forEach { ordered += it }
        if (cat != null) {
            if ("openrouter/free" !in ordered && usable("openrouter/free") && cat.any { it.id == "openrouter/free" }) ordered += "openrouter/free"
            cat.filter { it.isFree && it.id !in ordered && usable(it.id) }.sortedByDescending { it.contextLength }.forEach { ordered += it.id }
        }
        return ordered
    }

    override fun complete(system: String, user: String, maxTokens: Int): AiReply {
        val tried = ArrayList<String>()
        for (model in candidates()) {
            tried += model
            var attempt = 0
            while (attempt < 2) {
                attempt++
                val started = clock()
                try {
                    val reply = once(model, system, user, maxTokens)
                    record(model, "ok", reply.inputTokens, reply.outputTokens, clock() - started)
                    tokensByModel.getOrPut(model) { IntArray(2) }.let { it[0] += reply.inputTokens; it[1] += reply.outputTokens }
                    return reply
                } catch (e: RequestFailure.RateLimited) {
                    resting[model] = clock() + (e.retryAfterSeconds ?: 120) * 1000L
                    record(model, "rate-limited", millis = clock() - started, note = "resting ${e.retryAfterSeconds ?: 120}s")
                    break
                } catch (e: RequestFailure.Unauthorized) {
                    record(model, "unauthorized", millis = clock() - started, note = e.message ?: "")
                    throw AiPausedException("OpenRouter refused the API key: check it in Settings › AI engine.")
                } catch (e: RequestFailure.ModelUnavailable) {
                    failed += model
                    record(model, "unavailable", millis = clock() - started, note = e.message ?: "")
                    break
                } catch (e: RequestFailure.ServerError) {
                    record(model, "server error", millis = clock() - started, note = e.message ?: "")
                    if (attempt >= 2) failed += model
                } catch (e: RequestFailure.Timeout) {
                    record(model, "timeout", millis = clock() - started)
                    if (attempt >= 2) resting[model] = clock() + 60_000
                } catch (e: RequestFailure.Malformed) {
                    record(model, "malformed", millis = clock() - started, note = e.message ?: "")
                    if (attempt >= 2) failed += model
                }
            }
        }
        val soonest = resting.values.minOrNull()?.let { ((it - clock()) / 1000).coerceAtLeast(0) }
        throw AiPausedException(
            if (tried.isEmpty()) "No free model is available: none of the preferred models is in OpenRouter's catalog as free, and the catalog lists no other free model."
            else "Every free model is rate-limited or failing (${tried.joinToString()}). Paused with progress kept" +
                (soonest?.let { "; the soonest one frees in about ${it}s." } ?: "."),
        )
    }

    private fun once(model: String, system: String, user: String, maxTokens: Int): AiReply {
        val body = buildJsonObject {
            put("model", model)
            put("max_tokens", maxTokens)
            put("temperature", 0.1)
            put("messages", buildJsonArray {
                add(buildJsonObject { put("role", "system"); put("content", system) })
                add(buildJsonObject { put("role", "user"); put("content", user) })
            })
        }.toString()
        val r = try {
            transport.post("$baseUrl/chat/completions", headers(), body, connectTimeoutMs, readTimeoutMs)
        } catch (e: SocketTimeoutException) {
            throw RequestFailure.Timeout(model)
        } catch (e: IOException) {
            throw RequestFailure.ServerError(model, 0)
        }
        when {
            r.code == 429 -> throw RequestFailure.RateLimited(model, r.headers["retry-after"]?.trim()?.toIntOrNull())
            r.code == 401 || r.code == 403 -> throw RequestFailure.Unauthorized(r.body.take(200))
            r.code == 404 || r.code == 400 && r.body.contains("model", ignoreCase = true) -> throw RequestFailure.ModelUnavailable(model, r.body.take(200))
            r.code == 408 || r.code == 504 -> throw RequestFailure.Timeout(model)
            r.code >= 500 -> throw RequestFailure.ServerError(model, r.code)
            r.code !in 200..299 -> throw RequestFailure.ServerError(model, r.code)
        }
        val root = runCatching { Json.parseToJsonElement(r.body).jsonObject }.getOrNull() ?: throw RequestFailure.Malformed(model, r.body.take(200))
        // OpenRouter reports some upstream failures as 200 with an error object.
        (root["error"] as? JsonObject)?.let { err ->
            val code = err["code"]?.jsonPrimitive?.intOrNull ?: 0
            val msg = err["message"]?.jsonPrimitive?.contentOrNull ?: "error"
            if (code == 429) throw RequestFailure.RateLimited(model, null)
            throw RequestFailure.ModelUnavailable(model, msg)
        }
        val text = root["choices"]?.jsonArray?.firstOrNull()?.jsonObject?.get("message")?.jsonObject?.get("content")?.jsonPrimitive?.contentOrNull
            ?: throw RequestFailure.Malformed(model, "no message")
        val usage = root["usage"] as? JsonObject
        return AiReply(text, usage?.get("prompt_tokens")?.jsonPrimitive?.intOrNull ?: 0, usage?.get("completion_tokens")?.jsonPrimitive?.intOrNull ?: 0, false)
    }

    private fun record(model: String, status: String, input: Int = 0, output: Int = 0, millis: Long = 0, note: String = "") {
        val rec = AiRequestRecord(clock(), model, purpose, status, input, output, millis, note)
        history += rec
        historyFile?.let { f ->
            runCatching {
                f.parentFile?.mkdirs()
                f.appendText(Json.encodeToString(AiRequestRecord.serializer(), rec) + "\n")
            }
        }
    }

    companion object {
        /** The models the user asked for, in order; the live catalog decides which exist. */
        val DEFAULT_PREFERRED = listOf(
            "recursive/flint-v1.0:free",
            "cohere/north-mini-code:free",
            "thinkingmachines/inkling-2-small:free",
            "openrouter/free",
        )

        fun readHistory(file: File): List<AiRequestRecord> =
            if (!file.exists()) emptyList() else file.readLines().mapNotNull { l -> runCatching { Json.decodeFromString(AiRequestRecord.serializer(), l) }.getOrNull() }
    }
}
