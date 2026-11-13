package dev.rustmodforge.core.geo

import kotlin.math.PI

/**
 * A Molang evaluator for the expressions animation files use in keyframes: arithmetic,
 * comparisons, `?:`, `math.*` (trigonometry in degrees, as Molang defines it) and the time
 * queries. Unknown variables and queries evaluate to 0 and are reported through [unknown], so
 * an approximation is never silent.
 */
class Molang(private val queries: Map<String, Double> = emptyMap()) {
    val unknown = LinkedHashSet<String>()

    fun eval(expr: String): Double {
        val trimmed = expr.trim().removeSuffix(";")
        trimmed.toDoubleOrNull()?.let { return it }
        if (trimmed.isEmpty()) return 0.0
        // Only the last statement of a complex expression yields a value; `return` is optional.
        val statement = trimmed.split(';').last { it.isNotBlank() }.trim().removePrefix("return").trim()
        return Parser(statement.lowercase()).run { val v = ternary(); v }
    }

    private inner class Parser(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        fun peek(t: String): Boolean { ws(); return s.startsWith(t, i) }
        fun eat(t: String): Boolean { if (peek(t)) { i += t.length; return true }; return false }

        fun ternary(): Double {
            val c = or()
            if (eat("?")) {
                val a = ternary()
                return if (eat(":")) { val b = ternary(); if (c != 0.0) a else b } else if (c != 0.0) a else 0.0
            }
            return c
        }
        fun or(): Double { var l = and(); while (eat("||")) { val r = and(); l = if (l != 0.0 || r != 0.0) 1.0 else 0.0 }; return l }
        fun and(): Double { var l = cmp(); while (eat("&&")) { val r = cmp(); l = if (l != 0.0 && r != 0.0) 1.0 else 0.0 }; return l }
        fun cmp(): Double {
            var l = add()
            while (true) {
                l = when {
                    eat("<=") -> b(l <= add()); eat(">=") -> b(l >= add())
                    eat("==") -> b(l == add()); eat("!=") -> b(l != add())
                    eat("<") -> b(l < add()); eat(">") -> b(l > add())
                    else -> return l
                }
            }
        }
        fun b(x: Boolean) = if (x) 1.0 else 0.0
        fun add(): Double {
            var l = mul()
            while (true) { l = when { eat("+") -> l + mul(); peek("-") && !peek("->") -> { i++; l - mul() }; else -> return l } }
        }
        fun mul(): Double {
            var l = unary()
            while (true) { l = when { eat("*") -> l * unary(); eat("/") -> { val r = unary(); if (r == 0.0) 0.0 else l / r }; else -> return l } }
        }
        fun unary(): Double = when { eat("-") -> -unary(); eat("+") -> unary(); eat("!") -> b(unary() == 0.0); else -> primary() }
        fun primary(): Double {
            ws()
            if (eat("(")) { val v = ternary(); eat(")"); return v }
            if (i < s.length && (s[i].isDigit() || s[i] == '.')) {
                val start = i
                while (i < s.length && (s[i].isDigit() || s[i] == '.' || s[i] == 'e')) i++
                if (i < s.length && s[i] == 'f') i++
                return s.substring(start, i).trimEnd('f').toDoubleOrNull() ?: 0.0
            }
            val start = i
            while (i < s.length && (s[i].isLetterOrDigit() || s[i] == '_' || s[i] == '.')) i++
            val name = s.substring(start, i)
            if (name.isEmpty()) { i++; return 0.0 }
            if (eat("(")) {
                val args = ArrayList<Double>()
                if (!eat(")")) { do { args += ternary() } while (eat(",")); eat(")") }
                return call(name, args)
            }
            return value(name)
        }
        fun call(name: String, a: List<Double>): Double {
            fun x(k: Int) = a.getOrElse(k) { 0.0 }
            return when (name.removePrefix("math.")) {
                "sin" -> kotlin.math.sin(Math.toRadians(x(0)))
                "cos" -> kotlin.math.cos(Math.toRadians(x(0)))
                "abs" -> kotlin.math.abs(x(0))
                "sqrt" -> kotlin.math.sqrt(kotlin.math.max(0.0, x(0)))
                "floor" -> kotlin.math.floor(x(0))
                "ceil" -> kotlin.math.ceil(x(0))
                "round" -> kotlin.math.round(x(0))
                "trunc" -> kotlin.math.truncate(x(0))
                "clamp" -> x(0).coerceIn(kotlin.math.min(x(1), x(2)), kotlin.math.max(x(1), x(2)))
                "lerp" -> x(0) + (x(1) - x(0)) * x(2)
                "min" -> kotlin.math.min(x(0), x(1))
                "max" -> kotlin.math.max(x(0), x(1))
                "mod" -> if (x(1) == 0.0) 0.0 else x(0) % x(1)
                "pow" -> Math.pow(x(0), x(1))
                "exp" -> kotlin.math.exp(x(0))
                "ln" -> if (x(0) > 0) kotlin.math.ln(x(0)) else 0.0
                "atan" -> Math.toDegrees(kotlin.math.atan(x(0)))
                "atan2" -> Math.toDegrees(kotlin.math.atan2(x(0), x(1)))
                "asin" -> Math.toDegrees(kotlin.math.asin(x(0).coerceIn(-1.0, 1.0)))
                "acos" -> Math.toDegrees(kotlin.math.acos(x(0).coerceIn(-1.0, 1.0)))
                "sign" -> kotlin.math.sign(x(0))
                "random", "random_integer", "die_roll" -> { unknown += "math.$name (random, evaluated at its midpoint)"; (x(0) + x(1)) / 2 }
                else -> { unknown += "$name()"; 0.0 }
            }
        }
        fun value(name: String): Double {
            val n = when {
                name.startsWith("q.") -> "query." + name.substring(2)
                name.startsWith("v.") -> "variable." + name.substring(2)
                name.startsWith("t.") -> "temp." + name.substring(2)
                else -> name
            }
            return when (n) {
                "math.pi" -> PI
                "true" -> 1.0
                "false" -> 0.0
                else -> queries[n] ?: run { unknown += n; 0.0 }
            }
        }
    }
}
