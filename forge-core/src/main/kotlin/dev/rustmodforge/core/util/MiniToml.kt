package dev.rustmodforge.core.util

/**
 * A TOML reader for the subset mod manifests use (Forge/NeoForge `mods.toml`): bare and quoted
 * keys, dotted keys, strings (basic, literal, multi-line), integers, floats, booleans, arrays,
 * inline tables, `[table]` and `[[array.of.tables]]`. Values become String, Long, Double,
 * Boolean, List<Any?> or Map<String, Any?>. Errors carry the line number.
 */
class TomlException(message: String) : Exception(message)

object MiniToml {
    fun parse(text: String): Map<String, Any?> {
        val root = LinkedHashMap<String, Any?>()
        var current: MutableMap<String, Any?> = root
        val p = Parser(text)
        while (true) {
            p.skipWsCommentsNewlines()
            if (p.eof()) break
            if (p.peek() == '[') {
                val array = p.peekAt(1) == '['
                p.pos += if (array) 2 else 1
                p.skipWs()
                val key = p.readKeyPath()
                p.skipWs()
                p.expect(']')
                if (array) p.expect(']')
                current = if (array) appendTable(root, key, p) else table(root, key, p)
                p.endOfLine()
                continue
            }
            val key = p.readKeyPath()
            p.skipWs()
            p.expect('=')
            p.skipWs()
            val value = p.readValue()
            put(current, key, value, p)
            p.endOfLine()
        }
        return root
    }

    @Suppress("UNCHECKED_CAST")
    private fun table(root: MutableMap<String, Any?>, path: List<String>, p: Parser): MutableMap<String, Any?> {
        var m = root
        for (k in path) {
            m = when (val v = m[k]) {
                null -> LinkedHashMap<String, Any?>().also { m[k] = it }
                is MutableMap<*, *> -> v as MutableMap<String, Any?>
                is MutableList<*> -> (v.lastOrNull() as? MutableMap<String, Any?>) ?: throw p.error("$k is not a table")
                else -> throw p.error("$k is not a table")
            }
        }
        return m
    }

    @Suppress("UNCHECKED_CAST")
    private fun appendTable(root: MutableMap<String, Any?>, path: List<String>, p: Parser): MutableMap<String, Any?> {
        val parent = table(root, path.dropLast(1), p)
        val list = when (val v = parent[path.last()]) {
            null -> ArrayList<Any?>().also { parent[path.last()] = it }
            is MutableList<*> -> v as MutableList<Any?>
            else -> throw p.error("${path.last()} is not an array of tables")
        }
        return LinkedHashMap<String, Any?>().also { list += it }
    }

    private fun put(m: MutableMap<String, Any?>, key: List<String>, value: Any?, p: Parser) {
        val t = table(m, key.dropLast(1), p)
        t[key.last()] = value
    }

    private class Parser(val s: String) {
        var pos = 0
        fun eof() = pos >= s.length
        fun peek() = s[pos]
        fun peekAt(o: Int) = if (pos + o < s.length) s[pos + o] else '\u0000'
        fun line() = s.substring(0, pos.coerceAtMost(s.length)).count { it == '\n' } + 1
        fun error(msg: String) = TomlException("line ${line()}: $msg")
        fun expect(c: Char) {
            if (eof() || s[pos] != c) throw error("expected '$c'")
            pos++
        }
        fun skipWs() { while (!eof() && (s[pos] == ' ' || s[pos] == '\t')) pos++ }
        fun skipComment() { if (!eof() && s[pos] == '#') while (!eof() && s[pos] != '\n') pos++ }
        fun skipWsCommentsNewlines() {
            while (!eof()) {
                when (s[pos]) {
                    ' ', '\t', '\r', '\n' -> pos++
                    '#' -> skipComment()
                    else -> return
                }
            }
        }
        fun endOfLine() {
            skipWs(); skipComment()
            if (!eof() && s[pos] == '\r') pos++
            if (!eof() && s[pos] != '\n') throw error("unexpected '${s[pos]}'")
        }
        fun readKeyPath(): List<String> {
            val parts = ArrayList<String>()
            while (true) {
                skipWs()
                parts += readKey()
                skipWs()
                if (!eof() && s[pos] == '.') { pos++; continue }
                return parts
            }
        }
        fun readKey(): String = when {
            eof() -> throw error("expected a key")
            s[pos] == '"' -> readBasicString()
            s[pos] == '\'' -> readLiteralString()
            else -> {
                val start = pos
                while (!eof() && (s[pos].isLetterOrDigit() || s[pos] == '_' || s[pos] == '-')) pos++
                if (start == pos) throw error("expected a key")
                s.substring(start, pos)
            }
        }
        fun readValue(): Any? {
            if (eof()) throw error("expected a value")
            return when (val c = s[pos]) {
                '"' -> if (s.startsWith("\"\"\"", pos)) readMultiBasic() else readBasicString()
                '\'' -> if (s.startsWith("'''", pos)) readMultiLiteral() else readLiteralString()
                '[' -> readArray()
                '{' -> readInlineTable()
                't', 'f' -> readBool()
                else -> if (c == '+' || c == '-' || c.isDigit() || c == 'i' || c == 'n') readNumberOrDate() else throw error("unexpected '$c'")
            }
        }
        fun readBool(): Boolean = when {
            s.startsWith("true", pos) -> { pos += 4; true }
            s.startsWith("false", pos) -> { pos += 5; false }
            else -> throw error("expected a boolean")
        }
        fun readNumberOrDate(): Any {
            val start = pos
            while (!eof() && s[pos] !in ",]}\n\r#" && !(s[pos] == ' ' && !looksLikeDateTimeSpace(start))) pos++
            val raw = s.substring(start, pos).trim().replace("_", "")
            raw.toLongOrNull()?.let { return it }
            if (raw.startsWith("0x")) raw.substring(2).toLongOrNull(16)?.let { return it }
            raw.toDoubleOrNull()?.let { return it }
            return when (raw) {
                "inf", "+inf" -> Double.POSITIVE_INFINITY
                "-inf" -> Double.NEGATIVE_INFINITY
                "nan", "+nan", "-nan" -> Double.NaN
                else -> raw // dates and times are kept as text
            }
        }
        private fun looksLikeDateTimeSpace(start: Int) = s.substring(start, pos).matches(Regex("\\d{4}-\\d{2}-\\d{2}"))
        fun readBasicString(): String {
            expect('"')
            val sb = StringBuilder()
            while (true) {
                if (eof() || s[pos] == '\n') throw error("unterminated string")
                val c = s[pos++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> sb.append(readEscape())
                    else -> sb.append(c)
                }
            }
        }
        fun readEscape(): String {
            if (eof()) throw error("bad escape")
            return when (val e = s[pos++]) {
                'n' -> "\n"; 't' -> "\t"; 'r' -> "\r"; '"' -> "\""; '\\' -> "\\"; 'b' -> "\b"; 'f' -> "\u000C"
                'u' -> codepoint(4)
                'U' -> codepoint(8)
                else -> throw error("bad escape \\$e")
            }
        }
        private fun codepoint(n: Int): String {
            if (pos + n > s.length) throw error("bad unicode escape")
            val cp = s.substring(pos, pos + n).toIntOrNull(16) ?: throw error("bad unicode escape")
            pos += n
            return String(Character.toChars(cp))
        }
        fun readLiteralString(): String {
            expect('\'')
            val end = s.indexOf('\'', pos)
            if (end < 0 || s.substring(pos, end).contains('\n')) throw error("unterminated string")
            return s.substring(pos, end).also { pos = end + 1 }
        }
        fun readMultiBasic(): String {
            pos += 3
            if (!eof() && s[pos] == '\n') pos++ else if (s.startsWith("\r\n", pos)) pos += 2
            val sb = StringBuilder()
            while (true) {
                if (eof()) throw error("unterminated multi-line string")
                if (s.startsWith("\"\"\"", pos)) { pos += 3; return sb.toString() }
                val c = s[pos++]
                if (c == '\\') {
                    if (!eof() && (s[pos] == '\n' || s[pos] == '\r' || s[pos] == ' ')) {
                        while (!eof() && s[pos].isWhitespace()) pos++
                    } else sb.append(readEscape())
                } else sb.append(c)
            }
        }
        fun readMultiLiteral(): String {
            pos += 3
            if (!eof() && s[pos] == '\n') pos++ else if (s.startsWith("\r\n", pos)) pos += 2
            val end = s.indexOf("'''", pos)
            if (end < 0) throw error("unterminated multi-line string")
            return s.substring(pos, end).also { pos = end + 3 }
        }
        fun readArray(): List<Any?> {
            expect('[')
            val list = ArrayList<Any?>()
            while (true) {
                skipWsCommentsNewlines()
                if (eof()) throw error("unterminated array")
                if (s[pos] == ']') { pos++; return list }
                list += readValue()
                skipWsCommentsNewlines()
                if (!eof() && s[pos] == ',') { pos++; continue }
                skipWsCommentsNewlines()
                expect(']')
                return list
            }
        }
        fun readInlineTable(): Map<String, Any?> {
            expect('{')
            val m = LinkedHashMap<String, Any?>()
            skipWs()
            if (!eof() && s[pos] == '}') { pos++; return m }
            while (true) {
                val key = readKeyPath()
                skipWs(); expect('='); skipWs()
                put(m, key, readValue(), this)
                skipWs()
                if (!eof() && s[pos] == ',') { pos++; skipWs(); continue }
                expect('}')
                return m
            }
        }
    }
}
