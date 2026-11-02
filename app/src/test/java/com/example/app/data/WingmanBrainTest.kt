package com.example.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WingmanBrainTest {

    private fun person(
        name: String = "Alex",
        vibe: String = "",
        interests: String = "",
        style: String = "",
        notes: String = ""
    ) = Person(
        id = 1L,
        displayName = name,
        discordHandle = "alex#0001",
        vibe = vibe,
        interests = interests,
        communicationStyle = style,
        notes = notes
    )

    private fun message(id: Long, text: String, sender: ChatMessage.MessageSender) = ChatMessage(
        id = id,
        personId = 1L,
        sender = sender,
        text = text,
        createdAt = 1_000L * id
    )

    @Test
    fun `confidence grows with more detail`() {
        val sparse = person()
        val rich = person(
            vibe = "dry humour",
            interests = "mechanical keyboards",
            style = "short messages",
            notes = "works nights"
        )
        assertTrue(WingmanBrain.confidence(rich, emptyList()) > WingmanBrain.confidence(sparse, emptyList()))
    }

    @Test
    fun `confidence grows with chat history and stays bounded`() {
        val p = person()
        val shortHistory = (1L..3L).map { message(it, "hey", ChatMessage.MessageSender.USER) }
        val longHistory = (1L..30L).map { message(it, "hey", ChatMessage.MessageSender.OTHER) }

        assertTrue(WingmanBrain.confidence(p, longHistory) > WingmanBrain.confidence(p, shortHistory))
        assertTrue(WingmanBrain.confidence(p, longHistory) <= 0.95f)
    }

    @Test
    fun `summary mentions the friend and their vibe`() {
        val profile = WingmanBrain.profileFor(
            person = person(vibe = "calm", notes = "loves tea"),
            history = emptyList(),
            now = 42L
        )
        assertTrue(profile.summary.contains("Alex"))
        assertTrue(profile.summary.contains("calm"))
        assertEquals(42L, profile.updatedAt)
    }

    @Test
    fun `opener uses the first listed interest`() {
        val profile = WingmanBrain.profileFor(
            person = person(interests = "mechanical keyboards, hiking"),
            history = emptyList()
        )
        assertTrue(profile.suggestedOpener.contains("mechanical keyboards"))
    }

    @Test
    fun `short style gets a brief opener when no interests exist`() {
        val profile = WingmanBrain.profileFor(
            person = person(style = "short, low-effort replies"),
            history = emptyList()
        )
        assertTrue(profile.suggestedOpener.contains("quick one"))
    }

    @Test
    fun `profile keeps the existing id and is marked updated`() {
        val profile = WingmanBrain.profileFor(
            person = person(interests = "chess"),
            history = listOf(message(1L, "hi", ChatMessage.MessageSender.USER)),
            profileId = 7L,
            now = 99L
        )
        assertEquals(7L, profile.id)
        assertEquals(1L, profile.personId)
        assertEquals(99L, profile.updatedAt)
    }

    @Test
    fun `blank details fall back to friendly defaults`() {
        val profile = WingmanBrain.profileFor(person = person(name = "  "), history = emptyList())
        assertEquals("Still figuring it out", profile.vibe)
        assertEquals("Nothing noted yet", profile.interests)
        assertTrue(profile.summary.isNotBlank())
        assertTrue(profile.suggestedOpener.isNotBlank())
    }
}
