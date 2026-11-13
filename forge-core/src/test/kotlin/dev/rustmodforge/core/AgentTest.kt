package dev.rustmodforge.core

import dev.rustmodforge.core.agent.AgentContext
import dev.rustmodforge.core.agent.AgentOutcome
import dev.rustmodforge.core.agent.Knowledge
import dev.rustmodforge.core.agent.ReconstructionAgent
import dev.rustmodforge.core.ai.AiProvider
import dev.rustmodforge.core.ai.AiReply
import dev.rustmodforge.core.ai.OpenRouterProvider
import dev.rustmodforge.core.analysis.ModAnalyzer
import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.build.BuildResult
import dev.rustmodforge.core.build.BuildBackend
import dev.rustmodforge.core.build.Diagnostic
import dev.rustmodforge.core.build.Issue
import dev.rustmodforge.core.compat.HorizonApiIndex
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.target.OutputTree
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** A model that replies with a fixed script, so the loop is tested without a network. */
private class ScriptedProvider(private val replies: List<String>) : AiProvider {
    var calls = 0; private set
    val prompts = ArrayList<String>()
    override fun complete(system: String, user: String, maxTokens: Int): AiReply {
        prompts += system + "\n--\n" + user
        val text = replies.getOrElse(calls) { """{"tool":"finish","args":{"summary":"done"}}""" }
        calls++
        return AiReply(text, 100, 50, false)
    }
}

class AgentTest {
    private val fog by lazy { Fixtures.jar("fog_horror") }

    private fun context(tmp: File, native: Boolean, validator: () -> List<Issue> = { emptyList() }, backend: BuildBackend? = null): Pair<AgentContext, SafeArchive> {
        val a = ModAnalyzer(scratch = File(tmp, "scratch")).analyze(fog)
        val archive = SafeArchive.open(fog)
        val ctx = AgentContext(
            analysis = a, archive = archive, modId = "fogwatcher", target = if (native) TargetId.HORIZON_DESKTOP else TargetId.HORIZON_ANDROID,
            knowledge = Knowledge(File(tmp, "knowledge")),
            content = OutputTree(File(tmp, "hmod")),
            native = if (native) OutputTree(File(tmp, "hnmod")) else null,
            backend = backend, validator = validator,
        )
        return ctx to archive
    }

    @Test
    fun theAgentUsesRealToolsAgainstTheRealMod() {
        val tmp = Fixtures.tempDir("agent")
        val (ctx, archive) = context(tmp, native = true)
        archive.use {
            val script = listOf(
                """{"thought":"find the entity","tool":"entity_report","args":{"id":"fogwatcher:the_watcher"}}""",
                """{"thought":"what goals exist","tool":"search_horizon_api","args":{"query":"register goals melee attack","kinds":"goal,hook"}}""",
                """{"thought":"read the stalk goal","tool":"disassemble","args":{"name":"com.example.fogwatcher.goal.StalkPlayerGoal","limit":2000}}""",
                """{"thought":"note it","tool":"remember","args":{"key":"watcher.stalk","text":"keeps 24 blocks, paths when further"}}""",
                """{"thought":"write it","tool":"write_rust","args":{"path":"mixins/fogwatcher/api/src/stalk.rs","content":"// generated\npub struct Stalk;\n"}}""",
                """{"thought":"check","tool":"validate","args":{}}""",
                """{"tool":"finish","args":{"summary":"rebuilt the stalk goal","unsupported":"renderer fog has no Horizon equivalent"}}""",
            )
            val provider = ScriptedProvider(script)
            val run = ReconstructionAgent(provider, ctx, maxSteps = 10).run("Rebuild the watcher's AI")

            assertEquals(AgentOutcome.FINISHED, run.outcome)
            assertEquals("rebuilt the stalk goal", run.summary)
            assertTrue(run.unsupported.contains("renderer fog"))
            // Every tool really ran against the real mod and the real index.
            val byTool = run.steps.associateBy { it.tool }
            assertTrue(byTool.containsKey("entity_report") && byTool.containsKey("disassemble"))
            assertEquals(7, provider.calls)
            // The entity report carried the attributes local analysis found.
            val entityStep = provider.prompts[1]
            assertTrue(entityStep.contains("minecraft:max_health=80.0"), entityStep.takeLast(1200))
            // The API search answered from Horizon's own source, with a real constructor.
            val apiStep = provider.prompts[2]
            assertTrue(apiStep.contains("MeleeAttack::new(speed: f64, follow_unseen: bool)"), apiStep.takeLast(1500))
            // The disassembly is real bytecode of the fixture's goal class.
            assertTrue(provider.prompts[3].contains("getNearestPlayer"), "no bytecode in the disassembly step")
            // The write landed in the native tree and is reported.
            assertTrue(ctx.native!!.exists("mixins/fogwatcher/api/src/stalk.rs"))
            assertEquals(listOf("hnmod/mixins/fogwatcher/api/src/stalk.rs"), run.filesWritten)
            // Knowledge persisted for later runs.
            assertEquals("keeps 24 blocks, paths when further", Knowledge(File(tmp, "knowledge")).note("watcher.stalk"))
            assertTrue(run.inputTokens > 0 && run.outputTokens > 0)
        }
    }

    @Test
    fun writesOutsideTheModAreRefused() {
        val tmp = Fixtures.tempDir("agent-escape")
        val (ctx, archive) = context(tmp, native = true)
        archive.use {
            val script = listOf(
                """{"tool":"write_rust","args":{"path":"../../../etc/passwd","content":"x"}}""",
                """{"tool":"write_rust","args":{"path":"mixins/fogwatcher/api/src/../../../../evil.rs","content":"x"}}""",
                """{"tool":"write_content","args":{"path":"data/minecraft/loot_table/blocks/stone.json","content":"{}"}}""",
                """{"tool":"write_content","args":{"path":"data/fogwatcher/x.json","content":"not json"}}""",
                """{"tool":"finish","args":{"summary":"stopped"}}""",
            )
            val run = ReconstructionAgent(ScriptedProvider(script), ctx, maxSteps = 8).run("try to escape")
            assertEquals(emptyList(), run.filesWritten)
            assertTrue(run.steps.filter { it.tool.startsWith("write_") }.all { !it.ok }, run.steps.joinToString { it.detail })
            assertTrue(!File(tmp, "evil.rs").exists())
        }
    }

    @Test
    fun workThatBreaksValidationIsRolledBack() {
        val tmp = Fixtures.tempDir("agent-rollback")
        // The validator reports an error only once the agent's file exists.
        var ctxRef: AgentContext? = null
        val validator = {
            val c = ctxRef
            if (c != null && c.native!!.exists("mixins/fogwatcher/api/src/bad.rs")) listOf(Issue(true, "bad.rs", "broken"))
            else emptyList()
        }
        val (ctx, archive) = context(tmp, native = true, validator = validator)
        ctxRef = ctx
        archive.use {
            val tree = ctx.native!!
            tree.putText("mixins/fogwatcher/api/src/lib.rs", "// the good version\n")
            val script = listOf(
                """{"tool":"write_rust","args":{"path":"mixins/fogwatcher/api/src/bad.rs","content":"// breaks validation\n"}}""",
                """{"tool":"finish","args":{"summary":"wrote it"}}""",
            )
            val run = ReconstructionAgent(ScriptedProvider(script), ctx, maxSteps = 5).run("write a bad file")
            assertTrue(!run.verified)
            assertTrue(run.verification.startsWith("rolled back"), run.verification)
            assertTrue(!tree.exists("mixins/fogwatcher/api/src/bad.rs"), "the bad file survived")
            assertEquals("// the good version\n", tree.readText("mixins/fogwatcher/api/src/lib.rs"))
            assertEquals(emptyList(), run.filesWritten)
        }
    }

    @Test
    fun rustThatDoesNotCompileIsRolledBack() {
        val tmp = Fixtures.tempDir("agent-compile")
        val backend = object : BuildBackend {
            override val name = "fake cargo"
            override fun available() = true
            override fun check(nativeTree: File, modId: String) = BuildResult(
                ran = true, success = false, log = "error[E0425]: cannot find value `nope`",
                diagnostics = listOf(Diagnostic("error", "api/src/lib.rs", 3, "cannot find value `nope`")), backend = name,
            )
        }
        val (ctx, archive) = context(tmp, native = true, backend = backend)
        archive.use {
            val tree = ctx.native!!
            tree.putText("mixins/fogwatcher/api/src/lib.rs", "// working\n")
            val script = listOf(
                """{"tool":"write_rust","args":{"path":"mixins/fogwatcher/api/src/lib.rs","content":"fn x() { nope(); }\n"}}""",
                """{"tool":"compile","args":{}}""",
                """{"tool":"finish","args":{"summary":"I think it is fine"}}""",
            )
            val run = ReconstructionAgent(ScriptedProvider(script), ctx, maxSteps = 6).run("write Rust")
            // The model claimed success; the compiler decided otherwise.
            assertTrue(!run.verified)
            assertTrue(run.verification.contains("did not compile"), run.verification)
            assertEquals("// working\n", tree.readText("mixins/fogwatcher/api/src/lib.rs"))
            // The compiler's real errors reached the model.
            assertTrue(run.steps.any { it.tool == "compile" && it.detail.contains("cannot find value") }, run.steps.joinToString { it.detail })
        }
    }

    @Test
    fun withoutAProviderNothingRunsAndNothingIsClaimed() {
        val tmp = Fixtures.tempDir("agent-none")
        val (ctx, archive) = context(tmp, native = false)
        archive.use {
            val run = ReconstructionAgent(null, ctx).run("anything")
            assertEquals(AgentOutcome.NO_PROVIDER, run.outcome)
            assertTrue(!run.verified)
            assertTrue(run.unsupported.contains("did not run"))
        }
    }

    @Test
    fun theApiIndexComesFromHorizonsOwnSource() {
        val d = HorizonApiIndex.data
        assertEquals(40, d.source.revision.length)
        assertEquals(415, d.source.native_hooks_api)
        assertTrue(d.hooks.size > 400 && d.helpers.size > 150 && d.goals.size >= 15)
        // Real contracts, not names: the hook carries its signature and the goal its constructor.
        val submit = HorizonApiIndex.hook("mob_submit")!!
        assertTrue(submit.signature.contains("NativeMobRender"), submit.signature)
        assertEquals("MobSubmitEvent", submit.event_type)
        assertTrue(HorizonApiIndex.goal("MeleeAttack")!!.constructors.single().contains("speed: f64"))
        // Mob's navigation methods are indexed, so generated goals can call them.
        val mob = d.structs.single { it.name == "Mob" }
        assertTrue(mob.methods.any { it.startsWith("nav_move_to(") }, mob.methods.take(20).toString())
        assertTrue(mob.fields.any { it.startsWith("position:") })
        // An API that does not exist is reported as absent rather than guessed at.
        assertTrue(HorizonApiIndex.search("teleport_entity_to_dimension_fancy").isEmpty())
        assertTrue(HorizonApiIndex.search("register goals").isNotEmpty())
    }

    @Test
    fun openRouterOnlyUsesFreeModelsAndPausesInstead() {
        val catalog = """
            {"data":[
              {"id":"recursive/flint-v1.0:free","name":"Flint","context_length":131072,"pricing":{"prompt":"0","completion":"0"}},
              {"id":"paid/strong","name":"Paid","context_length":200000,"pricing":{"prompt":"0.000003","completion":"0.000015"}},
              {"id":"other/small:free","name":"Small","context_length":32768,"pricing":{"prompt":"0","completion":"0"}}
            ]}
        """.trimIndent()
        val calls = ArrayList<String>()
        val transport = object : OpenRouterProvider.Transport {
            override fun get(url: String, headers: Map<String, String>, connectMs: Int, readMs: Int) =
                OpenRouterProvider.Response(200, catalog)
            override fun post(url: String, headers: Map<String, String>, body: String, connectMs: Int, readMs: Int): OpenRouterProvider.Response {
                val model = Regex("\"model\":\"([^\"]+)\"").find(body)!!.groupValues[1]
                calls += model
                return when (model) {
                    // The preferred model is out of quota, the next free one answers.
                    "recursive/flint-v1.0:free" -> OpenRouterProvider.Response(429, "{\"error\":{\"message\":\"rate limit\"}}", mapOf("retry-after" to "30"))
                    "other/small:free" -> OpenRouterProvider.Response(200, """{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":7,"completion_tokens":3}}""")
                    else -> OpenRouterProvider.Response(200, """{"choices":[{"message":{"content":"paid!"}}]}""")
                }
            }
        }
        val p = OpenRouterProvider("key", listOf("recursive/flint-v1.0:free", "missing/model:free"), allowPaid = false, transport = transport)
        // A model the catalog lacks is reported, not called.
        val availability = p.availability().toMap()
        assertEquals("available, free, 131k context", availability["recursive/flint-v1.0:free"])
        assertEquals("not in OpenRouter's catalog right now", availability["missing/model:free"])
        // The rate-limited preference falls back to another free model; the paid one is never called.
        val reply = p.complete("s", "u", 100)
        assertEquals("ok", reply.text)
        assertEquals(listOf("recursive/flint-v1.0:free", "other/small:free"), calls)
        assertTrue(calls.none { it == "paid/strong" })
        assertTrue(p.history.any { it.status == "rate-limited" && it.model == "recursive/flint-v1.0:free" })
    }

    @Test
    fun whenEveryFreeModelIsExhaustedTheRunPausesWithProgressKept() {
        val transport = object : OpenRouterProvider.Transport {
            override fun get(url: String, headers: Map<String, String>, connectMs: Int, readMs: Int) =
                OpenRouterProvider.Response(200, """{"data":[{"id":"a:free","pricing":{"prompt":"0","completion":"0"}}]}""")
            override fun post(url: String, headers: Map<String, String>, body: String, connectMs: Int, readMs: Int) =
                OpenRouterProvider.Response(429, "{}", mapOf("retry-after" to "45"))
        }
        val p = OpenRouterProvider("key", listOf("a:free"), transport = transport)
        val tmp = Fixtures.tempDir("agent-paused")
        val (ctx, archive) = context(tmp, native = true)
        archive.use {
            val tree = ctx.native!!
            tree.putText("mixins/fogwatcher/api/src/lib.rs", "// kept\n")
            val run = ReconstructionAgent(p, ctx, maxSteps = 4).run("do work")
            assertEquals(AgentOutcome.PAUSED, run.outcome)
            // Progress is preserved, and no paid model was substituted.
            assertEquals("// kept\n", tree.readText("mixins/fogwatcher/api/src/lib.rs"))
            assertTrue(run.steps.last().detail.contains("rate-limited") || run.steps.last().detail.contains("free model"), run.steps.joinToString { it.detail })
        }
    }
}
