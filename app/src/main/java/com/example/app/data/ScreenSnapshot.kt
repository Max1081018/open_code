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
 * Discord (and most chat apps) lay out a message as a vertical group:
 *   [sender name]   <- small, above the bubble, left-aligned
 *   [message text]  <- the bubble itself, left or right of centre
 *   [timestamp]     <- tiny, below or beside the bubble
 *
 * We cluster nodes by vertical proximity, treat the topmost short line of each
 * cluster as the sender name, and classify left-vs-right by horizontal centre.
 * Anything that cannot be confidently classified is still passed through so the
 * user can fix it in the editable review step.
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

    /** Vertical gap (px) within which two text nodes belong to the same message cluster. */
    private const val CLUSTER_GAP_PX = 60f

    /** Max height (px) for a node to be considered a sender name rather than message body. */
    private const val NAME_MAX_HEIGHT_PX = 30f

    /** Max characters for a sender name. */
    private const val NAME_MAX_CHARS = 40

    /**
     * @param nodes every text node in the active window, in any order
     * @param width screen width in pixels, used to tell left-aligned from right-aligned
     * @param height screen height in pixels, used to find the header/title area
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

        // Cluster nodes into message groups by vertical proximity.
        val clusters = clusterNodes(cleaned, screenWidth)

        val lines = clusters.flatMap { cluster ->
            cluster.toCoachLines(screenWidth)
        }.filter { it.text.isNotEmpty() }

        return ScanSnapshot(
            packageName = packageName,
            appLabel = appLabel,
            lines = lines,
            nameGuess = guessName(cleaned, height, appLabel)
        )
    }

    /** Groups vertically adjacent text nodes into message clusters. */
    private fun clusterNodes(
        nodes: List<CapturedText>,
        screenWidth: Int
    ): List<List<CapturedText>> {
        val clusters = mutableListOf<MutableList<CapturedText>>()
        var current: MutableList<CapturedText>? = null

        nodes.forEach { node ->
            if (current == null || node.top - current!!.last().bottom > CLUSTER_GAP_PX) {
                current = mutableListOf()
                clusters.add(current)
            }
            current!!.add(node)
        }

        return clusters
    }

    /**
     * Converts a cluster of text nodes into CoachLine(s).
     *
     * The topmost short line in the cluster is treated as the sender name. The
     * remaining lines form the message body. Left-vs-right classification uses
     * the horizontal centre of the message body.
     */
    private fun List<CapturedText>.toCoachLines(screenWidth: Int): List<CoachLine> {
        if (isEmpty()) return emptyList()

        val sorted = sortedBy { it.top }

        // Find the sender name: the first line that is short and sits above the rest.
        var nameIndex = -1
        for (i in sorted.indices) {
            val node = sorted[i]
            val height = node.bottom - node.top
            val isLikelyName = node.text.length <= NAME_MAX_CHARS &&
                height <= NAME_MAX_HEIGHT_PX &&
                i < sorted.size / 2 && // names appear in the top half of a cluster
                !TIME.matches(node.text) &&
                !SYSTEM_DATE.matches(node.text)
            if (isLikelyName) {
                nameIndex = i
                break
            }
        }

        val nameNode = if (nameIndex >= 0) sorted.removeAt(nameIndex) else null
        val bodyNodes = sorted

        // Classify left vs right by the centre of the message body.
        val fromMe = bodyNodes.classifySide(screenWidth)

        // Build lines: if we found a name, prefix it so the AI knows who said what.
        return bodyNodes.map { node ->
            val prefix = if (nameNode != null) "${nameNode.text.trim()}: " else ""
            CoachLine(fromMe = fromMe, text = prefix + node.text.trim())
        }
    }

    /** Classifies a message body as "mine" (right side) or "theirs" (left side). */
    private fun List<CapturedText>.classifySide(screenWidth: Int): Boolean {
        if (isEmpty() || screenWidth <= 0) return false
        val centres = map { (it.left + it.right) / 2f }
        val averageCentre = centres.average()
        val spansMost = any { (it.right - it.left) >= screenWidth * 0.9f }
        if (spansMost) return false // system row, treat as theirs
        return averageCentre > screenWidth * 0.56f
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

    /**
     * Guesses the conversation partner's name from the header/title area of the
     * screen, or from sender names found in message clusters.
     */
    private fun guessName(nodes: List<CapturedText>, height: Int, appLabel: String): String {
        val headerBottom = if (height > 0) height * 0.20f else 320f

        // First try the app header area (Discord shows the partner name there).
        val headerCandidate = nodes.asSequence()
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

        if (headerCandidate != null) return headerCandidate

        // Otherwise, try the most common sender name in message clusters.
        val nameCounts = nodes.asSequence()
            .map { it.text.trim() }
            .filter { candidate ->
                val lower = candidate.lowercase()
                candidate.length in 2..NAME_MAX_CHARS &&
                    lower !in CHROME &&
                    lower != appLabel.lowercase() &&
                    !TIME.matches(candidate) &&
                    !SYSTEM_DATE.matches(candidate) &&
                    candidate.none { it == '\n' } &&
                    !candidate.contains('?') &&
                    !candidate.contains('!')
            }
            .counting()

        return nameCounts.maxByOrNull { it.value }?.key.orEmpty()
    }
}
