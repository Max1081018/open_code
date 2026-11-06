package com.example.app.data

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** One line of the chat as it will be handed to the coach. */
data class CoachLine(val fromMe: Boolean, val text: String)

/** One suggested reply, with the reasoning behind it. */
data class CoachSuggestion(
    val text: String,
    val why: String,
    val style: String
)

/** Where a result came from, so the UI never pretends offline output is AI output. */
enum class ReplySource(val label: String) {
    ONLINE("AI"),
    OFFLINE("On-device")
}

/** Everything the coach returns for one request. */
data class CoachReply(
    val read: String,
    val signals: List<String>,
    val suggestions: List<CoachSuggestion>,
    val caution: String = "",
    val source: ReplySource = ReplySource.ONLINE,
    val notice: String = ""
)

/** A failure we can show the user verbatim. */
class CoachException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** The free tier is busy. [retryAfterSeconds] is the provider's own number. */
class RateLimitException(
    val retryAfterSeconds: Long,
    message: String
) : CoachException(message)

/**
 * A free, no-signup provider that speaks the OpenAI chat-completions protocol.
 * Every provider below uses the same request shape, which keeps [RemoteAi] small.
 */
enum class AiProvider(
    val label: String,
    val shortLabel: String,
    val baseUrl: String,
    val model: String,
    val requiresKey: Boolean,
    val hint: String,
    val keyUrl: String,
    val fallbackModels: List<String>
) {
    FREE(
        label = "Free AI (no key)",
        shortLabel = "Free",
        baseUrl = "https://text.pollinations.ai/openai",
        model = "openai",
        requiresKey = false,
        hint = "Works out of the box. It is a shared free queue, so it allows about one request every 30 seconds. For instant replies, add a free Gemini or Groq key.",
        keyUrl = "https://enter.pollinations.ai",
        fallbackModels = listOf("openai", "openai-fast", "gpt-oss-20b")
    ),
    GEMINI(
        label = "Gemini (free key)",
        shortLabel = "Gemini",
        baseUrl = "https://generativelanguage.googleapis.com/v1beta/openai",
        model = "gemini-flash-latest",
        requiresKey = true,
        hint = "Free key from Google AI Studio. Fast, generous free tier, no card.",
        keyUrl = "https://aistudio.google.com/app/apikey",
        fallbackModels = listOf("gemini-flash-latest", "gemini-2.5-flash", "gemini-2.0-flash")
    ),
    GROQ(
        label = "Groq (free key)",
        shortLabel = "Groq",
        baseUrl = "https://api.groq.com/openai/v1",
        model = "llama-3.3-70b-versatile",
        requiresKey = true,
        hint = "Free key from Groq. The fastest option here.",
        keyUrl = "https://console.groq.com/keys",
        fallbackModels = listOf("llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b")
    ),
    OPENROUTER(
        label = "OpenRouter (free key)",
        shortLabel = "OpenRouter",
        baseUrl = "https://openrouter.ai/api/v1",
        model = "meta-llama/llama-3.3-70b-instruct:free",
        requiresKey = true,
        hint = "Free key from OpenRouter. Free model names change, so the app tries several.",
        keyUrl = "https://openrouter.ai/keys",
        fallbackModels = listOf(
            "meta-llama/llama-3.3-70b-instruct:free",
            "qwen/qwen-2.5-72b-instruct:free",
            "google/gemma-2-9b-it:free"
        )
    ),
    CUSTOM(
        label = "Custom endpoint",
        shortLabel = "Custom",
        baseUrl = "https://api.openai.com/v1",
        model = "gpt-4o-mini",
        requiresKey = true,
        hint = "Any OpenAI-compatible /chat/completions endpoint.",
        keyUrl = "",
        fallbackModels = emptyList()
    );

    companion object {
        fun fromName(name: String?): AiProvider =
            values().firstOrNull { it.name == name } ?: FREE
    }
}

/**
 * Where the coach sends its request. The default needs no key, so a fresh
 * install can produce a reply immediately.
 */
data class CoachConfig(
    val provider: AiProvider = AiProvider.FREE,
    val apiKey: String = "",
    val baseUrl: String = AiProvider.FREE.baseUrl,
    val model: String = AiProvider.FREE.model,
    /** How the user texts, in their own words. Sent with every request. */
    val myVoice: String = ""
) {
    val isReady: Boolean
        get() = baseUrl.isNotBlank() &&
            model.isNotBlank() &&
            (!provider.requiresKey || apiKey.isNotBlank())

    /** What to show in the UI: "••••4f2a", never the whole key. */
    val maskedKey: String
        get() = when {
            apiKey.length <= 8 -> "••••"
            else -> "••••" + apiKey.takeLast(4)
        }

    /** Models to try, in order, so a renamed model does not become a 404 dead end. */
    val modelCandidates: List<String>
        get() = (listOf(model.trim()) + provider.fallbackModels)
            .filter { it.isNotBlank() }
            .distinct()

    val endpoint: String
        get() = endpointFor(baseUrl, provider)

    companion object {
        const val DEFAULT_BASE_URL = "https://text.pollinations.ai/openai"
        const val DEFAULT_MODEL = "openai"

        fun forProvider(provider: AiProvider, apiKey: String = ""): CoachConfig =
            CoachConfig(
                provider = provider,
                apiKey = apiKey,
                baseUrl = provider.baseUrl,
                model = provider.model
            )

        /**
         * Free mode lives at /openai on Pollinations. Everything else is a
         * standard /chat/completions base URL. A user who pastes the full
         * endpoint is left alone.
         */
        fun endpointFor(rawBaseUrl: String, provider: AiProvider): String {
            val base = rawBaseUrl.trim().trimEnd('/')
            if (base.isEmpty()) throw CoachException("The base URL is empty. Check AI settings.")
            if (!base.startsWith("https://")) {
                throw CoachException("The base URL must start with https://")
            }
            return when {
                base.endsWith("/chat/completions") -> base
                provider == AiProvider.FREE && base.endsWith("/openai") -> base
                provider == AiProvider.FREE -> "$base/openai"
                else -> "$base/chat/completions"
            }
        }
    }
}

/**
 * The prompt and the parser for the reply coach.
 *
 * This file is deliberately free of Android imports so it can be unit tested on
 * the JVM. It knows nothing about HTTP; see [RemoteAi] for that.
 */
object ReplyCoach {

    /** Longest chat we will send, in characters. */
    const val MAX_USER_CHARS = 6_000

    /** Most lines we will send, oldest ones get dropped first. */
    const val MAX_LINES = 40

    /** Prompt for the model. Not a compile-time constant, so it is trimmed once. */
    val SYSTEM_PROMPT = """
You are a conversation coach. The user finds online chats hard to keep going and wants to get better at it. He is not looking for tricks or scripts; he wants the conversation to feel natural.

You receive the last part of a chat, oldest first. Lines beginning "ME:" are his. Lines beginning "THEM:" are theirs. You may also receive notes on how each of them writes.

Think silently. Return one JSON object and nothing else.

1. "read": two to four sentences on what is actually happening. Their interest, energy and tone. Whether they are warm, polite, busy, or fading. What they seem to want from this conversation. If they are not interested, say it plainly instead of being encouraging.

2. "signals": two to four very short observations that support the read, each pointing at something specific in the chat.

3. "replies": exactly three options, genuinely different in intent, all in his voice.
   - "curious": follows up on something specific they said, keeps the thread alive
   - "playful": light, a small joke or gentle tease, never at their expense
   - "direct": plain and low pressure, no games, no performance
   Every reply must be a complete message he could send right now, not advice about what to say.

4. "caution": one short sentence if there is a real reason not to send anything. Empty string if there is not.

Hard rules.
- Match their message length. If they wrote five words, he does not send forty.
- At most one question per message. Not every option needs a question.
- Never compliment their appearance. Never use pet names, never "beautiful", "gorgeous", "hun", "babe".
- Never invent shared history, inside jokes or events that are not in the chat.
- No emoji unless they used one first.
- Do not interview them. Do not stack questions.
- If they asked something, answer it before adding anything else.
- If the chat is one-sided or dead, do not manufacture cleverness. Say so in "read" and "caution".
- Never mention coaching, this app, or that he is being advised.

Return JSON only, no prose and no code fence, exactly this shape:
{"read": "...", "signals": ["...", "..."], "replies": [{"style": "curious", "text": "...", "why": "..."}, {"style": "playful", "text": "...", "why": "..."}, {"style": "direct", "text": "...", "why": "..."}], "caution": "..."}
""".trim()

    /**
     * Turns the editable transcript box into lines. Anything starting with
     * "me:", "you:" or ">" belongs to the user, everything else is theirs.
     */
    fun parseTranscript(raw: String): List<CoachLine> =
        raw.lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .map { line ->
                val lower = line.lowercase()
                when {
                    lower.startsWith("me:") -> CoachLine(true, line.drop(3).trim())
                    lower.startsWith("you:") -> CoachLine(true, line.drop(4).trim())
                    line.startsWith(">") -> CoachLine(true, line.drop(1).trim())
                    lower.startsWith("them:") -> CoachLine(false, line.drop(5).trim())
                    lower.startsWith("her:") -> CoachLine(false, line.drop(4).trim())
                    lower.startsWith("she:") -> CoachLine(false, line.drop(4).trim())
                    lower.startsWith("he:") -> CoachLine(false, line.drop(3).trim())
                    lower.startsWith("him:") -> CoachLine(false, line.drop(4).trim())
                    else -> CoachLine(false, line)
                }
            }
            .filter { it.text.isNotEmpty() }

    /** The transcript as it should be formatted before the user edits it. */
    fun formatTranscript(lines: List<CoachLine>): String =
        lines.joinToString("\n") { (if (it.fromMe) "Me: " else "Them: ") + it.text.trim() }

    fun userMessage(
        lines: List<CoachLine>,
        theirStyle: String = "",
        myVoice: String = "",
        paused: Boolean = false
    ): String {
        val trimmed = fit(lines)
        return buildString {
            if (theirStyle.isNotBlank()) {
                append("How they write (from his notes): ")
                append(theirStyle.trim())
                append("\n\n")
            }
            if (myVoice.isNotBlank()) {
                append("How he writes: ")
                append(myVoice.trim())
                append("\n\n")
            }
            if (paused) {
                append("He has marked this conversation as paused, so the honest answer ")
                append("may be that he should not send anything yet.\n\n")
            }
            append("CHAT (oldest first):\n")
            trimmed.forEach {
                append(if (it.fromMe) "ME: " else "THEM: ")
                append(it.text.trim())
                append('\n')
            }
            if (trimmed.isNotEmpty() && trimmed.last().fromMe) {
                append("\nNOTE: his last message is still unanswered.")
            }
        }.trim()
    }

    /** Drops the oldest lines until the request fits our size budget. */
    fun fit(lines: List<CoachLine>): List<CoachLine> {
        val cleaned = lines
            .map { CoachLine(it.fromMe, it.text.trim()) }
            .filter { it.text.isNotEmpty() }
        var kept = if (cleaned.size > MAX_LINES) cleaned.takeLast(MAX_LINES) else cleaned

        fun size(of: List<CoachLine>): Int = of.sumOf { it.text.length + 6 }
        while (kept.size > 1 && size(kept) > MAX_USER_CHARS) {
            kept = kept.drop(1)
        }
        return kept
    }

    /**
     * Parses the model's JSON. Tolerates a stray code fence or leading prose,
     * because every provider gets this wrong occasionally.
     */
    fun parse(raw: String): CoachReply {
        val json = extractJsonObject(raw)
            ?: throw CoachException("The coach replied in a format the app could not read.")

        val root = try {
            JSONObject(json)
        } catch (e: JSONException) {
            throw CoachException("The coach replied in a format the app could not read.", e)
        }
        return parse(root)
    }

    /** Parses an already-decoded object. Shared with the screen-analysis parser. */
    fun parse(root: JSONObject): CoachReply {
        val read = root.optString("read").trim()
        val signals = root.optJSONArray("signals").stringList()
        val rawReplies = root.optJSONArray("replies") ?: root.optJSONArray("suggestions")
            ?: throw CoachException("The coach did not send any replies. Try again.")

        val suggestions = (0 until rawReplies.length()).mapNotNull { index ->
            val item = rawReplies.optJSONObject(index) ?: return@mapNotNull null
            val text = item.optString("text").trim().ifBlank { item.optString("reply").trim() }
            if (text.isBlank()) return@mapNotNull null
            CoachSuggestion(
                text = text,
                why = item.optString("why").trim(),
                style = item.optString("style").trim().ifBlank { "option" }
            )
        }

        if (suggestions.isEmpty()) {
            throw CoachException("The coach did not send any replies. Try again.")
        }

        return CoachReply(
            read = read.ifBlank { "No read back from the model." },
            signals = signals,
            suggestions = suggestions.take(4),
            caution = root.optString("caution").trim()
        )
    }

    /** Exposed so [AnalysisParser] can decode one provider response once. */
    fun extractJsonObject(raw: String): String? {
        val start = raw.indexOf('{')
        val end = raw.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return raw.substring(start, end + 1)
    }

    private fun JSONArray?.stringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { index ->
            optString(index).trim().ifBlank { null }
        }
    }
}
