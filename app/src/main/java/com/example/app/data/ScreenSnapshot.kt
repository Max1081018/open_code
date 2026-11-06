package com.example.app.data

/** One piece of text the accessibility service found on screen, with its bounds. */
data class CapturedText(
    val text: String,
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
)

/** A chat snapshot taken from whatever app the user was reading. */
data class ScanSnapshot(
    val packageName: String,
    val appLabel: String,
    val lines: List<CoachLine>,
    val nameGuess: String = "",
    val capturedAt: Long = System.currentTimeMillis()
) {
    val transcript: String
        get() = ReplyCoach.formatTranscript(lines)

    val isEmpty: Boolean
        get() = lines.isEmpty()
}

/**
 * Turns the raw accessibility tree into a conversation.
 *
 * Chat bubbles are left or right aligned, so the horizontal centre of a node is
 * the strongest signal we have for who sent it. App chrome, timestamps and the
 * message box are filtered out by name and position. None of this is perfect
 * across every chat app, which is why the user always gets an editable review
 * before anything is analysed.
 */
object ScreenTranscript {

    private val TIME = Regex("""^\d{1,2}:\d{2}(\s?[ap]\.?m\.?)?$""", RegexOption.IGNORE_CASE)
    private val SYSTEM_DATE = Regex("""^(today|yesterday) at .+$""", RegexOption.IGNORE_CASE)

    private val CHROME = setOf(
        "message", "send", "gif", "emoji", "sticker", "search", "members", "online",
        "offline", "friends", "direct messages", "servers", "type a message",
        "add a comment", "reply", "cancel", "back", "more", "settings", "profile",
        "notifications", "discord", "new messages", "jump to present", "edited",
        "attachment", "download", "open", "close", "menu", "home", "inbox",
        "voice", "video", "call", "mute", "deafen", "leave", "invite", "share"
    )

    private val PREFIX_CHROME = listOf(
        "message @", "message #", "type a message", "search for", "today at ",
        "yesterday at ", "new messages", "you are now", "this is the beginning"
    )

    /**
     * @param nodes every text node in the active window, in any order
     * @param width screen width in pixels, used to tell left-aligned from right-aligned
     */
    fun snapshot(
        nodes: List<CapturedText>,
        width: Int,
        height: Int,
        appLabel: String,
        packageName: String
    ): ScanSnapshot {
        val cleaned = nodes
            .asSequence()
            .filter { it.right > it.left && it.bottom > it.top }
            .filter { it.text.isNotBlank() && it.text.length <= 1_000 }
            .filter { isMessage(it.text) }
            .distinctBy { "${it.text}|${it.top / 4}|${it.left / 4}" }
            .sortedWith(compareBy<CapturedText> { it.top }.thenBy { it.left })
            .toList()

        val screenWidth = if (width > 0) width else cleaned.maxOfOrNull { it.right } ?: 0
        val lines = cleaned.map { node ->
            CoachLine(fromMe = isMine(node, screenWidth), text = node.text.trim())
        }.filter { it.text.isNotEmpty() }

        return ScanSnapshot(
            packageName = packageName,
            appLabel = appLabel,
            lines = lines,
            nameGuess = guessName(cleaned, height, appLabel)
        )
    }

    fun isMessage(raw: String): Boolean {
        val text = raw.trim()
        if (text.isEmpty()) return false
        val lower = text.lowercase()
        if (lower in CHROME) return false
        if (PREFIX_CHROME.any { lower.startsWith(it) }) return false
        if (TIME.matches(text) || SYSTEM_DATE.matches(text)) return false
        if (text.all { it.isDigit() || it == ':' || it == '.' }) return false
        return true
    }

    private fun isMine(node: CapturedText, screenWidth: Int): Boolean {
        if (screenWidth <= 0) return false
        val centre = (node.left + node.right) / 2f
        val spansMost = (node.right - node.left) >= screenWidth * 0.9f
        if (spansMost) {
            // System rows and the composer span the width; those are filtered
            // above. Anything left is more likely a received message.
            return false
        }
        return centre > screenWidth * 0.56f
    }

    private fun guessName(nodes: List<CapturedText>, height: Int, appLabel: String): String {
        val headerBottom = if (height > 0) height * 0.20f else 320f
        return nodes.asSequence()
            .filter { it.top < headerBottom }
            .map { it.text.trim() }
            .firstOrNull { candidate ->
                val lower = candidate.lowercase()
                candidate.length in 2..40 &&
                    lower !in CHROME &&
                    lower != appLabel.lowercase() &&
                    !lower.startsWith("@") &&
                    !TIME.matches(candidate) &&
                    !SYSTEM_DATE.matches(candidate) &&
                    candidate.none { it == '\n' }
            }
            .orEmpty()
    }
}
