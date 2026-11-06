package com.example.app.data

/**
 * Deterministic, fully on-device "wingman" that turns the notes you keep about a
 * friend into a short profile and a suggested opener.
 *
 * There is deliberately no network call and no LLM here: the app is offline-first
 * and never uploads anything about your friends. Everything below is local logic.
 */
object WingmanBrain {

    private const val MIN_CONFIDENCE = 0.15f
    private const val MAX_CONFIDENCE = 0.95f

    fun profileFor(
        person: Person,
        history: List<ChatMessage> = emptyList(),
        profileId: Long = 0L,
        now: Long = System.currentTimeMillis()
    ): PersonalityProfile {
        val name = person.displayName.trim().ifBlank { "They" }
        val vibe = person.vibe.trim()
        val interests = person.interests.trim()
        val style = person.communicationStyle.trim()
        val notes = person.notes.trim()

        return PersonalityProfile(
            id = profileId,
            personId = person.id,
            summary = summary(name, vibe, style, notes, history.size),
            vibe = vibe.ifBlank { "Still figuring it out" },
            interests = interests.ifBlank { "Nothing noted yet" },
            communicationStyle = style.ifBlank { "Unknown" },
            confidence = confidence(person, history),
            suggestedOpener = opener(name, interests, style, history.size),
            source = "Notes (on-device)",
            createdAt = now,
            updatedAt = now
        )
    }

    fun confidence(person: Person, history: List<ChatMessage>): Float {
        var score = 0.25f
        if (person.discordHandle.isNotBlank()) score += 0.03f
        if (person.vibe.isNotBlank()) score += 0.15f
        if (person.interests.isNotBlank()) score += 0.15f
        if (person.communicationStyle.isNotBlank()) score += 0.15f
        if (person.notes.isNotBlank()) score += 0.10f
        score += history.size.coerceAtMost(10) * 0.02f
        return score.coerceIn(MIN_CONFIDENCE, MAX_CONFIDENCE)
    }

    private fun summary(
        name: String,
        vibe: String,
        style: String,
        notes: String,
        messageCount: Int
    ): String = buildString {
        append(name)
        append(" is a Discord friend you are getting to know.")
        if (vibe.isNotBlank()) {
            append(" Vibe: ")
            append(vibe.trimEnd('.'))
            append('.')
        }
        if (style.isNotBlank()) {
            append(" Prefers ")
            append(style.trimEnd('.'))
            append(" conversation.")
        }
        if (notes.isNotBlank()) {
            append(" Worth remembering: ")
            append(notes.trimEnd('.'))
            append('.')
        }
        when {
            messageCount >= 10 -> append(" You have a solid chat history to work from.")
            messageCount > 0 -> append(" You have logged $messageCount message")
                .append(if (messageCount == 1) "." else "s so far.")
            else -> append(" No messages logged yet.")
        }
    }

    private fun opener(
        name: String,
        interests: String,
        style: String,
        messageCount: Int
    ): String {
        val topic = primaryInterest(interests)
        val prefersShort = style.contains("short", ignoreCase = true) ||
            style.contains("brief", ignoreCase = true)

        return when {
            topic != null -> "Hey $name, I keep coming back to $topic. What got you into it?"
            prefersShort -> "Hey $name, quick one - how has your week been?"
            messageCount > 0 -> "Hey $name, picking up where we left off - how did that go?"
            else -> "Hey $name, random question: what have you been enjoying lately?"
        }
    }

    private fun primaryInterest(interests: String): String? =
        interests
            .split(',', ';', '/', '\n')
            .asSequence()
            .flatMap { it.split(" and ", " & ") }
            .map { it.trim().trimEnd('.') }
            .firstOrNull { it.length >= 2 }

    fun confidencePercent(profile: PersonalityProfile): Int =
        (profile.confidence.coerceIn(0f, 1f) * 100).toInt()
}
