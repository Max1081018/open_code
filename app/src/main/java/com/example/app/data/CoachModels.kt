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

/** Everything the coach returns for one request. */
data class CoachReply(
    val read: String,
    val signals: List<String>,
    val suggestions: List<CoachSuggestion>,
    val caution: String = ""
)

/** A failure we can show the user verbatim. */
class CoachException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Where the coach sends its request. Any OpenAI-compatible endpoint works, so the
 * user can point this at OpenAI, OpenRouter, Groq or their own server.
 */
data class CoachConfig(
    val apiKey: String = "",
    val baseUrl: String = DEFAULT_BASE_URL,
    val model: String = DEFAULT_MODEL,
    /** How the user texts, in their own words. Sent with every request. */
    val myVoice: String = ""
) {
    val isReady: Boolean
        get() = apiKey.isNotBlank() && baseUrl.isNotBlank() && model.isNotBlank()

    /** What to show in the UI: "••••4f2a", never the whole key. */
    val maskedKey: String
        get() = when {
            apiKey.length <= 8 -> "••••"
            else -> "••••" + apiKey.takeLast(4)
        }

    companion object {
        const val DEFAULT_BASE_URL = "https://api.openai.com/v1"
        const val DEFAULT_MODEL = "gpt-4o-mini"
    }
}

/**
 * The prompt and the parser for the reply coach.
 *
 * This file is deliberately free of Android imports so it can be unit tested on
 * the JVM. It knows nothing about HTTP; see [OpenAiReplyEngine] for that.
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

Return four things.

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

Reply with JSON only, no prose and no code fence, exactly this shape:
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

    private fun extractJsonObject(raw: String): String? {
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
