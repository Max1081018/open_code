package com.example.app.data

/**
 * The on-device safety net.
 *
 * The free provider can be busy, rate limited or offline. When that happens the
 * app still has to return a usable read and three replies, and it has to be
 * honest that they did not come from a model. Everything here is deterministic
 * and derived only from the captured chat.
 */
object LocalWingman {

    private val STOPWORDS = setOf(
        "the", "and", "you", "your", "yours", "for", "with", "that", "this", "have",
        "just", "from", "they", "them", "their", "there", "here", "what", "when",
        "where", "which", "who", "how", "why", "are", "was", "were", "been", "being",
        "not", "but", "can", "could", "would", "should", "will", "wont", "dont",
        "didnt", "doesnt", "about", "into", "over", "under", "then", "than", "too",
        "very", "really", "some", "any", "all", "out", "its", "it's", "im", "i'm",
        "ive", "i've", "hey", "hii", "haha", "yeah", "okay", "ok", "lol", "like",
        "know", "think", "going", "gonna", "want", "good", "well", "much", "more",
        "she", "him", "her", "his", "has", "had", "did", "does", "get", "got",
        "make", "made", "time", "day", "today", "tomorrow", "tonight", "one", "two",
        "people", "thing", "things", "something", "anything", "because", "before",
        "after", "still", "even", "back", "now", "new", "old", "way", "say", "said"
    )

    fun analyze(
        personName: String,
        transcript: List<CoachLine>,
        theirStyle: String = ""
    ): ScreenAnalysis {
        val lines = transcript
            .map { CoachLine(it.fromMe, it.text.trim()) }
            .filter { it.text.isNotEmpty() }
        val theirs = lines.filter { !it.fromMe }
        val mine = lines.filter { it.fromMe }
        val last = lines.lastOrNull()

        val name = personName.trim()
        val label = name.ifBlank { "They" }
        val averageLength = if (theirs.isEmpty()) 0 else theirs.sumOf { it.text.length } / theirs.size
        val questions = theirs.count { it.text.contains('?') }
        val topics = topics(lines)
        val style = describeStyle(theirs, theirStyle)

        val read = buildString {
            append(label)
            append(" has sent ")
            append(theirs.size)
            append(if (theirs.size == 1) " message" else " messages")
            append(" and you have sent ")
            append(mine.size)
            append(if (mine.size == 1) " message" else " messages")
            append(" in this captured chat.")
            if (theirs.isNotEmpty()) {
                append(" Their messages average ")
                append(averageLength)
                append(" characters")
                append(if (questions > 0) " and they asked $questions question${if (questions == 1) "" else "s"}." else " with no questions back.")
            }
            append(
                when {
                    theirs.isEmpty() -> " There is not enough from them yet to read the room."
                    averageLength <= 4 && questions == 0 ->
                        " That pattern usually means polite but low energy, so do not push for a long conversation."
                    averageLength <= 8 ->
                        " They are keeping it light and short, which is fine as long as you do not over-invest."
                    questions > 0 ->
                        " They are engaging with you, not just replying, so a specific follow-up is the safest move."
                    else ->
                        " They are warm enough but not asking much back, so keep the next message short and low pressure."
                }
            )
        }

        val signals = buildList {
            if (theirs.isNotEmpty()) {
                add("${theirs.size} of their messages, averaging $averageLength characters")
            } else {
                add("no messages from them in this scan")
            }
            add(if (questions > 0) "they asked $questions question${if (questions == 1) "" else "s"}" else "they have not asked anything back")
            if (topics.isNotEmpty()) add("recurring topic: ${topics.joinToString(", ")}")
            last?.let { add(if (it.fromMe) "your message is still the last one" else "they spoke last") }
        }

        // Psychological read: attachment style and emotional needs from text behavior.
        val attachmentStyle = when {
            theirs.isEmpty() -> "unclear"
            questions >= 2 && averageLength >= 12 -> "secure"
            questions >= 1 && averageLength <= 8 -> "anxious"
            questions == 0 && averageLength <= 6 -> "avoidant"
            questions == 0 && averageLength > 12 -> "avoidant"
            else -> "secure"
        }

        val emotionalNeeds = when {
            theirs.isEmpty() -> "connection - there is no chat to read yet"
            averageLength <= 4 && questions == 0 -> "reassurance - they are giving very little back"
            questions > 0 && mine.size <= theirs.size -> "engagement - they are asking questions, they want to talk"
            mine.size > theirs.size * 2 && mine.size >= 3 -> "space - you are carrying the conversation, give them room"
            theirs.isNotEmpty() && questions == 0 -> "validation - they are responding but not initiating"
            else -> "connection - the chat is two-way and warm"
        }

        val greenFlags = buildList {
            if (questions > 0) add("asks you questions back")
            if (averageLength >= 14) add("writes more than a few words")
            if (theirs.isNotEmpty() && mine.isNotEmpty()) add("keeps the conversation two-way")
            if (topics.isNotEmpty()) add("shares what they are into")
        }.take(3)

        val redFlags = buildList {
            if (theirs.isEmpty()) add("nothing from them in this scan")
            if (theirs.isNotEmpty() && averageLength <= 4) add("very short replies")
            if (theirs.isNotEmpty() && questions == 0) add("has not asked anything back")
            if (mine.size > theirs.size * 2 && mine.size >= 3) add("you are carrying the conversation")
        }.take(3)

        val confidence = (
            0.25f +
                (theirs.size.coerceAtMost(12) * 0.03f) +
                (if (theirs.isNotEmpty() && mine.isNotEmpty()) 0.12f else 0f) +
                (if (questions > 0) 0.08f else 0f) +
                (if (topics.isNotEmpty()) 0.05f else 0f)
            ).coerceIn(0.2f, 0.78f)

        val lastTheirs = theirs.lastOrNull()?.text.orEmpty()
        val topic = topics.firstOrNull()

        val curious = when {
            lastTheirs.contains('?') -> "honestly not sure yet. what about you?"
            topic != null -> "wait, $topic - how did that start?"
            else -> "what has been keeping you busy lately?"
        }
        val playful = when {
            lastTheirs.length in 1..12 -> "short and mysterious. i respect it"
            lastTheirs.isEmpty() -> "i'll go first then: what's the best thing this week?"
            else -> "okay, that is a better answer than i expected"
        }
        val direct = when {
            last?.fromMe == true -> "no rush, just checking in"
            else -> "fair enough. tell me more when you feel like it"
        }

        val caution = when {
            theirs.isEmpty() -> "There is nothing from them here yet, so there is no read to trust."
            averageLength <= 4 && questions == 0 ->
                "They are giving very little back. Send one short message, then leave it with them."
            mine.size > theirs.size * 2 && mine.size >= 3 ->
                "You are doing most of the talking. Give them room to start the next one."
            else -> ""
        }

        val opener = if (topic != null) {
            "hey, still thinking about $topic. how did that go?"
        } else {
            "hey, how has your week been?"
        }

        val summary = buildString {
            append(label)
            append(if (name.isNotBlank()) " writes " else " write ")
            append(style)
            append(".")
            if (topics.isNotEmpty()) {
                append(" They keep coming back to ")
                append(topics.joinToString(", "))
                append(".")
            } else if (theirs.isNotEmpty()) {
                append(" There is not a clear shared topic yet.")
            } else {
                append(" No messages from them were captured.")
            }
        }

        return ScreenAnalysis(
            person = PersonaDraft(
                name = name,
                summary = summary,
                vibe = style,
                interests = topics.joinToString(", "),
                communicationStyle = style,
                attachmentStyle = attachmentStyle,
                emotionalNeeds = emotionalNeeds,
                confidence = confidence,
                opener = opener,
                greenFlags = greenFlags,
                redFlags = redFlags
            ),
            coach = CoachReply(
                read = read,
                signals = signals.take(4),
                suggestions = listOf(
                    CoachSuggestion(curious, "Follows the thread they are already on.", "curious"),
                    CoachSuggestion(playful, "Light, and does not demand a long answer.", "playful"),
                    CoachSuggestion(direct, "Plain and low pressure.", "direct")
                ),
                caution = caution,
                source = ReplySource.OFFLINE
            ),
            source = ReplySource.OFFLINE
        )
    }

    fun suggest(lines: List<CoachLine>, paused: Boolean = false): CoachReply {
        val analysis = analyze("", lines)
        val base = analysis.coach
        return if (!paused) base else base.copy(
            caution = listOf(base.caution, "This chat is marked paused. Silence is a valid answer.")
                .filter { it.isNotBlank() }
                .joinToString(" ")
        )
    }

    private fun describeStyle(theirs: List<CoachLine>, note: String): String {
        if (note.isNotBlank()) return note.trim().trimEnd('.')
        if (theirs.isEmpty()) return "not enough messages to tell"
        val average = theirs.sumOf { it.text.length } / theirs.size
        val lowercase = theirs.count { it.text.any { c -> c.isLetter() } && it.text.none { c -> c.isUpperCase() } }
        val slang = theirs.count {
            it.text.contains("lol", true) || it.text.contains("ngl", true) ||
                it.text.contains("tbh", true) || it.text.contains("idk", true)
        }
        val emoji = theirs.count { hasEmoji(it.text) }
        return buildList {
            add(
                when {
                    average <= 4 -> "short, almost one-word replies"
                    average <= 12 -> "brief and casual"
                    average <= 40 -> "relaxed, full-sentence replies"
                    else -> "long, detailed messages"
                }
            )
            if (lowercase >= theirs.size / 2) add("mostly lowercase")
            if (slang > 0) add("uses casual slang")
            if (emoji > 0) add("uses emoji")
            if (theirs.any { it.text.contains('?') }) add("asks questions")
        }.joinToString(", ")
    }

    private fun topics(lines: List<CoachLine>): List<String> {
        val counts = LinkedHashMap<String, Int>()
        lines.forEach { line ->
            WORD.findAll(line.text.lowercase()).forEach { match ->
                val word = match.value.trim('\'')
                if (word.length >= 4 && word !in STOPWORDS) {
                    counts[word] = (counts[word] ?: 0) + 1
                }
            }
        }
        return counts.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(3)
            .map { it.key }
    }

    private fun hasEmoji(text: String): Boolean =
        text.any { char ->
            char.code in 0x1F300..0x1FAFF || char.code in 0x2600..0x27BF
        }

    private val WORD = Regex("[a-zA-Z']{4,}")
}
