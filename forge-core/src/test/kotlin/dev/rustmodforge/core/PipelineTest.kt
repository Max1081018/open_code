package dev.rustmodforge.core

import dev.rustmodforge.core.build.HorizonModChecker
import dev.rustmodforge.core.build.LocalCargoBackend
import dev.rustmodforge.core.build.Validator
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.pipeline.CancellationToken
import dev.rustmodforge.core.pipeline.CancelledException
import dev.rustmodforge.core.pipeline.ConversionPipeline
import dev.rustmodforge.core.pipeline.PipelineOptions
import dev.rustmodforge.core.pipeline.Project
import dev.rustmodforge.core.pipeline.Quality
import dev.rustmodforge.core.pipeline.Stage
import dev.rustmodforge.core.pipeline.StageState
import dev.rustmodforge.core.report.FeatureStatus
import dev.rustmodforge.core.target.PackGenerator
import dev.rustmodforge.core.report.StepStatus
import dev.rustmodforge.core.util.JsonTree
import dev.rustmodforge.core.util.MiniToml
import java.io.File
import java.util.zip.ZipFile
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class PipelineTest {
    private fun project(name: String, quality: Quality, vararg jars: File, targets: List<TargetId> = listOf(TargetId.HORIZON_ANDROID, TargetId.HORIZON_DESKTOP)) =
        Project.create(Fixtures.tempDir("proj"), name, quality, targets, jars.toList())

    /** Optional external checks: Horizon's checker and a Horizon checkout, when the environment provides them. */
    private val checkers = buildMap {
        System.getenv("RMF_HORIZON_MOD_BIN")?.let { put(TargetId.HORIZON_ANDROID, HorizonModChecker(File(it))) }
        System.getenv("RMF_HORIZON_MOD_BIN_UPSTREAM")?.let { put(TargetId.HORIZON_DESKTOP, HorizonModChecker(File(it))) }
    }
    private val horizonSrc = System.getenv("RMF_HORIZON_SRC")?.let { File(it) }

    private fun entries(f: File) = ZipFile(f).use { z -> z.entries().toList().map { it.name }.toSet() }
    private fun text(f: File, entry: String) = ZipFile(f).use { z -> z.getInputStream(z.getEntry(entry)).readBytes().decodeToString() }

    @Test
    fun horrorModAdvancedBothTargets() {
        val p = project("fog", Quality.ADVANCED, Fixtures.jar("fog_horror"))
        val opts = PipelineOptions(horizonCheckers = checkers, buildBackend = horizonSrc?.let { LocalCargoBackend(it) })
        val report = ConversionPipeline(p, opts).run().single()
        val android = File(p.out, "fogwatcher-android.hmod")
        val desktop = File(p.out, "fogwatcher-desktop.hmod")
        val native = File(p.out, "fogwatcher.hnmod")
        assertTrue(android.exists() && desktop.exists() && native.exists())

        // Our validator finds no errors on any output.
        assertEquals(emptyList(), Validator.validateHmod(android, TargetId.HORIZON_ANDROID).filter { it.error })
        assertEquals(emptyList(), Validator.validateHmod(desktop, TargetId.HORIZON_DESKTOP).filter { it.error })
        assertEquals(emptyList(), Validator.validateHnmod(native).filter { it.error })

        val a = entries(android)
        // Content carried, folders renamed to 1.21+ names, item definitions added.
        assertTrue("assets/fogwatcher/textures/entity/the_watcher.png" in a)
        assertTrue("data/fogwatcher/loot_table/entities/the_watcher.json" in a)
        assertTrue("data/fogwatcher/recipe/fog_lantern.json" in a)
        assertTrue("assets/fogwatcher/items/fog_essence.json" in a)
        assertTrue("data/fogwatcher/forge/biome_modifier/watcher_spawns.json" in entries(desktop))
        // Horizon Android declares no living mob types: the creature is a tagged zombie set up by functions.
        assertTrue(a.none { it.contains("/horizon/entity_type/") })
        assertTrue("data/fogwatcher/function/summon/the_watcher.mcfunction" in a)
        assertTrue("data/fogwatcher/predicate/spawn/the_watcher.json" in a)
        assertTrue(a.none { it.contains("biome_modifier") })
        val init = text(android, "data/fogwatcher/function/e/the_watcher/init.mcfunction")
        assertTrue(init.contains("attribute @s minecraft:max_health base set 80"), init)
        assertTrue(init.contains("DeathLootTable:\"fogwatcher:entities/the_watcher\""), init)
        // Upstream declares it from the zombie template with the mod's attributes.
        val decl = JsonTree.obj(JsonTree.parse(text(desktop, "data/fogwatcher/horizon/entity_type/the_watcher.json")))!!
        assertEquals("minecraft:zombie", decl["template"])
        assertEquals(80L, JsonTree.obj(decl["attributes"])!!["minecraft:max_health"])
        // Rig, behaviour functions and tick tag.
        assertTrue("assets/fogwatcher/models/item/rig/the_watcher/head.json" in a)
        assertTrue("assets/fogwatcher/items/rig/the_watcher/head.json" in a)
        assertTrue("assets/fogwatcher/textures/item/rig/the_watcher_glow.png" in a)
        assertTrue("data/minecraft/tags/function/tick.json" in a)
        val ai = text(android, "data/fogwatcher/function/e/the_watcher/tick.mcfunction")
        assertTrue(ai.contains("function fogwatcher:e/the_watcher/vanish"), ai)
        assertTrue(ai.contains("effect give @a[distance=..16,gamemode=!spectator] minecraft:darkness"), ai)
        assertTrue(ai.contains("#looked"), ai)
        assertTrue(a.any { it.startsWith("data/fogwatcher/function/e/the_watcher/anim/") })
        // Loot upgraded: no 1.21.1-style keys remain.
        assertTrue(!text(android, "data/fogwatcher/loot_table/entities/the_watcher.json").contains("\"functions\""))
        // The desktop content mod has no functions (the native mod does that work there).
        assertTrue(entries(desktop).none { it.endsWith(".mcfunction") })
        val manifest = MiniToml.parse(text(android, "horizon-mod.toml"))
        assertEquals("0.2", manifest["api"]); assertEquals("both", manifest["side"])

        val lib = text(native, "mixins/fogwatcher/api/src/lib.rs")
        assertTrue(lib.contains("impl Hooks for Mod"))
        assertTrue(lib.contains("goals::MeleeAttack::new(1.2, false)"), lib)
        assertTrue(lib.contains("VanishWhenNear { distance: 8.0 }"))
        assertTrue(lib.contains("Stalk { keep: 24.0"))

        // Report: statuses with reasons, honest build steps.
        val byName = report.features.associateBy { it.name + "|" + it.target }
        assertTrue(report.features.any { it.status == FeatureStatus.PARTIAL && it.name.startsWith("Model of fogwatcher:the_watcher") && it.target == "android" })
        assertTrue(report.features.filter { it.status != FeatureStatus.IMPLEMENTED }.all { it.reason.isNotBlank() }, byName.keys.toString())
        assertTrue(report.build.any { it.name.startsWith("Runtime test") && it.status == StepStatus.NOT_RUN })
        if (horizonSrc == null) assertTrue(report.build.any { it.name.startsWith("Rust compilation") && it.status == StepStatus.NOT_RUN })
        else assertEquals(StepStatus.PASSED, report.build.first { it.name.startsWith("Rust compilation") && it.target == "desktop" }.status,
            report.build.first { it.name.startsWith("Rust compilation") && it.target == "desktop" }.log.takeLast(3000))
        if (checkers.isNotEmpty()) assertTrue(report.build.filter { it.name.startsWith("Horizon's own checker") && it.status != StepStatus.NOT_RUN }.all { it.status == StepStatus.PASSED },
            report.build.filter { it.name.startsWith("Horizon's own checker") }.joinToString { it.log })
        assertTrue(report.dependencies.single { it.id == "geckolib" }.status == "reconstructed")
        assertTrue(report.dependencies.single { it.id == "loudfog" }.status == "incompatible")
        assertTrue(File(p.out, "fogwatcher-report.md").readText().contains("## Reconstruction"))
        assertEquals(StageState.DONE, p.load().stages.single { it.stage == Stage.REPORT }.state)
    }

    /** The agent runs inside the pipeline, uses the real tools, and its work is packed. */
    @Test
    fun theAgentRunsInsideTheConversionAndItsWorkIsPacked() {
        val p = project("agent-pipeline", Quality.MAXIMUM, Fixtures.jar("fog_horror"), targets = listOf(TargetId.HORIZON_DESKTOP))
        val script = listOf(
            """{"thought":"read the entity","tool":"entity_report","args":{"id":"fogwatcher:the_watcher"}}""",
            """{"thought":"look up the API","tool":"search_horizon_api","args":{"query":"goal can_use navigation"}}""",
            """{"thought":"add a module","tool":"write_rust","args":{"path":"mixins/fogwatcher/api/src/notes.rs","content":"//! Reconstructed by the agent.\npub const KEEP_DISTANCE: f64 = 24.0;\n"}}""",
            """{"thought":"check","tool":"validate","args":{}}""",
            """{"tool":"finish","args":{"summary":"kept the stalk distance from the original","unsupported":"renderer fog"}}""",
        )
        var steps = 0
        val provider = object : dev.rustmodforge.core.ai.AiProvider {
            var calls = 0
            override fun complete(system: String, user: String, maxTokens: Int): dev.rustmodforge.core.ai.AiReply {
                // The prompt carries the real API revision and the project's own findings.
                assertTrue(system.contains(dev.rustmodforge.core.compat.HorizonApiIndex.revision.take(10)), "no revision in the prompt")
                val text = script.getOrElse(calls) { """{"tool":"finish","args":{"summary":"done"}}""" }
                calls++
                return dev.rustmodforge.core.ai.AiReply(text, 50, 20, false)
            }
        }
        val report = ConversionPipeline(p, PipelineOptions(agentProvider = provider, onAgentStep = { steps++ })).run().single()

        assertTrue(steps >= 5, "the app saw $steps agent steps")
        val agentStep = report.build.single { it.name.startsWith("AI reconstruction agent") }
        // Validators clean but no compiler here: neither passed nor failed.
        assertEquals(StepStatus.UNVERIFIED, agentStep.status, agentStep.detail)
        assertTrue(agentStep.detail.contains("1 file(s) kept"), agentStep.detail)
        // The agent's file is inside the packaged .hnmod, not just on disk.
        assertTrue("mixins/fogwatcher/api/src/notes.rs" in entries(File(p.out, "fogwatcher.hnmod")))
        assertTrue(report.features.any { it.name == "AI reconstruction" && it.route.contains("stalk distance") })
        assertTrue(report.features.any { it.name == "Missing Horizon capability" && it.reason.contains("renderer fog") })
        // Verification statuses are per file and name what was not reached.
        val hnmod = report.outputs.single { it.name.endsWith(".hnmod") }
        assertTrue(dev.rustmodforge.core.report.Verification.PACKAGED in hnmod.reached)
        assertTrue(dev.rustmodforge.core.report.Verification.RUNTIME_TESTED !in hnmod.reached)
        assertTrue(dev.rustmodforge.core.report.Verification.COMPILED !in hnmod.reached, "nothing compiled it, so it must not claim COMPILED")
        // The agent's steps are kept for the app's history.
        val saved = dev.rustmodforge.core.agent.Knowledge.stepsOf(File(p.dir, "knowledge"))
        assertTrue(saved.any { it.tool == "search_horizon_api" } && saved.any { it.tool == "write_rust" })
    }

    @Test
    fun fastQualityIsContentOnly() {
        val p = project("fog-fast", Quality.FAST, Fixtures.jar("fog_horror"), targets = listOf(TargetId.HORIZON_ANDROID))
        val report = ConversionPipeline(p).run().single()
        val android = File(p.out, "fogwatcher-android.hmod")
        assertTrue(entries(android).none { it.endsWith(".mcfunction") || it.contains("/rig/") })
        assertTrue(!File(p.out, "fogwatcher.hnmod").exists())
        assertTrue(report.features.any { it.category == "Behaviour" && it.status == FeatureStatus.UNSUPPORTED })
    }

    @Test
    fun maximumQualitySamplesEveryTick() {
        val p = project("fog-max", Quality.MAXIMUM, Fixtures.jar("fog_horror"), targets = listOf(TargetId.HORIZON_ANDROID))
        ConversionPipeline(p).run()
        val frames = entries(File(p.out, "fogwatcher-android.hmod")).filter { it.contains("/anim/1/f") }
        // The walk clip is 1 s: 20 frames at every tick (Advanced writes 10).
        assertEquals(20, frames.size)
    }

    @Test
    fun simpleAndJavaModelModsConvertTogether() {
        val p = project("multi", Quality.ADVANCED, Fixtures.jar("simple_fabric"), Fixtures.jar("java_model_mob"), Fixtures.jar("content_only"))
        val reports = ConversionPipeline(p, PipelineOptions(horizonCheckers = checkers, buildBackend = horizonSrc?.let { LocalCargoBackend(it) })).run()
        assertEquals(3, reports.size)
        for (f in p.out.listFiles()!!.filter { it.name.endsWith(".hmod") }) {
            val target = if (f.name.contains("-android")) TargetId.HORIZON_ANDROID else TargetId.HORIZON_DESKTOP
            assertEquals(emptyList(), Validator.validateHmod(f, target).filter { it.error }, f.name)
        }
        val simple = File(p.out, "simplemod-android.hmod")
        assertTrue("data/simplemod/horizon/item/ruby.json" in entries(simple))
        assertTrue("data/simplemod/horizon/block/ruby_block.json" in entries(simple))
        assertTrue("data/c/tags/item/gems.json" in entries(simple))
        val recipe = text(simple, "data/simplemod/recipe/ruby_block.json")
        assertTrue(recipe.contains("\"#\": \"simplemod:ruby\""), recipe)
        // The Java-model mob gets a rig on Android and a drawn model on desktop.
        assertTrue(entries(File(p.out, "ghouls-android.hmod")).any { it.startsWith("assets/ghouls/models/item/rig/ghoul/") })
        assertTrue(text(File(p.out, "ghouls.hnmod"), "mixins/ghouls/api/src/lib.rs").contains("GHOUL_BONES"))
        if (horizonSrc != null) assertEquals(StepStatus.PASSED, reports.single { it.modId == "ghouls" }.build.first { it.name.startsWith("Rust compilation") && it.target == "desktop" }.status)
    }

    @Test
    fun cancelAndResume() {
        val p = project("resume", Quality.ADVANCED, Fixtures.jar("fog_horror"), targets = listOf(TargetId.HORIZON_ANDROID))
        val token = CancellationToken()
        var seen = 0
        assertFailsWith<CancelledException> {
            ConversionPipeline(p, progress = { _, _, _ -> if (++seen == 5) token.cancel() }, cancel = token).run()
        }
        assertTrue(p.load().lastError!!.startsWith("Cancelled"))
        // Resume: a fresh run finishes and reuses nothing it should not.
        val report = ConversionPipeline(p).run().single()
        assertEquals("fogwatcher", report.modId)
        assertTrue(File(p.out, "fogwatcher-android.hmod").exists())
    }

    /**
     * The bug a user hit: a sound mod replaces vanilla's own files, which a content mod may not
     * hold, so it converted to a .hmod that changed nothing in game. Its content belongs in a
     * resource pack (and a data pack), which is what the launcher applies over vanilla.
     */
    @Test
    fun vanillaOverridesBecomePacksThatActuallyApply() {
        val p = project("sounds", Quality.ADVANCED, Fixtures.jar("better_sounds"), targets = listOf(TargetId.HORIZON_ANDROID))
        val report = ConversionPipeline(p, PipelineOptions(horizonCheckers = checkers)).run().single()

        val pack = File(p.out, "bettersounds-resourcepack.zip")
        val data = File(p.out, "bettersounds-datapack.zip")
        assertTrue(pack.exists(), "no resource pack: " + p.out.list()?.joinToString())
        assertTrue(data.exists(), "no data pack")
        // A mod that only changes vanilla's files needs no content mod, and an empty one would
        // be the bug all over again.
        assertTrue(!File(p.out, "bettersounds-android.hmod").exists())

        val a = entries(pack)
        assertTrue("assets/minecraft/sounds.json" in a, a.toString())
        assertTrue("assets/minecraft/sounds/mob/zombie/say1.ogg" in a)
        assertTrue("assets/minecraft/sounds/mob/zombie/hurt1.ogg" in a)
        // The vanilla sounds.json points at the mod's own namespace, so the pack carries it too.
        assertTrue("assets/bettersounds/sounds/zombie_extra.ogg" in a, a.toString())
        assertTrue("pack.png" in a, "the pack has no icon")
        // The format range this build reads, in the shape it validates.
        // A range, not one number: a pack whose only format is the newest is marked too new by
        // an older launcher and never applies, which is how "the pack does nothing" happens.
        val meta = JsonTree.obj(JsonTree.obj(JsonTree.parse(text(pack, "pack.mcmeta")))!!["pack"])!!
        assertEquals(64L, meta["pack_format"])
        assertEquals(15L, meta["min_format"])
        assertEquals(99L, meta["max_format"])
        assertEquals(listOf(15L, 64L), meta["supported_formats"])
        assertEquals(emptyList(), Validator.validatePack(pack, PackGenerator.PackKind.RESOURCE).filter { it.error })

        val d = entries(data)
        assertTrue("data/minecraft/loot_table/blocks/stone.json" in d, d.toString())
        val dmeta = JsonTree.obj(JsonTree.obj(JsonTree.parse(text(data, "pack.mcmeta")))!!["pack"])!!
        assertEquals(81L, dmeta["pack_format"])
        assertEquals(listOf(15L, 81L), dmeta["supported_formats"])
        assertEquals(140L, dmeta["max_format"])
        // Carried through the 26.3 upgrades, not copied blindly.
        val loot = text(data, "data/minecraft/loot_table/blocks/stone.json")
        assertTrue(loot.contains("minecraft:uniform"), loot)
        assertTrue(!loot.contains("\"functions\"") && !loot.contains("\"conditions\""), loot)
        assertEquals(emptyList(), Validator.validatePack(data, PackGenerator.PackKind.DATA).filter { it.error })

        // The report says the sounds apply, and how to install each file.
        assertTrue(report.features.any { it.name.startsWith("Vanilla sounds replaced") && it.status == FeatureStatus.IMPLEMENTED },
            report.features.joinToString { it.name })
        assertTrue(report.features.any { it.name.startsWith("Vanilla loot tables changed") && it.status == FeatureStatus.IMPLEMENTED })
        assertTrue(report.outputs.any { it.kind.startsWith("resource pack") } && report.outputs.any { it.kind.startsWith("data pack") })
        // The report says in one line what changes, and where the pack is installed.
        assertTrue(report.verdict.startsWith("What changes in game"), report.verdict)
        assertTrue(report.verdict.contains("bettersounds-resourcepack.zip"), report.verdict)
        assertTrue(report.verdict.contains("Packs page, not Mods"), report.verdict)
    }

    /** A mod with its own content keeps its .hmod; only vanilla's files move to the packs. */
    @Test
    fun ownContentStillBecomesAContentMod() {
        val p = project("mixed", Quality.FAST, Fixtures.jar("simple_fabric"), targets = listOf(TargetId.HORIZON_ANDROID))
        ConversionPipeline(p).run()
        assertTrue(File(p.out, "simplemod-android.hmod").exists())
        assertTrue(!File(p.out, "simplemod-resourcepack.zip").exists(), "nothing of vanilla's is touched")
    }

    @Test
    fun unsupportedApisAreReportedNotHidden() {
        val p = project("bad", Quality.ADVANCED, Fixtures.jar("unsupported_apis"), targets = listOf(TargetId.HORIZON_ANDROID))
        val report = ConversionPipeline(p).run().single()
        assertTrue(report.analysis.any { it.contains("Mixins") && it.contains("Reflection") }, report.analysis.toString())
        assertTrue(report.analysis.any { it.contains("1 mixins") })
        // A mod whose behaviour is Java code converts to files that add nothing: say so.
        assertTrue(report.verdict.startsWith("Installing these changes nothing"), report.verdict)
    }
}
