package dev.rustmodforge.core

import dev.rustmodforge.core.analysis.ModAnalyzer
import dev.rustmodforge.core.model.DependencyKind
import dev.rustmodforge.core.model.GoalSelectorKind
import dev.rustmodforge.core.model.Loader
import dev.rustmodforge.core.model.RegistryKind
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.model.TraitKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AnalysisTest {
    private val fog by lazy { ModAnalyzer(scratch = Fixtures.tempDir("an")).analyze(Fixtures.jar("fog_horror")) }

    @Test
    fun forgeMetadataAndDependencies() {
        val m = fog.metadata
        assertEquals(Loader.FORGE, m.loader)
        assertEquals("fogwatcher", m.modId)
        assertEquals("The Watcher in the Fog", m.name)
        assertEquals("1.2.0", m.version)
        assertEquals("[1.20.1,1.21)", m.minecraftVersion)
        val deps = m.dependencies.associateBy { it.id }
        assertEquals(DependencyKind.REQUIRED, deps.getValue("geckolib").kind)
        assertEquals(DependencyKind.OPTIONAL, deps.getValue("jei").kind)
        assertEquals("client", deps.getValue("jei").side)
        assertEquals(DependencyKind.INCOMPATIBLE, deps.getValue("loudfog").kind)
    }

    @Test
    fun registrationsFromDeferredRegisterAndHelpers() {
        val regs = fog.registrations.associateBy { it.id }
        val watcher = regs.getValue("fogwatcher:the_watcher")
        assertEquals(RegistryKind.ENTITY_TYPE, watcher.kind)
        assertEquals("com.example.fogwatcher.entity.TheWatcher", watcher.valueClass)
        assertEquals("0.7", watcher.details["width"])
        assertEquals("2.9", watcher.details["height"])
        assertEquals("monster", watcher.details["category"])
        // Registered through a private register(String) helper.
        assertEquals(RegistryKind.SOUND_EVENT, regs.getValue("fogwatcher:watcher_scream").kind)
        assertEquals(RegistryKind.SOUND_EVENT, regs.getValue("fogwatcher:watcher_ambient").kind)
        assertEquals(RegistryKind.ITEM, regs.getValue("fogwatcher:fog_essence").kind)
    }

    @Test
    fun entityAttributesGoalsAndTraits() {
        val e = fog.entities.single { it.id == "fogwatcher:the_watcher" }
        assertEquals("Monster", e.vanillaBase)
        assertEquals(80.0, e.attributes["minecraft:max_health"])
        assertEquals(0.32, e.attributes["minecraft:movement_speed"])
        assertEquals(9.0, e.attributes["minecraft:attack_damage"])
        assertEquals(64.0, e.attributes["minecraft:follow_range"])
        val goals = e.goals.filter { it.selector == GoalSelectorKind.GOAL }.associateBy { it.priority }
        assertEquals("FloatGoal", goals.getValue(0).goal)
        assertTrue(goals.getValue(2).custom)
        assertEquals("MeleeAttackGoal", goals.getValue(4).goal)
        assertEquals(listOf("1.2", "0"), goals.getValue(4).args)
        assertEquals("LookAtPlayerGoal", goals.getValue(5).goal)
        assertEquals(listOf("Player", "32"), goals.getValue(5).args)
        val target = e.goals.single { it.selector == GoalSelectorKind.TARGET }
        assertEquals("NearestAttackableTargetGoal", target.goal)
        assertEquals(listOf("Player"), target.targets)

        val kinds = e.traits.map { it.kind }.toSet()
        for (k in listOf(TraitKind.VANISH_WHEN_APPROACHED, TraitKind.STALK_PLAYER, TraitKind.FREEZE_WHEN_LOOKED_AT, TraitKind.NIGHT_ONLY,
            TraitKind.APPLY_EFFECT_TO_PLAYER, TraitKind.PLAY_SOUND, TraitKind.SPAWN_PARTICLES, TraitKind.PERSISTENT, TraitKind.CUSTOM_MELEE,
            TraitKind.CHASE_PLAYER, TraitKind.JUMPSCARE_OVERLAY)) {
            assertTrue(k in kinds, "missing $k in $kinds")
        }
        assertEquals("8", e.traits.first { it.kind == TraitKind.VANISH_WHEN_APPROACHED }.params["distance"])
        assertEquals("24", e.traits.first { it.kind == TraitKind.STALK_PLAYER }.params["keep_distance"])
        assertEquals("minecraft:darkness", e.traits.first { it.kind == TraitKind.APPLY_EFFECT_TO_PLAYER }.params["effect"])
        assertEquals("fogwatcher:watcher_ambient", e.sounds.ambient)
        assertTrue("fogwatcher:watcher_scream" in e.sounds.other)
    }

    @Test
    fun geckoLibAssetsAreLinked() {
        val e = fog.entities.single()
        assertTrue(e.usesGeckoLib)
        assertEquals("assets/fogwatcher/geo/entity/the_watcher.geo.json", e.geoModel)
        assertEquals("assets/fogwatcher/animations/entity/the_watcher.animation.json", e.animationFile)
        assertEquals("assets/fogwatcher/textures/entity/the_watcher.png", e.texture)
        assertEquals("com.example.fogwatcher.client.TheWatcherRenderer", e.rendererClass)
        assertEquals(listOf("#minecraft:is_overworld"), e.spawn?.biomes)
        assertEquals(5, e.spawn?.weight)
        assertEquals(2, fog.sounds.size)
        assertEquals(1, fog.resourcesOf(ResourceKind.BIOME_MODIFIER).size)
    }

    @Test
    fun fabricIntermediaryRegistrations() {
        val a = ModAnalyzer().analyze(Fixtures.jar("simple_fabric"))
        assertEquals(Loader.FABRIC, a.metadata.loader)
        assertEquals("~1.21.1", a.metadata.minecraftVersion)
        assertEquals(DependencyKind.OPTIONAL, a.metadata.dependencies.single { it.id == "modmenu" }.kind)
        val regs = a.registrations.associateBy { it.id }
        assertEquals(RegistryKind.ITEM, regs.getValue("simplemod:ruby").kind)
        assertEquals(RegistryKind.BLOCK, regs.getValue("simplemod:ruby_block").kind)
    }

    @Test
    fun contentOnlyPackAndNestedJars() {
        val pack = Fixtures.jar("content_only")
        val a = ModAnalyzer(scratch = Fixtures.tempDir("nest")).analyze(Fixtures.jar("simple_fabric", mapOf("META-INF/jars/packdemo.jar" to pack)))
        assertEquals(1, a.nested.size)
        val n = a.nested.single()
        assertEquals(Loader.DATA_OR_RESOURCE_PACK, n.metadata.loader)
        assertTrue(n.metadata.minecraftVersion.contains("1.21"))
        assertEquals(1, n.resourcesOf(ResourceKind.FUNCTION).size)
    }

    @Test
    fun javaModelLayerIsExtracted() {
        val analyzer = ModAnalyzer()
        val a = analyzer.analyze(Fixtures.jar("java_model_mob"))
        assertEquals(Loader.NEOFORGE, a.metadata.loader)
        val e = a.entities.single()
        assertEquals("ghouls:ghoul", e.id)
        assertNull(e.geoModel)
        assertNotNull(e.javaModelLayer)
        val layer = analyzer.lastExtras.javaLayers.single()
        assertEquals(64, layer.textureWidth)
        assertEquals(listOf("body", "head", "right_arm", "left_arm", "right_leg", "left_leg"), layer.parts.map { it.name })
        assertEquals("body", layer.parts.single { it.name == "head" }.parent)
        assertEquals(0.5, layer.parts.single { it.name == "head" }.cubes.single().inflate)
        assertEquals(listOf(-5.0, 2.0, 0.0), layer.parts.single { it.name == "right_arm" }.offset)
        assertEquals(-1.5, layer.parts.single { it.name == "right_arm" }.rotation[0], 1e-6)
        assertTrue(layer.parts.single { it.name == "left_leg" }.cubes.single().mirror)
        val rig = layer.toRig()
        // Head of a biped: Java y -8..0 → Bedrock y 24..32.
        val head = rig.bone("head")!!.cubes.single()
        assertEquals(listOf(-4.0, 24.0, -4.0), head.origin)
        assertEquals(setOf("HurtByTargetGoal", "NearestAttackableTargetGoal"), e.goals.filter { it.selector == GoalSelectorKind.TARGET }.map { it.goal }.toSet())
    }

    @Test
    fun unsupportedApisAndMixinsAreReported() {
        val a = ModAnalyzer().analyze(Fixtures.jar("unsupported_apis"))
        val mixin = a.mixins.single()
        assertEquals(listOf("net.minecraft.client.gui.screens.TitleScreen"), mixin.targets)
        assertTrue(mixin.injections.any { it.startsWith("Inject") })
        val apis = a.unsupportedApis.map { it.api }.toSet()
        assertTrue("Reflection" in apis, "$apis")
        assertTrue("Networking" in apis, "$apis")
        assertTrue("Mixins" in apis, "$apis")
    }
}
