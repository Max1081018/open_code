package com.example.app.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScanAnalysisTest {

    // ---- combined profile + reply parsing ------------------------------------

    @Test
    fun `parser reads the combined screen analysis shape`() {
        val raw = """
            {"person":{"name":"Riley","summary":"Riley is playful and private.","vibe":"dry","interests":"tennis","communicationStyle":"short messages","confidence":0.6,"opener":"hey, still thinking about tennis","greenFlags":["asks questions"],"redFlags":[]},
             "read":"Riley is warm but low energy.","signals":["kept it short"],"replies":[{"style":"curious","text":"how did the match go?","why":"keeps thread"}],"caution":""}
        """.trimIndent()

        val analysis = AnalysisParser.parse(raw)

        assertEquals("Riley", analysis.person.name)
        assertEquals("Riley is playful and private.", analysis.person.summary)
        assertEquals(0.6f, analysis.person.confidence, 0.001f)
        assertEquals("hey, still thinking about tennis", analysis.person.opener)
        assertEquals(listOf("asks questions"), analysis.person.greenFlags)
        assertTrue(analysis.coach.read.isNotBlank())
        assertEquals(3, analysis.coach.suggestions.size)
        assertEquals("how did the match go?", analysis.coach.suggestions.single().text)
        assertEquals(ReplySource.ONLINE, analysis.source)
    }

    // ---- screen transcript --------------------------------------------------

    @Test
    fun `screen transcript splits bubbles by side and drops chrome`() {
        val snapshot = ScreenTranscript.snapshot(
            nodes = listOf(
                CapturedText(text = "hey, how was your day", left = 80, top = 100, right = 420, bottom = 130),
                CapturedText(text = "Message", left = 700, top = 400, right = 900, bottom = 430),
                CapturedText(text = "long, but good", left = 650, top = 200, right = 900, bottom = 230)
            ),
            width = 1080,
            height = 2400,
            appLabel = "Discord",
            packageName = "com.discord"
        )

        assertEquals(2, snapshot.lines.size)
        assertEquals(false, snapshot.lines[0].fromMe)
        assertEquals("hey, how was your day", snapshot.lines[0].text)
        assertEquals(true, snapshot.lines[1].fromMe)
        assertEquals("long, but good", snapshot.lines[1].text)
        assertEquals("com.discord", snapshot.packageName)
    }

    // ---- on device fallback --------------------------------------------------

    @Test
    fun `on device fallback still answers with three suggestions`() {
        val analysis = LocalWingman.analyze(
            personName = "Riley",
            transcript = listOf(
                CoachLine(false, "hey"),
                CoachLine(true, "how was the exam"),
                CoachLine(false, "pretty good")
            )
        )

        assertEquals(ReplySource.OFFLINE, analysis.source)
        assertEquals(ReplySource.OFFLINE, analysis.coach.source)
        assertTrue(analysis.coach.read.isNotBlank())
        assertEquals(3, analysis.coach.suggestions.size)
        assertEquals("", analysis.coach.caution.ifBlank { "" }.let { analysis.coach.caution })
    }
}

class AiResilienceTest {

    private class FlakyAi(private val failure: Exception) : WingmanAi {
        override suspend fun suggest(
            lines: List<CoachLine>,
            theirStyle: String,
            myVoice: String,
            paused: Boolean
        ): CoachReply = throw failure

        override suspend fun analyze(
            appLabel: String,
            personName: String?,
            transcript: List<CoachLine>,
            theirStyle: String,
            myVoice: String
        ): ScreenAnalysis = throw failure

        override suspend fun test(): String = throw failure
    }

    @Test
    fun `offline fallback kicks in when the provider fails`() = runBlocking {
        val resilient = ResilientWingman(FlakyAi(CoachException("boom")))

        val reply = resilient.suggest(
            lines = listOf(CoachLine(false, "hey")),
            theirStyle = "",
            myVoice = "",
            paused = false
        )
        assertEquals(ReplySource.OFFLINE, reply.source)
        assertTrue(reply.notice.isNotBlank())
        assertTrue(reply.suggestions.isNotEmpty())

        val analysis = resilient.analyze(
            appLabel = "Discord",
            personName = "Riley",
            transcript = listOf(CoachLine(false, "hey")),
            theirStyle = "",
            myVoice = ""
        )
        assertEquals(ReplySource.OFFLINE, analysis.source)
    }
}
