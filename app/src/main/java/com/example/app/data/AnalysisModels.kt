package com.example.app.data

import org.json.JSONException
import org.json.JSONObject

/** A personality draft produced from one chat snapshot. */
data class PersonaDraft(
    val name: String = "",
    val summary: String = "",
    val vibe: String = "",
    val interests: String = "",
    val communicationStyle: String = "",
    val confidence: Float = 0f,
    val opener: String = "",
    val greenFlags: List<String> = emptyList(),
    val redFlags: List<String> = emptyList()
)

/** The profile plus the live read/replies for one scan. */
data class ScreenAnalysis(
    val person: PersonaDraft,
    val coach: CoachReply,
    val source: ReplySource = ReplySource.ONLINE,
    val notice: String = ""
)

/**
 * One request does everything: profile, read, signals and three replies. That
 * matters on a free tier where every extra call costs a 30 second wait.
 */
object AnalysisPrompt {

    val SYSTEM = """
You are Wingman, a social coach. You receive text captured from the user's screen while he was chatting with someone. The capture may contain app chrome and junk. Work out the real conversation, then analyse the person and the moment.

Think silently. Return one JSON object and nothing else, exactly this shape:
{"person":{"name":"","summary":"","vibe":"","interests":"","communicationStyle":"","confidence":0.0,"opener":"","greenFlags":[""],"redFlags":[""]},"read":"","signals":[""],"replies":[{"style":"curious","text":"","why":""},{"style":"playful","text":"","why":""},{"style":"direct","text":"","why":""}],"caution":""}

person
- "name": the other person's display name if it is visible. Do not guess a random word. Empty string if not visible.
- "summary": two or three sentences about who they seem to be, based only on this chat.
- "vibe": a short phrase, for example "dry, playful, a little guarded".
- "interests": what they actually talked about or showed interest in. Empty if nothing.
- "communicationStyle": how they write, message length, punctuation, slang, energy.
- "confidence": 0.0 to 1.0, how much evidence this chat gives you.
- "opener": one low-pressure opening line the user could use next time, in his voice.
- "greenFlags": up to three short positives visible in the chat.
- "redFlags": up to three short concerns. Empty if none. Never invent a red flag.

read, signals, replies, caution: same rules as a reply coach.
- "read": two to four sentences on what is actually happening, including when the honest answer is "they are being polite".
- "signals": two to four specific observations from the chat.
- "replies": exactly three complete messages in the user's voice: "curious", "playful", "direct".
- "caution": one short sentence if there is a real reason not to send anything, else "".

Hard rules.
- Use only evidence in the captured text. Never invent shared history, events or jokes.
- Match their message length. If they wrote five words, he does not send forty.
- At most one question per reply. Not every reply needs a question.
- Never compliment appearance. Never use pet names or "beautiful", "gorgeous", "hun", "babe".
- No emoji unless they used one first.
- If they asked something, answer it before adding anything else.
- If the chat is one-sided or dead, say so instead of manufacturing cleverness.
- Never mention coaching, this app, that the screen was captured, or that he is being advised.
""".trim()

    fun userMessage(
        appLabel: String,
        personName: String?,
        transcript: List<CoachLine>,
        theirStyle: String = "",
        myVoice: String = ""
    ): String {
        val fitted = ReplyCoach.fit(transcript)
        return buildString {
            if (appLabel.isNotBlank()) {
                append("CAPTURED FROM: ")
                append(appLabel)
                append("\n")
            }
            if (!personName.isNullOrBlank()) {
                append("NAME ON SCREEN: ")
                append(personName)
                append("\n")
            }
            if (theirStyle.isNotBlank()) {
                append("How they write (from his notes): ")
                append(theirStyle.trim())
                append("\n")
            }
            if (myVoice.isNotBlank()) {
                append("How he writes: ")
                append(myVoice.trim())
                append("\n")
            }
            append("\nCHAT (oldest first):\n")
            fitted.forEach {
                append(if (it.fromMe) "ME: " else "THEM: ")
                append(it.text.trim())
                append('\n')
            }
            if (fitted.isNotEmpty() && fitted.last().fromMe) {
                append("\nNOTE: his last message is still unanswered.")
            }
        }.trim()
    }
}

object AnalysisParser {

    fun parse(raw: String): ScreenAnalysis {
        val json = ReplyCoach.extractJsonObject(raw)
            ?: throw CoachException("The AI replied in a format the app could not read.")
        val root = try {
            JSONObject(json)
        } catch (e: JSONException) {
            throw CoachException("The AI replied in a format the app could not read.", e)
        }
        return parse(root)
    }

    fun parse(root: JSONObject): ScreenAnalysis {
        val coach = ReplyCoach.parse(root)
        val person = root.optJSONObject("person")
        val draft = PersonaDraft(
            name = person?.optString("name").orEmpty().trim(),
            summary = person?.optString("summary").orEmpty().trim(),
            vibe = person?.optString("vibe").orEmpty().trim(),
            interests = person?.optString("interests").orEmpty().trim(),
            communicationStyle = person?.optString("communicationStyle").orEmpty().trim(),
            confidence = person?.optDouble("confidence", 0.5)?.toFloat()?.coerceIn(0f, 1f) ?: 0.5f,
            opener = person?.optString("opener").orEmpty().trim(),
            greenFlags = person?.optJSONArray("greenFlags").toStringList(),
            redFlags = person?.optJSONArray("redFlags").toStringList()
        )
        return ScreenAnalysis(person = draft, coach = coach, source = ReplySource.ONLINE)
    }

    private fun org.json.JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { index ->
            optString(index).trim().ifBlank { null }
        }.take(3)
    }
}
