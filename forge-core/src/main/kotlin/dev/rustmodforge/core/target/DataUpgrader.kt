package dev.rustmodforge.core.target

import dev.rustmodforge.core.util.JsonTree

/**
 * Rewrites 1.20/1.21.1-era data into the 26.3 shapes Horizon reads. The rules are ported from
 * Horizon's own `horizon-port-pack` carry (crates/horizon-port-pack/src/carry.rs, MIT), so a
 * file converted here loads the way Horizon's tooling would load it.
 */
object DataUpgrader {
    /** 1.21 renamed these data folders to the singular. */
    val renamedIn121 = listOf(
        "recipes" to "recipe", "loot_tables" to "loot_table", "structures" to "structure", "advancements" to "advancement",
        "predicates" to "predicate", "item_modifiers" to "item_modifier", "functions" to "function",
        "tags/blocks" to "tags/block", "tags/items" to "tags/item", "tags/entity_types" to "tags/entity_type",
        "tags/fluids" to "tags/fluid", "tags/game_events" to "tags/game_event", "tags/functions" to "tags/function",
    )

    /** Ids vanilla renamed after 1.21.1. */
    private val renamedIds = mapOf("minecraft:chain" to "minecraft:iron_chain")

    /** `data/m/recipes/a.json` → `data/m/recipe/a.json`; unchanged otherwise. */
    fun renamePath(path: String): String {
        if (!path.startsWith("data/")) return path
        val ns = path.removePrefix("data/").substringBefore('/')
        val rest = path.removePrefix("data/$ns/")
        for ((before, after) in renamedIn121) {
            if (rest.startsWith("$before/")) return "data/$ns/$after/${rest.removePrefix("$before/")}"
        }
        return path
    }

    fun ingredient(v: Any?): Any? = when (v) {
        is String -> v
        is Map<*, *> -> if (v.size == 1) (v["item"] as? String) ?: (v["tag"] as? String)?.let { "#$it" } else null
        is List<*> -> {
            val ids = v.map { x -> (x as? Map<*, *>)?.takeIf { it.size == 1 }?.get("item") as? String }
            if (ids.any { it == null }) null else if (ids.size == 1) ids.first() else ArrayList<Any?>(ids)
        }
        else -> null
    }

    /** Upgrades a vanilla recipe in place; false (unchanged) for custom types or unconvertible ingredients. */
    fun upgradeRecipe(recipe: MutableMap<String, Any?>): Boolean {
        val type = recipe["type"] as? String ?: return false
        if (!type.startsWith("minecraft:") || recipe.containsKey("neoforge:conditions") || recipe.containsKey("forge:conditions")) return false
        val copy = JsonTree.parse(JsonTree.write(recipe)) as MutableMap<String, Any?>
        JsonTree.obj(copy["key"])?.let { key -> for (k in key.keys.toList()) key[k] = ingredient(key[k]) ?: return false }
        JsonTree.list(copy["ingredients"])?.let { list -> for (i in list.indices) list[i] = ingredient(list[i]) ?: return false }
        for (field in listOf("ingredient", "base", "addition", "template")) {
            if (copy.containsKey(field)) copy[field] = ingredient(copy[field]) ?: return false
        }
        // Before 1.20.5 a result named its item as `item`; 26.3 reads `id`.
        JsonTree.obj(copy["result"])?.let { r -> if (r.containsKey("item") && !r.containsKey("id")) { r["id"] = r.remove("item") } }
        if (copy["result"] is String) copy["result"] = JsonTree.of("id" to copy["result"])
        recipe.clear(); recipe.putAll(copy)
        return true
    }

    fun renameIds(v: Any?): Any? = when (v) {
        is String -> renamedIds[v] ?: v
        is MutableList<*> -> { @Suppress("UNCHECKED_CAST") val l = v as MutableList<Any?>; for (i in l.indices) l[i] = renameIds(l[i]); l }
        is MutableMap<*, *> -> { @Suppress("UNCHECKED_CAST") val m = v as MutableMap<String, Any?>; for (k in m.keys.toList()) m[k] = renameIds(m[k]); m }
        else -> v
    }

    /** `enter_block` criteria name their block as `blocks` in 26.3. */
    fun upgradeAdvancement(v: MutableMap<String, Any?>): Boolean {
        var changed = false
        JsonTree.obj(v["criteria"])?.values?.forEach { c ->
            val crit = JsonTree.obj(c) ?: return@forEach
            val trigger = crit["trigger"] as? String
            if (trigger != "minecraft:enter_block" && trigger != "enter_block") return@forEach
            val cond = JsonTree.obj(crit["conditions"]) ?: return@forEach
            if (!cond.containsKey("blocks") && cond.containsKey("block")) { cond["blocks"] = cond.remove("block"); changed = true }
        }
        return changed
    }

    /** A 1.21.1 loot table in 26.3's shape (see Horizon's `upgrade_loot`). */
    fun upgradeLoot(v: Any?) {
        when (v) {
            is MutableList<*> -> v.forEach { upgradeLoot(it) }
            is MutableMap<*, *> -> {
                @Suppress("UNCHECKED_CAST") val o = v as MutableMap<String, Any?>
                JsonTree.list(o["pools"])?.forEach { pool -> JsonTree.obj(pool)?.let { p -> listOf("rolls", "bonus_rolls").forEach { k -> p[k]?.let { typeNumber(it) } } } }
                (o.remove("conditions") as? MutableList<Any?>)?.let { list ->
                    list.forEach { upgradeCondition(it) }
                    o["condition"] = if (list.size == 1) list[0] else JsonTree.of("type" to "minecraft:all_of", "terms" to list)
                }
                (o.remove("functions") as? MutableList<Any?>)?.let { list ->
                    for (f in list) { renameKind(f, "function"); typeFunctionNumbers(f); upgradeLoot(f) }
                    o["modifier"] = list
                }
                for ((k, x) in o) if (k != "condition" && k != "modifier") upgradeLoot(x)
            }
        }
    }

    private fun typeNumber(v: Any?) {
        val o = JsonTree.obj(v) ?: return
        if (!o.containsKey("type") && o.containsKey("min") && o.containsKey("max")) o["type"] = "minecraft:uniform"
        val kind = (o["type"] as? String)?.removePrefix("minecraft:") ?: ""
        val bounds = when (kind) { "uniform" -> listOf("min", "max"); "binomial" -> listOf("n", "p"); else -> emptyList() }
        bounds.forEach { o[it]?.let { b -> typeNumber(b) } }
    }

    private fun typeFunctionNumbers(f: Any?) {
        val o = JsonTree.obj(f) ?: return
        val kind = (o["type"] as? String)?.removePrefix("minecraft:") ?: ""
        fun each(list: String, key: String) = JsonTree.list(o[list])?.forEach { x -> JsonTree.obj(x)?.get(key)?.let { typeNumber(it) } }
        when (kind) {
            "set_stew_effect" -> each("effects", "duration")
            "set_attributes" -> each("modifiers", "amount")
            "set_enchantments" -> JsonTree.obj(o["enchantments"])?.values?.forEach { typeNumber(it) }
            "limit_count" -> JsonTree.obj(o["limit"])?.let { l -> listOf("min", "max").forEach { k -> l[k]?.let { typeNumber(it) } } }
            "set_count", "enchanted_count_increase" -> o["count"]?.let { typeNumber(it) }
            "set_damage" -> o["damage"]?.let { typeNumber(it) }
            "enchant_with_levels" -> o["levels"]?.let { typeNumber(it) }
            "set_ominous_bottle_amplifier" -> o["amplifier"]?.let { typeNumber(it) }
        }
    }

    private fun renameKind(v: Any?, key: String) {
        val o = JsonTree.obj(v) ?: return
        if (!o.containsKey("type") && o.containsKey(key)) o["type"] = o.remove(key)
    }

    private val entityFields = listOf("distance", "movement", "location", "stepping_on", "movement_affected_by", "effects", "nbt", "flags",
        "equipment", "periodic_tick", "team", "slots", "components", "predicates", "type_specific")
    private val entityNested = listOf("vehicle", "passenger", "targeted_entity")

    private fun upgradeCondition(c: Any?) {
        renameKind(c, "condition")
        val o = JsonTree.obj(c) ?: return
        o["term"]?.let { upgradeCondition(it) }
        JsonTree.list(o["terms"])?.forEach { upgradeCondition(it) }
        when (o["type"]) {
            "minecraft:match_tool" -> namedToolCondition(o["predicate"])?.let { named -> o.clear(); o["type"] = named }
            "minecraft:entity_properties" -> o["predicate"]?.let { upgradeEntityPredicate(it) }
            "minecraft:damage_source_properties" -> JsonTree.obj(o["predicate"])?.let { p -> listOf("direct_entity", "source_entity").forEach { k -> p[k]?.let { upgradeEntityPredicate(it) } } }
        }
    }

    /** 26.3 keys entity predicate fields by registry name: `type` → `minecraft:entity_type`, `flags` → `minecraft:flags`. */
    fun upgradeEntityPredicate(p: Any?) {
        val o = JsonTree.obj(p) ?: return
        o.remove("type")?.let { o["minecraft:entity_type"] = it }
        for (f in entityNested) o.remove(f)?.let { upgradeEntityPredicate(it); o["minecraft:$f"] = it }
        for (f in entityFields) o.remove(f)?.let { o["minecraft:$f"] = it }
    }

    private fun namedToolCondition(predicate: Any?): String? {
        val p = JsonTree.obj(predicate) ?: return null
        if (p.keys == setOf("items")) {
            val items = p["items"]
            if (items == "minecraft:shears" || items == listOf("minecraft:shears")) return "minecraft:tool/can_shear"
        }
        if (p.keys == setOf("predicates")) {
            val list = JsonTree.list(JsonTree.obj(p["predicates"])?.get("minecraft:enchantments")) ?: return null
            val e = JsonTree.obj(list.singleOrNull()) ?: return null
            val levels = JsonTree.obj(e["levels"])
            val min = (levels?.get("min") as? Number)?.toLong() ?: 1
            if (e["enchantments"] == "minecraft:silk_touch" && min <= 1 && levels?.containsKey("max") != true && JsonTree.obj(p["predicates"])?.size == 1) {
                return "minecraft:tool/can_silk_touch"
            }
        }
        return null
    }

    /** Block state variants: 1.21.1's Gson read `"true"`/`"90"`, 26.3's codec needs real types. */
    fun upgradeAssets(v: Any?): Boolean {
        var changed = false
        when (v) {
            is MutableList<*> -> v.forEach { changed = upgradeAssets(it) or changed }
            is MutableMap<*, *> -> {
                @Suppress("UNCHECKED_CAST") val o = v as MutableMap<String, Any?>
                if (o.containsKey("model")) {
                    for (k in listOf("uvlock")) (o[k] as? String)?.toBooleanStrictOrNull()?.let { o[k] = it; changed = true }
                    for (k in listOf("x", "y", "weight")) (o[k] as? String)?.toLongOrNull()?.let { o[k] = it; changed = true }
                }
                for (k in o.keys.toList()) {
                    val x = o[k]
                    if (x is String) {
                        val path = x.removePrefix("minecraft:")
                        if (path == "block/chain" || path == "item/chain") { o[k] = "minecraft:" + path.replace("chain", "iron_chain"); changed = true }
                    } else changed = upgradeAssets(x) or changed
                }
            }
        }
        return changed
    }
}
