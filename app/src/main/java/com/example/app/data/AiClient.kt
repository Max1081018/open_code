package com.example.app.data

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException

/** Anything that can analyse a chat and suggest replies. Swappable for tests. */
interface WingmanAi {
    suspend fun suggest(
        lines: List<CoachLine>,
        theirStyle: String,
        myVoice: String,
        paused: Boolean
    ): CoachReply

    suspend fun analyze(
        appLabel: String,
        personName: String?,
        transcript: List<CoachLine>,
        theirStyle: String,
        myVoice: String
    ): ScreenAnalysis

    /** Returns the model that answered, so settings can show a real result. */
    suspend fun test(): String
}

private class ModelUnavailable(message: String) : Exception(message)

/**
 * Talks to a free or user-configured OpenAI-compatible endpoint.
 *
 * The default provider needs no key. Model names are retried against a
 * provider-specific fallback list, which is what stops a renamed free model
 * from turning into a permanent 404.
 */
class RemoteAi(private val config: CoachConfig) : WingmanAi {

    override suspend fun suggest(
        lines: List<CoachLine>,
        theirStyle: String,
        myVoice: String,
        paused: Boolean
    ): CoachReply = withContext(Dispatchers.IO) {
        val content = post(
            system = ReplyCoach.SYSTEM_PROMPT,
            user = ReplyCoach.userMessage(lines, theirStyle, myVoice, paused),
            maxTokens = 2_200
        )
        ReplyCoach.parse(content.content)
    }

    override suspend fun analyze(
        appLabel: String,
        personName: String?,
        transcript: List<CoachLine>,
        theirStyle: String,
        myVoice: String
    ): ScreenAnalysis = withContext(Dispatchers.IO) {
        val content = post(
            system = AnalysisPrompt.SYSTEM,
            user = AnalysisPrompt.userMessage(appLabel, personName, transcript, theirStyle, myVoice),
            maxTokens = 2_600
        )
        AnalysisParser.parse(content.content)
    }

    override suspend fun test(): String = withContext(Dispatchers.IO) {
        val content = post(
            system = "You are a connection test. Reply with the single word OK and nothing else.",
            user = "Reply with OK.",
            maxTokens = 400
        )
        if (content.content.isBlank()) throw CoachException("The test got an empty answer.")
        content.model
    }

    private data class AiText(val content: String, val model: String)

    private suspend fun post(system: String, user: String, maxTokens: Int): AiText {
        if (!config.isReady) {
            throw CoachException(
                if (config.provider.requiresKey) {
                    "Add a free ${config.provider.shortLabel} API key in AI settings."
                } else {
                    "AI settings are incomplete."
                }
            )
        }
        val endpoint = try {
            config.endpoint
        } catch (e: CoachException) {
            throw e
        } catch (e: Exception) {
            throw CoachException("That base URL is not valid. Check AI settings.", e)
        }

        var lastProblem: String? = null
        for (model in config.modelCandidates) {
            var attempt = 0
            while (attempt < 2) {
                attempt++
                try {
                    return execute(endpoint, model, system, user, maxTokens)
                } catch (e: ModelUnavailable) {
                    lastProblem = e.message
                    break
                } catch (e: RateLimitException) {
                    throw e
                } catch (e: CoachException) {
                    throw e
                } catch (e: SocketTimeoutException) {
                    lastProblem = "The provider took too long to answer."
                    if (attempt < 2) delay(900)
                } catch (e: UnknownHostException) {
                    throw CoachException("Could not reach the AI. Check your connection.", e)
                } catch (e: IOException) {
                    throw CoachException("Could not reach the AI. Check your connection.", e)
                } catch (e: Exception) {
                    lastProblem = e.message ?: e.javaClass.simpleName
                    break
                }
            }
        }
        throw CoachException(
            lastProblem ?: "No working model was available. Try Free AI again or pick another provider."
        )
    }

    private fun execute(
        endpoint: String,
        model: String,
        system: String,
        user: String,
        maxTokens: Int
    ): AiText {
        val body = JSONObject().apply {
            put("model", model)
            put("temperature", 0.8)
            put("max_tokens", maxTokens)
            put("stream", false)
            put(
                "messages",
                JSONArray().apply {
                    put(JSONObject().put("role", "system").put("content", system))
                    put(JSONObject().put("role", "user").put("content", user))
                }
            )
        }

        val connection = try {
            (URL(endpoint).openConnection() as HttpURLConnection)
        } catch (e: IOException) {
            throw CoachException("That base URL is not valid. Check AI settings.", e)
        }

        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 90_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "Wingman/2.0 (Android)")
            if (config.apiKey.isNotBlank()) {
                connection.setRequestProperty("Authorization", "Bearer ${config.apiKey.trim()}")
            }
            if (config.provider == AiProvider.OPENROUTER) {
                connection.setRequestProperty("HTTP-Referer", "https://github.com/Max1081018/open_code")
                connection.setRequestProperty("X-Title", "Wingman")
            }

            connection.outputStream.use { out ->
                out.write(body.toString().toByteArray(Charsets.UTF_8))
            }

            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val payload = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()

            if (code in 200..299) {
                val content = extractContent(payload)
                if (content.isBlank()) {
                    throw ModelUnavailable("The model returned an empty answer.")
                }
                return AiText(content, model)
            }

            when {
                code == 401 || code == 403 -> throw CoachException(
                    "The API key was rejected. Check the free key in AI settings."
                )
                code == 402 || code == 429 -> {
                    val wait = retrySeconds(payload, connection.getHeaderField("Retry-After"))
                    throw RateLimitException(
                        wait,
                        "The free AI is busy. Try again in ${wait}s, or add a free key in AI settings."
                    )
                }
                code == 404 -> throw ModelUnavailable("Model '$model' does not exist on this provider.")
                code == 413 -> throw CoachException("That chat was too long for the model. Trim it and retry.")
                code in 500..599 -> throw ModelUnavailable("The provider had a problem (HTTP $code).")
                code == 400 -> throw ModelUnavailable(friendlyBody(payload))
                else -> throw CoachException("Request failed (HTTP $code). ${friendlyBody(payload)}")
            }
        } catch (e: SocketTimeoutException) {
            throw e
        } catch (e: UnknownHostException) {
            throw e
        } catch (e: IOException) {
            throw e
        } finally {
            connection.disconnect()
        }
    }

    private fun extractContent(payload: String): String = try {
        val root = JSONObject(payload)
        val message = root
            .getJSONArray("choices")
            .getJSONObject(0)
            .getJSONObject("message")
        when (val content = message.opt("content")) {
            is String -> content
            is JSONArray -> (0 until content.length()).joinToString("") { index ->
                content.optJSONObject(index)?.optString("text").orEmpty()
            }
            else -> ""
        }
    } catch (e: JSONException) {
        throw CoachException("The provider sent something unexpected. Try again.", e)
    }

    private fun retrySeconds(payload: String, header: String?): Long {
        header?.trim()?.toLongOrNull()?.let { return it.coerceIn(1, 120) }
        val match = Regex("retry after\\s+(\\d+)", RegexOption.IGNORE_CASE).find(payload)
        return match?.groupValues?.getOrNull(1)?.toLongOrNull()?.coerceIn(1, 120) ?: 30
    }

    private fun friendlyBody(payload: String): String {
        val fromJson = runCatching {
            JSONObject(payload).optJSONObject("error")?.optString("message").orEmpty()
        }.getOrNull().orEmpty()
        val text = fromJson.ifBlank { payload }
        return text.take(180).trim().ifBlank { "No details from the provider." }
    }
}

/**
 * The safety net. A free provider can be busy or offline; the app still has to
 * give the user something useful instead of an error screen.
 */
class ResilientWingman(private val remote: WingmanAi) : WingmanAi {

    override suspend fun suggest(
        lines: List<CoachLine>,
        theirStyle: String,
        myVoice: String,
        paused: Boolean
    ): CoachReply = try {
        remote.suggest(lines, theirStyle, myVoice, paused)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        LocalWingman.suggest(lines, paused).copy(
            source = ReplySource.OFFLINE,
            notice = noticeFor(e)
        )
    }

    override suspend fun analyze(
        appLabel: String,
        personName: String?,
        transcript: List<CoachLine>,
        theirStyle: String,
        myVoice: String
    ): ScreenAnalysis = try {
        remote.analyze(appLabel, personName, transcript, theirStyle, myVoice)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        LocalWingman.analyze(personName.orEmpty(), transcript, theirStyle).copy(
            source = ReplySource.OFFLINE,
            notice = noticeFor(e)
        )
    }

    override suspend fun test(): String = remote.test()

    private fun noticeFor(e: Exception): String = when (e) {
        is RateLimitException -> "AI is busy right now. Showing on-device suggestions. ${e.message}"
        is CoachException -> "AI unavailable. Showing on-device suggestions. ${e.message}"
        else -> "AI unavailable. Showing on-device suggestions."
    }
}
