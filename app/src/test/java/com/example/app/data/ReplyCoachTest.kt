package com.example.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ReplyCoachTest {

    // ---- transcript parsing -------------------------------------------------

    @Test
    fun `me prefix is mine, everything else is theirs`() {
        val lines = ReplyCoach.parseTranscript(
            """
            Them: hey, how was your day
            Me: long, but good
            me: got the job btw
            > just checking
            """.trimIndent()
        )

        assertEquals(4, lines.size)
        assertEquals(false, lines[0].fromMe)
        assertEquals("hey, how was your day", lines[0].text)
        assertEquals(true, lines[1].fromMe)
        assertEquals("long, but good", lines[1].text)
        assertEquals(true, lines[2].fromMe)
        assertEquals("got the job btw", lines[2].text)
        assertTrue(lines[3].fromMe)
    }

    @Test
    fun `unlabelled lines are treated as theirs`() {
        val lines = ReplyCoach.parseTranscript("hii what are you up to")
        assertEquals(1, lines.size)
        assertEquals(false, lines.single().fromMe)
    }

    @Test
    fun `blank lines are dropped`() {
        val lines = ReplyCoach.parseTranscript("Me: a\n\n   \nThem: b\n")
        assertEquals(2, lines.size)
    }

    @Test
    fun `format and parse round trip`() {
        val original = listOf(
            CoachLine(false, "hey"),
            CoachLine(true, "hi, how's the exam going"),
            CoachLine(false, "better than expected")
        )
        assertEquals(original, ReplyCoach.parseTranscript(ReplyCoach.formatTranscript(original)))
    }

    // ---- request building ---------------------------------------------------

    @Test
    fun `user message labels both sides and notes an unanswered message`() {
        val message = ReplyCoach.userMessage(
            lines = listOf(CoachLine(false, "hey"), CoachLine(true, "yo")),
            theirStyle = "short, lowercase",
            myVoice = "dry, no emoji"
        )

        assertTrue(message.contains("THEM: hey"))
        assertTrue(message.contains("ME: yo"))
        assertTrue(message.contains("his last message is still unanswered"))
        assertTrue(message.contains("short, lowercase"))
        assertTrue(message.contains("dry, no emoji"))
    }

    @Test
    fun `no unanswered note when they spoke last`() {
        val message = ReplyCoach.userMessage(listOf(CoachLine(true, "yo"), CoachLine(false, "hey")))
        assertTrue(!message.contains("unanswered"))
    }

    @Test
    fun `paused chats tell the model to allow silence`() {
        val message = ReplyCoach.userMessage(listOf(CoachLine(false, "k")), paused = true)
        assertTrue(message.contains("paused"))
    }

    @Test
    fun `oldest lines are dropped to stay inside the budget`() {
        val many = (1..80).map { CoachLine(it % 2 == 0, "line $it") }
        val fitted = ReplyCoach.fit(many)

        assertTrue(fitted.size <= ReplyCoach.MAX_LINES)
        assertEquals("line 80", fitted.last().text)
    }

    @Test
    fun `very long single transcript is trimmed by characters`() {
        val huge = (1..5).map { CoachLine(false, "x".repeat(4_000)) }
        val fitted = ReplyCoach.fit(huge)

        val total = fitted.sumOf { it.text.length }
        assertTrue("expected under budget, was $total", total <= ReplyCoach.MAX_USER_CHARS)
        assertTrue(fitted.isNotEmpty())
    }

    // ---- parsing the model's answer ----------------------------------------

    @Test
    fun `parses the documented shape`() {
        val reply = ReplyCoach.parse(
            """
            {
              "read": "She is warm but short. Probably busy.",
              "signals": ["she replied in under a minute", "no question back"],
              "replies": [
                {"style": "curious", "text": "how did the exam go?", "why": "picks up her thread"},
                {"style": "playful", "text": "so you survived", "why": "light, matches her length"},
                {"style": "direct", "text": "tell me when you are free", "why": "clear, no pressure"}
              ],
              "caution": "Do not double text."
            }
            """.trimIndent()
        )

        assertEquals("She is warm but short. Probably busy.", reply.read)
        assertEquals(2, reply.signals.size)
        assertEquals(3, reply.suggestions.size)
        assertEquals("curious", reply.suggestions[0].style)
        assertEquals("how did the exam go?", reply.suggestions[0].text)
        assertEquals("Do not double text.", reply.caution)
    }

    @Test
    fun `parses through a code fence and leading prose`() {
        val reply = ReplyCoach.parse(
            """
            Sure, here you go:
            ```json
            {"read":"fine","signals":[],"replies":[{"style":"direct","text":"hey","why":"simple"}],"caution":""}
            ```
            """.trimIndent()
        )

        assertEquals("fine", reply.read)
        assertEquals("hey", reply.suggestions.single().text)
        assertEquals("", reply.caution)
    }

    @Test
    fun `missing signals and caution are tolerated`() {
        val reply = ReplyCoach.parse(
            """{"read":"ok","replies":[{"text":"hello"}]}"""
        )

        assertTrue(reply.signals.isEmpty())
        assertEquals("", reply.caution)
        assertEquals("option", reply.suggestions.single().style)
    }

    @Test
    fun `empty replies throw`() {
        val error = assertThrows(CoachException::class.java) {
            ReplyCoach.parse("""{"read":"she is done with you","signals":[],"replies":[]}""")
        }
        assertTrue(error.message!!.contains("did not send any replies"))
    }

    @Test
    fun `non json throws`() {
        assertThrows(CoachException::class.java) {
            ReplyCoach.parse("I think you should just be yourself!")
        }
    }

    @Test
    fun `replies without text are skipped`() {
        val reply = ReplyCoach.parse(
            """{"read":"ok","replies":[{"style":"curious","text":"  "},{"style":"direct","text":"hey","why":"w"}]}"""
        )
        assertEquals(1, reply.suggestions.size)
        assertEquals("hey", reply.suggestions.single().text)
    }

    @Test
    fun `more than four replies are cut down`() {
        val replies = (1..6).joinToString(",") { """{"style":"x","text":"r$it"}""" }
        val reply = ReplyCoach.parse("""{"read":"ok","replies":[$replies]}""")
        assertEquals(4, reply.suggestions.size)
    }

    // ---- config -------------------------------------------------------------

    @Test
    fun `config is only ready with a key, url and model`() {
        val empty = CoachConfig()
        assertTrue(!empty.isReady)

        assertTrue(empty.copy(apiKey = "sk-test").isReady)
        assertTrue(!empty.copy(apiKey = "sk-test", model = " ").isReady)
        assertTrue(!empty.copy(apiKey = "sk-test", baseUrl = "").isReady)
    }

    @Test
    fun `masked key never shows the whole secret`() {
        val masked = CoachConfig(apiKey = "sk-abcdefghijk").maskedKey
        assertTrue(!masked.contains("abcdefg"))
        assertTrue(masked.endsWith("hijk"))
        assertEquals("••••", CoachConfig(apiKey = "short").maskedKey)
    }
}
