package dev.rustmodforge.core

import dev.rustmodforge.core.archive.ArchiveException
import dev.rustmodforge.core.archive.ArchiveLimits
import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.build.Validator
import dev.rustmodforge.core.compat.HorizonCompat
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.geo.GeoParser
import dev.rustmodforge.core.geo.AnimationSampler
import dev.rustmodforge.core.geo.Molang
import dev.rustmodforge.core.target.DataUpgrader
import dev.rustmodforge.core.target.RigBuilder
import dev.rustmodforge.core.util.JsonTree
import dev.rustmodforge.core.util.MiniToml
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ComponentsTest {
    private fun zip(entries: Map<String, ByteArray>): File {
        val f = File(Fixtures.tempDir("zip"), "t.zip")
        ZipOutputStream(f.outputStream()).use { z -> entries.forEach { (k, v) -> z.putNextEntry(ZipEntry(k)); z.write(v); z.closeEntry() } }
        return f
    }

    @Test
    fun pathTraversalAndAbsolutePathsAreRefused() {
        for (bad in listOf("../evil.txt", "a/../../evil", "/etc/passwd", "C:/x", "a\\b", "a//b")) {
            assertFailsWith<ArchiveException>(bad) { SafeArchive.open(zip(mapOf(bad to byteArrayOf(1)))).close() }
        }
    }

    @Test
    fun zipBombsAndOversizeEntriesAreRefused() {
        val bomb = zip(mapOf("big.bin" to ByteArray(8 shl 20)))
        assertFailsWith<ArchiveException> { SafeArchive.open(bomb).close() }
        val limits = ArchiveLimits(maxEntryBytes = 1000)
        assertFailsWith<ArchiveException> { SafeArchive.open(zip(mapOf("a.bin" to ByteArray(5000) { it.toByte() })), limits).close() }
    }

    @Test
    fun extractionStaysInsideTheTarget() {
        val f = zip(mapOf("assets/x/a.txt" to "hi".toByteArray()))
        val dir = Fixtures.tempDir("ex")
        SafeArchive.open(f).use { a ->
            assertEquals("hi", a.extractTo("assets/x/a.txt", dir).readText())
            assertFailsWith<ArchiveException> { a.extractTo("assets/x/a.txt", dir, "../../escape.txt") }
        }
    }

    @Test
    fun tomlSubset() {
        val t = MiniToml.parse("""
            # comment
            modLoader = "javafml" # trailing
            [[mods]]
            modId = 'fog'
            description = '''
            multi
            line'''
            [[dependencies.fog]]
            modId = "forge"
            mandatory = true
            versionRange = "[47,)"
            [x.y]
            n = 1_000
            f = 2.5
            arr = [1, "two", { inline = true }]
        """.trimIndent())
        assertEquals("javafml", t["modLoader"])
        @Suppress("UNCHECKED_CAST") val mods = t["mods"] as List<Map<String, Any?>>
        assertEquals("multi\nline", mods.single()["description"])
        @Suppress("UNCHECKED_CAST") val deps = (t["dependencies"] as Map<String, Any?>)["fog"] as List<Map<String, Any?>>
        assertEquals(true, deps.single()["mandatory"])
        @Suppress("UNCHECKED_CAST") val y = (t["x"] as Map<String, Any?>)["y"] as Map<String, Any?>
        assertEquals(1000L, y["n"]); assertEquals(2.5, y["f"])
    }

    @Test
    fun molangEvaluatesAnimationExpressions() {
        val m = Molang(mapOf("query.anim_time" to 0.25))
        assertEquals(30.0, m.eval("math.sin(query.anim_time * 360) * 30"), 1e-9)
        assertEquals(-30.0, m.eval("-math.sin(q.anim_time * 360) * 30"), 1e-9)
        assertEquals(5.0, m.eval("math.clamp(10, 0, 5)"))
        assertEquals(2.0, m.eval("query.anim_time > 0.1 ? 2 : 3"))
        assertEquals(0.0, m.eval("variable.unknown_thing"))
        assertTrue("variable.unknown_thing" in m.unknown)
    }

    @Test
    fun recipeAndLootUpgradesMatchHorizonCarry() {
        val recipe = JsonTree.obj(JsonTree.parse("""{"type":"minecraft:crafting_shapeless","ingredients":[{"item":"a:b"},{"tag":"c:gems"}],"result":{"item":"a:c","count":2}}"""))!!
        assertTrue(DataUpgrader.upgradeRecipe(recipe))
        assertEquals(listOf("a:b", "#c:gems"), recipe["ingredients"])
        assertEquals("a:c", JsonTree.obj(recipe["result"])!!["id"])
        val loot = JsonTree.parse("""{"pools":[{"rolls":{"min":1,"max":2},"conditions":[{"condition":"minecraft:random_chance","chance":0.5}],
            "entries":[{"type":"minecraft:item","name":"a:b","functions":[{"function":"minecraft:set_count","count":{"min":1,"max":3}}]}]}]}""")
        DataUpgrader.upgradeLoot(loot)
        val text = JsonTree.write(loot)
        assertTrue(!text.contains("\"conditions\"") && !text.contains("\"functions\""), text)
        assertTrue(text.contains("\"modifier\"") && text.contains("\"condition\"") && text.contains("minecraft:uniform"), text)
        assertEquals("data/m/loot_table/x.json", DataUpgrader.renamePath("data/m/loot_tables/x.json"))
        assertEquals("data/c/tags/item/a.json", DataUpgrader.renamePath("data/c/tags/items/a.json"))
        val custom = JsonTree.obj(JsonTree.parse("""{"type":"create:mixing","ingredients":[{"item":"a:b"}]}"""))!!
        assertTrue(!DataUpgrader.upgradeRecipe(custom))
    }

    @Test
    fun rigRestPoseAndAnimation() {
        val geo = File(Fixtures.root, "fog_horror/resources/assets/fogwatcher/geo/entity/the_watcher.geo.json").readText()
        val model = GeoParser.parseGeometry(geo, "x").single()
        val rig = RigBuilder(model)
        val rest = rig.pose(null, 0.0)
        // The head's pivot is 38 px up: 2.375 blocks, facing turned 180° about y.
        val head = rest.getValue("head")
        assertEquals(2.375, head.translation[1], 1e-9)
        assertEquals(1.0, kotlin.math.abs(head.rotation.y), 1e-9)
        // Legs 24 px long fit block-model bounds without downscaling; nothing exceeds -16..32.
        for (b in rig.drawnBones) {
            @Suppress("UNCHECKED_CAST") val els = rig.boneModel(b, "t")["elements"] as List<Map<String, Any?>>
            for (e in els) for (k in listOf("from", "to")) (e[k] as List<Double>).forEach { assertTrue(it in -16.0..32.0, "${b.name} $k $it") }
        }
        val anims = GeoParser.parseAnimations(File(Fixtures.root, "fog_horror/resources/assets/fogwatcher/animations/entity/the_watcher.animation.json").readText())
        val walk = anims.single { it.name.endsWith("walk") }
        val s = AnimationSampler(walk)
        assertEquals(30.0, s.pose("left_leg", 0.25).rotation[0], 1e-6)
        val moved = rig.pose(walk, 0.25, s).getValue("left_leg")
        val restLeg = rest.getValue("left_leg").rotation
        // 180° facing turn then 30° about x: the quaternion (0, cos 15°, -sin 15°, 0).
        assertEquals(kotlin.math.cos(Math.toRadians(15.0)), moved.rotation.y, 1e-6)
        assertEquals(-kotlin.math.sin(Math.toRadians(15.0)), moved.rotation.z, 1e-6)
        assertTrue(restLeg != moved.rotation)
        val attack = anims.single { it.name.endsWith("attack") }
        assertEquals(listOf("watcher_scream"), attack.sounds.map { it.effect })
    }

    @Test
    fun validatorRefusesWhatHorizonRefuses() {
        val bad = zip(mapOf(
            "horizon-mod.toml" to "id = \"x\"\nname = \"x\"\nversion = \"1\"\napi = \"0.2\"\ncapabilities = [\"registries\", \"render\"]\ncolour = 1\n".toByteArray(),
            "assets/minecraft/textures/block/stone.png" to byteArrayOf(1),
            "data/x/horizon/fluid/a.json" to "{}".toByteArray(),
            "data/x/function/a.mcfunction" to "frobnicate @s\nfunction x:missing\n".toByteArray(),
            "assets/x/models/item/a.json" to "{\"textures\":{\"0\":\"x:item/none\"}}".toByteArray(),
        ))
        val issues = Validator.validateHmod(bad, TargetId.HORIZON_ANDROID).filter { it.error }.map { it.message }
        for (expected in listOf("unknown key colour", "experimental", "outside the namespaces", "reads no data/<id>/horizon/fluid",
            "unknown command frobnicate", "calls x:missing", "texture x:item/none")) {
            assertTrue(issues.any { it.contains(expected) }, "missing \"$expected\" in $issues")
        }
        val badId = zip(mapOf("horizon-mod.toml" to "id = \"Bad-Id\"\nname = \"x\"\nversion = \"1\"\napi = \"0.2\"\n".toByteArray()))
        assertTrue(Validator.validateHmod(badId, TargetId.HORIZON_DESKTOP).any { it.error && it.message.contains("id \"Bad-Id\"") })
    }

    @Test
    fun compatDatabaseMatchesTheCatalog() {
        assertEquals(434, HorizonCompat.hookCatalog.hooks.size)
        assertTrue(HorizonCompat.hasHook("mob_submit") && HorizonCompat.hasHook("entity_tick_pre") && HorizonCompat.hasHelper("draw_cube"))
        assertTrue(!HorizonCompat.android.loadsHnmod && HorizonCompat.desktop.loadsHnmod)
        assertTrue(HorizonCompat.android.livingTemplates.isEmpty())
    }
}
