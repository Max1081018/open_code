package com.example.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException

/** Anything that can turn a chat into suggestions. Swappable for tests. */
interface ReplyEngine {
    suspend fun suggest(
        lines: List<CoachLine>,
        theirStyle: String,
        myVoice: String,
        paused: Boolean
    ): CoachReply
}

/**
 * Talks to any OpenAI-compatible /chat/completions endpoint.
 *
 * Only the transcript the user has in the box, their own style note and the
 * notes on how the other person writes are sent. Names, handles and the private
 * friend notes are never part of the request.
 */
class OpenAiReplyEngine(private val config: CoachConfig) : ReplyEngine {

    override suspend fun suggest(
        lines: List<CoachLine>,
        theirStyle: String,
        myVoice: String,
        paused: Boolean
    ): CoachReply = withContext(Dispatchers.IO) {
        if (config.apiKey.isBlank()) {
            throw CoachException("No API key yet. Add one in the coach settings.")
        }

        val endpoint = chatEndpoint(config.baseUrl)
        val body = JSONObject().apply {
            put("model", config.model)
            put("temperature", 0.8)
            put("max_tokens", 900)
            put("response_format", JSONObject().put("type", "json_object"))
            put(
                "messages",
                JSONArray().apply {
                    put(JSONObject().put("role", "system").put("content", ReplyCoach.SYSTEM_PROMPT))
                    put(
                        JSONObject().put("role", "user").put(
                            "content",
                            ReplyCoach.userMessage(lines, theirStyle, myVoice, paused)
                        )
                    )
                }
            )
        }

        val connection = try {
            (URL(endpoint).openConnection() as HttpURLConnection)
        } catch (e: IOException) {
            throw CoachException("That base URL is not valid. Check it in the coach settings.", e)
        }

        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 15_000
            connection.readTimeout = 60_000
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer ${config.apiKey.trim()}")
            connection.setRequestProperty("Accept", "application/json")

            connection.outputStream.use { out ->
                out.write(body.toString().toByteArray(Charsets.UTF_8))
            }

            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val payload = stream?.bufferedReader()?.use { it.readText() }.orEmpty()

            if (code !in 200..299) {
                throw CoachException(friendlyError(code, payload))
            }

            val content = extractContent(payload)
            ReplyCoach.parse(content)
        } catch (e: SocketTimeoutException) {
            throw CoachException("The provider took too long to answer. Try again.", e)
        } catch (e: UnknownHostException) {
            throw CoachException("Could not reach the provider. Check your connection.", e)
        } catch (e: CoachException) {
            throw e
        } catch (e: IOException) {
            throw CoachException("Could not reach the provider. Check your connection.", e)
        } finally {
            connection.disconnect()
        }
    }

    private fun extractContent(payload: String): String = try {
        JSONObject(payload)
            .getJSONArray("choices")
            .getJSONObject(0)
            .getJSONObject("message")
            .getString("content")
    } catch (e: JSONException) {
        throw CoachException("The provider sent something unexpected. Try again.", e)
    }

    private fun friendlyError(code: Int, payload: String): String = when (code) {
        401, 403 -> "The API key was rejected. Check it in the coach settings."
        404 -> "That model or base URL does not exist on this provider."
        413 -> "That chat was too long for the model. Trim the transcript."
        429 -> "Rate limited or out of credit on that key. Try again shortly."
        in 500..599 -> "The provider is having a problem (HTTP $code). Try again."
        else -> "Request failed (HTTP $code). ${payload.take(160).trim()}"
    }

    private fun chatEndpoint(baseUrl: String): String {
        val base = baseUrl.trim().trimEnd('/')
        require(base.isNotEmpty()) { "empty base url" }
        if (!base.startsWith("https://")) {
            throw CoachException("The base URL must start with https://")
        }
        return if (base.endsWith("/chat/completions")) base else "$base/chat/completions"
    }
}
