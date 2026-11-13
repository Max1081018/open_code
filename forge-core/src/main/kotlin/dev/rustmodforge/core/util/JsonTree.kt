package dev.rustmodforge.core.util

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.doubleOrNull

/** Mutable JSON (LinkedHashMap / ArrayList / String / Long / Double / Boolean / null) for in-place rewrites. */
object JsonTree {
    val pretty = Json { prettyPrint = true; prettyPrintIndent = "  " }
    private val lenient = Json { isLenient = true; allowTrailingComma = true; ignoreUnknownKeys = true }

    fun parse(text: String): Any? = toAny(lenient.parseToJsonElement(text.removePrefix("﻿")))

    fun toAny(e: JsonElement): Any? = when (e) {
        is JsonNull -> null
        is JsonObject -> LinkedHashMap<String, Any?>().also { m -> e.forEach { (k, v) -> m[k] = toAny(v) } }
        is JsonArray -> e.mapTo(ArrayList()) { toAny(it) }
        is JsonPrimitive -> when {
            e.isString -> e.content
            e.booleanOrNull != null -> e.booleanOrNull
            e.longOrNull != null -> e.longOrNull
            else -> e.doubleOrNull
        }
    }

    fun toElement(v: Any?): JsonElement = when (v) {
        null -> JsonNull
        is JsonElement -> v
        is Map<*, *> -> JsonObject(v.entries.associate { (k, x) -> k.toString() to toElement(x) })
        is Iterable<*> -> JsonArray(v.map { toElement(it) })
        is Array<*> -> JsonArray(v.map { toElement(it) })
        is DoubleArray -> JsonArray(v.map { JsonPrimitive(it) })
        is Boolean -> JsonPrimitive(v)
        is Int -> JsonPrimitive(v)
        is Long -> JsonPrimitive(v)
        is Float -> JsonPrimitive(clean(v.toDouble()))
        is Double -> JsonPrimitive(clean(v))
        is Number -> JsonPrimitive(v)
        else -> JsonPrimitive(v.toString())
    }

    /** Whole numbers print without a fraction; others round to 6 decimals to keep files stable. */
    private fun clean(d: Double): Number = if (d == Math.rint(d) && kotlin.math.abs(d) < 1e15) d.toLong() else Math.round(d * 1e6) / 1e6

    fun write(v: Any?): String = pretty.encodeToString(JsonElement.serializer(), toElement(v)) + "\n"

    @Suppress("UNCHECKED_CAST")
    fun obj(v: Any?): MutableMap<String, Any?>? = v as? MutableMap<String, Any?>

    @Suppress("UNCHECKED_CAST")
    fun list(v: Any?): MutableList<Any?>? = v as? MutableList<Any?>

    fun of(vararg pairs: Pair<String, Any?>): MutableMap<String, Any?> = linkedMapOf(*pairs)
}
