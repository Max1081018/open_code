package dev.rustmodforge.core.pipeline

import dev.rustmodforge.core.ai.AiAssistant
import dev.rustmodforge.core.analysis.MetadataReader
import dev.rustmodforge.core.analysis.ModAnalyzer
import dev.rustmodforge.core.archive.ArchiveLimits
import dev.rustmodforge.core.archive.SafeArchive
import dev.rustmodforge.core.build.BuildBackend
import dev.rustmodforge.core.build.BuildResult
import dev.rustmodforge.core.build.HorizonModChecker
import dev.rustmodforge.core.build.Packager
import dev.rustmodforge.core.build.Validator
import dev.rustmodforge.core.bytecode.Disassembler
import dev.rustmodforge.core.bytecode.JavaLayer
import dev.rustmodforge.core.compat.HorizonCompat
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.geo.GeoParser
import dev.rustmodforge.core.geo.RigAnimation
import dev.rustmodforge.core.geo.RigModel
import dev.rustmodforge.core.model.DependencyKind
import dev.rustmodforge.core.model.EntityInfo
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.model.ResourceKind
import dev.rustmodforge.core.report.ConversionReport
import dev.rustmodforge.core.report.DependencyStatus
import dev.rustmodforge.core.report.FeatureResult
import dev.rustmodforge.core.report.FeatureStatus
import dev.rustmodforge.core.report.OutputFile
import dev.rustmodforge.core.report.StepResult
import dev.rustmodforge.core.report.StepStatus
import dev.rustmodforge.core.report.Verification
import dev.rustmodforge.core.target.ContentModGenerator
import dev.rustmodforge.core.target.FunctionBackend
import dev.rustmodforge.core.target.NativeModGenerator
import dev.rustmodforge.core.target.OutputTree
import dev.rustmodforge.core.target.PackGenerator
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.time.Instant

data class PipelineOptions(
    val buildBackend: BuildBackend? = null,
    val ai: AiAssistant? = null,
    /** The model the reconstruction agent drives, when one is configured. */
    val agentProvider: dev.rustmodforge.core.ai.AiProvider? = null,
    val agentMaxSteps: Int = 24,
    val agentTokenBudget: Int = 120_000,
    /** Live agent steps for the app's progress view. */
    val onAgentStep: (dev.rustmodforge.core.agent.AgentStep) -> Unit = {},
    /** Horizon's own `cargo horizon-mod check`, built from each target's source (they differ). */
    val horizonCheckers: Map<TargetId, HorizonModChecker> = emptyMap(),
    val maxRepairs: Int = 3,
    val limits: ArchiveLimits = ArchiveLimits(),
)

/**
 * Runs a project's conversion, stage by stage, saving each stage so it can resume. One report
 * per imported jar; all imported jars are known to each other for dependency resolution.
 */
class ConversionPipeline(
    private val project: Project,
    private val options: PipelineOptions = PipelineOptions(),
    private val progress: ProgressListener = NoProgress,
    private val cancel: CancellationToken = CancellationToken(),
) {
    companion object { const val ENGINE_VERSION = "0.2.0" }

    private fun p(stage: Stage, f: Float, detail: String) = progress.onProgress(stage.label, f, detail)

    fun run(): List<ConversionReport> {
        val state = project.load()
        val reports = ArrayList<ConversionReport>()
        try {
            val analyses = state.sources.mapIndexed { i, s ->
                cancel.check()
                analyze(File(project.input, s.fileName), s.sha256, i, state.sources.size)
            }
            project.update { it.copy(modIds = analyses.map { a -> MetadataReader.sanitizeId(a.metadata.modId) }) }
            val provided = analyses.flatMap { a -> (a.metadata.declaredModIds + a.metadata.modId + a.nested.flatMap { n -> n.metadata.declaredModIds + n.metadata.modId }) }.toSet()
            project.backupOutputs()
            for ((i, a) in analyses.withIndex()) {
                cancel.check()
                reports += convert(a, File(project.input, state.sources[i].fileName), state, provided)
            }
            File(project.dir, "reports.json").writeText(Project.json.encodeToString(ListSerializer(ConversionReport.serializer()), reports))
            project.update { it.copy(outputs = project.out.listFiles()?.map { f -> f.name }?.sorted() ?: emptyList(), lastError = null) }
            return reports
        } catch (e: CancelledException) {
            project.update { it.copy(lastError = "Cancelled. Resume continues from the last finished stage.") }
            throw e
        } catch (e: Exception) {
            project.update { it.copy(lastError = "${e::class.simpleName}: ${e.message}") }
            throw e
        }
    }

    private fun analysisFile(sha: String) = File(project.analysisDir, "$sha.json")
    private fun layersFile(sha: String) = File(project.analysisDir, "$sha.layers.json")

    private fun analyze(jar: File, sha: String, index: Int, count: Int): ModAnalysis {
        val cached = analysisFile(sha)
        if (cached.exists()) {
            p(Stage.ANALYZE, 1f, "Using the saved analysis of ${jar.name}")
            return Project.json.decodeFromString(ModAnalysis.serializer(), cached.readText())
        }
        project.stage(Stage.ANALYZE, StageState.RUNNING, jar.name)
        val analyzer = ModAnalyzer(options.limits, { _, f, d -> progress.onProgress(Stage.ANALYZE.label, (index + f) / count, d) }, cancel, project.work)
        val a = analyzer.analyze(jar)
        project.analysisDir.mkdirs()
        cached.writeText(Project.json.encodeToString(ModAnalysis.serializer(), a))
        layersFile(sha).writeText(Project.json.encodeToString(ListSerializer(JavaLayer.serializer()), analyzer.lastExtras.javaLayers))
        project.stage(Stage.ANALYZE, StageState.DONE, "${a.classes.size} classes, ${a.resources.size} files, ${a.entities.size} entities")
        return a
    }

    private class Assets(val rig: RigModel?, val animations: List<RigAnimation>, val texture: String?, val glow: String?, val notes: List<String>)

    /** Geometry, animations and textures of one entity, from GeckoLib files or a Java model layer. */
    private fun assetsOf(e: EntityInfo, archive: SafeArchive, layers: List<JavaLayer>): Assets {
        val notes = ArrayList<String>()
        var rig: RigModel? = null
        e.geoModel?.let { path ->
            val models = runCatching { GeoParser.parseGeometry(archive.readText(path), path) }.getOrElse { notes += "$path does not parse: ${it.message}"; emptyList() }
            rig = models.firstOrNull()
            rig?.warnings?.forEach { notes += "$path: $it" }
        }
        if (rig == null) e.javaModelLayer?.let { ref -> layers.firstOrNull { "${it.ownerClass.replace('/', '.')}.${it.method}" == ref }?.let { rig = it.toRig() } }
        val animations = e.animationFile?.let { path -> runCatching { GeoParser.parseAnimations(archive.readText(path)) }.getOrElse { notes += "$path does not parse: ${it.message}"; emptyList() } } ?: emptyList()
        val texture = e.texture
        val glow = texture?.let { t -> listOf("_glowmask.png", "_glow.png", "_e.png", "_emissive.png").map { t.removeSuffix(".png") + it }.firstOrNull { archive.contains(it) } }
        return Assets(rig, animations, texture, glow, notes)
    }

    private fun convert(a: ModAnalysis, jar: File, state: ProjectState, provided: Set<String>): ConversionReport {
        val quality = state.quality
        val id = MetadataReader.sanitizeId(a.metadata.modId)
        val features = ArrayList<FeatureResult>()
        val steps = ArrayList<StepResult>()
        val warnings = ArrayList<String>(a.warnings)
        val outputs = ArrayList<OutputFile>()
        val agentRuns = ArrayList<dev.rustmodforge.core.agent.AgentRun>()
        val layers = layersFile(a.sha256).takeIf { it.exists() }?.let { Project.json.decodeFromString(ListSerializer(JavaLayer.serializer()), it.readText()) } ?: emptyList()

        SafeArchive.open(jar, options.limits).use { archive ->
            // ---- extraction of models and animations ----
            project.stage(Stage.EXTRACT, StageState.RUNNING)
            p(Stage.EXTRACT, 0f, "Reading models and animations")
            val assets = a.entities.associate { it.id to assetsOf(it, archive, layers) }
            assets.values.flatMap { it.notes }.forEach { warnings += it }
            project.stage(Stage.EXTRACT, StageState.DONE, "${assets.values.count { it.rig != null }} models, ${assets.values.sumOf { it.animations.size }} animations")

            // ---- behaviour reconstruction: optional AI pass over custom goals nothing recognised ----
            var entities = a.entities
            if (quality.reconstructsBehaviour) {
                project.stage(Stage.RECONSTRUCT, StageState.RUNNING)
                val ai = options.ai
                if (quality.usesAi && ai != null) {
                    entities = entities.map { e ->
                        val unrecognised = e.goals.filter { g -> g.custom && e.traits.none { t -> t.evidence.any { it.startsWith(g.goal.substringAfterLast('.')) } } }
                        var traits = e.traits
                        for (g in unrecognised) {
                            cancel.check()
                            p(Stage.RECONSTRUCT, 0.5f, "Asking the AI about ${g.goal.substringAfterLast('.')}")
                            traits = traits + ai.classifyGoal(g.goal, Disassembler.disassemble(archive, g.goal.replace('.', '/'), 12_000))
                        }
                        e.copy(traits = traits)
                    }
                }
                project.stage(Stage.RECONSTRUCT, StageState.DONE, "${entities.sumOf { it.traits.size }} behaviours")
            } else {
                project.stage(Stage.RECONSTRUCT, StageState.SKIPPED, "Fast quality: no behaviour reconstruction")
                for (e in entities) if (e.traits.isNotEmpty() || e.geoModel != null) features += FeatureResult("Behaviour", "Behaviour and model of ${e.id}", FeatureStatus.UNSUPPORTED,
                    reason = "Fast quality converts data only; choose Advanced or Maximum fidelity to rebuild ${e.traits.size} behaviours and the model")
            }

            // ---- packs: the mod's changes to vanilla's own files ----
            // A content mod may not hold them, so without this a sound or texture mod would
            // convert to a .hmod that does nothing. Their content is the same for every target.
            val packFiles = LinkedHashMap<PackGenerator.PackKind, File>()
            var packOnly = false
            run {
                val probe = OutputTree(File(project.build, "probe/$id")).also { it.clear() }
                val probeGen = ContentModGenerator(a.copy(entities = entities), archive, probe)
                val packTrees = LinkedHashMap<PackGenerator.PackKind, OutputTree>()
                for (kind in PackGenerator.PackKind.entries) {
                    val packTree = OutputTree(File(project.build, "packs/$id/${kind.name.lowercase()}")).also { it.clear() }
                    val gen = PackGenerator(a, archive, packTree, kind, id, setOf(id) + probeGen.extraNamespaces, packIsTheWholeMod = true)
                    if (gen.isEmpty()) continue
                    p(Stage.CONTENT, 0.15f, "Writing the ${kind.label}")
                    gen.generate()
                    features += gen.features
                    warnings += gen.warnings
                    packTrees[kind] = packTree
                }
                if (packTrees.isNotEmpty()) {
                    probeGen.generate()
                    val inPacks = packTrees.values.flatMap { it.list() }.toSet()
                    val own = probe.list().filter { it.startsWith("assets/") || it.startsWith("data/") }
                    // A content mod earns its place when it holds data of its own (declarations,
                    // recipes, loot, tags, functions) or assets the packs do not already carry.
                    // Otherwise its files are pack content and a .hmod would do nothing.
                    packOnly = own.none { it.startsWith("data/") } && own.all { it in inPacks }
                    for ((kind, packTree) in packTrees) {
                        val name = if (kind == PackGenerator.PackKind.RESOURCE) "resourcepack" else "datapack"
                        val file = Packager.pack(packTree.root, File(project.out, "$id-$name.zip"))
                        packFiles[kind] = file
                        outputs += OutputFile(file.name, file.path, file.length(), Packager.sha256(file), "both", "${kind.label} (.zip)",
                            reached = listOf(Verification.EXTRACTED, Verification.ANALYZED, Verification.GENERATED, Verification.PACKAGED),
                            stoppedBecause = "a pack needs no compiler; loading and runtime testing happen in the launcher")
                    }
                }
                probe.root.deleteRecursively()
            }

            for (target in state.targets) {
                cancel.check()
                val tname = if (target == TargetId.HORIZON_ANDROID) "android" else "desktop"
                // ---- content mod ----
                project.stage(Stage.CONTENT, StageState.RUNNING, tname)
                p(Stage.CONTENT, 0.2f, "Writing the $tname content mod")
                val tree = OutputTree(File(project.build, "$tname/$id/hmod")).also { it.clear() }
                val profile = HorizonCompat.profile(target)
                val content = ContentModGenerator(a.copy(entities = entities), archive, tree, livingEntityTypes = profile.livingTemplates.isNotEmpty())
                content.generate()
                features += content.features.map { it.copy(target = tname) }
                warnings += content.warnings.map { "[$tname] $it" }
                if (target == TargetId.HORIZON_ANDROID && quality.reconstructsBehaviour && entities.isNotEmpty()) {
                    val fb = FunctionBackend(content.id, tree, archive, quality.frameStep)
                    fb.generate(entities.filter { it.id.startsWith("${content.id}:") }.map { e ->
                        val s = assets.getValue(e.id)
                        val hostile = content.isHostile(e)
                        FunctionBackend.EntityPlan(e, s.rig, s.animations, s.texture, s.glow, ContentModGenerator.bodyFor(hostile),
                            HorizonCompat.templateAttributes.getValue(if (hostile) "minecraft:zombie" else "minecraft:wandering_trader"))
                    })
                    features += fb.features.map { it.copy(target = tname) }
                    warnings += fb.warnings.map { "[$tname] $it" }
                }
                project.stage(Stage.CONTENT, StageState.DONE, tname)

                // ---- native Rust mod (desktop) ----
                var nativeTree: OutputTree? = null
                if (target == TargetId.HORIZON_DESKTOP && quality.reconstructsBehaviour && entities.isNotEmpty()) {
                    project.stage(Stage.NATIVE, StageState.RUNNING)
                    p(Stage.NATIVE, 0.5f, "Generating Rust")
                    nativeTree = OutputTree(File(project.build, "desktop/$id/hnmod")).also { it.clear() }
                    // The native mod draws with the rig texture the content mod carries.
                    for (e in entities) assets.getValue(e.id).texture?.let { tree.copyFrom(archive, it, "assets/$id/textures/item/rig/${e.id.substringAfter(':')}.png") }
                    val ng = NativeModGenerator(id, a.metadata.version.ifBlank { "0.0.0" }.replace(Regex("[^0-9A-Za-z.+-]"), "-"), nativeTree)
                    ng.generate(entities.filter { it.id.startsWith("$id:") }.map { e ->
                        val s = assets.getValue(e.id)
                        NativeModGenerator.EntityPlan(e, s.rig, s.animations, s.texture != null)
                    })
                    features += ng.features
                    project.stage(Stage.NATIVE, StageState.DONE)
                } else if (target == TargetId.HORIZON_DESKTOP) project.stage(Stage.NATIVE, StageState.SKIPPED, "nothing needs code")

                // ---- package ----
                project.stage(Stage.PACKAGE, StageState.RUNNING)
                val hmod = if (packOnly) null else Packager.pack(tree.root, File(project.out, "$id-$tname.hmod"))
                if (hmod == null) {
                    features += FeatureResult("Assets and data", "Content mod", FeatureStatus.NOT_APPLICABLE,
                        "none written",
                        "this mod changes only vanilla's own files, so all of it is in the ${packFiles.keys.joinToString { it.label }}; a content mod would hold nothing",
                        target = tname)
                } else {
                    outputs += OutputFile(hmod.name, hmod.path, hmod.length(), Packager.sha256(hmod), tname, "content mod (.hmod)",
                        reached = buildList {
                            add(Verification.EXTRACTED); add(Verification.ANALYZED)
                            if (quality.reconstructsBehaviour && entities.isNotEmpty()) add(Verification.RECONSTRUCTED)
                            add(Verification.GENERATED); add(Verification.PACKAGED)
                        },
                        stoppedBecause = "content needs no compiler; RustMod Forge cannot load a mod into the game, so loading and runtime testing are yours to do")
                }
                val hnmod = nativeTree?.let { Packager.pack(it.root, File(project.out, "$id.hnmod")) }
                hnmod?.let { f -> outputs += OutputFile(f.name, f.path, f.length(), Packager.sha256(f), tname, "native mod source (.hnmod)",
                    reached = listOf(Verification.EXTRACTED, Verification.ANALYZED, Verification.RECONSTRUCTED, Verification.GENERATED, Verification.PACKAGED),
                    stoppedBecause = "compilation is recorded separately below; it needs a build backend") }
                project.stage(Stage.PACKAGE, StageState.DONE)

                // ---- validate ----
                project.stage(Stage.VALIDATE, StageState.RUNNING)
                p(Stage.VALIDATE, 0.7f, "Validating the output")
                val issues = hmod?.let { Validator.validateHmod(it, target) } ?: emptyList()
                val errors = issues.filter { it.error }
                if (hmod != null) steps += StepResult("Manifest, paths and references", if (errors.isEmpty()) StepStatus.PASSED else StepStatus.FAILED,
                    if (errors.isEmpty()) "${issues.size} warnings" else "${errors.size} errors: ${errors.take(3).joinToString("; ")}", issues.joinToString("\n"), tname)
                if (target == state.targets.first()) for ((kind, file) in packFiles) {
                    val pi = Validator.validatePack(file, kind)
                    steps += StepResult("${kind.label.replaceFirstChar(Char::uppercase)} structure and formats",
                        if (pi.none { it.error }) StepStatus.PASSED else StepStatus.FAILED,
                        pi.filter { it.error }.take(3).joinToString("; ").ifEmpty { "${file.name}: pack.mcmeta and paths check out" }, pi.joinToString("\n"), "both")
                }
                hnmod?.let { f ->
                    val ni = Validator.validateHnmod(f)
                    steps += StepResult("Native bundle structure", if (ni.none { it.error }) StepStatus.PASSED else StepStatus.FAILED, ni.joinToString("; ").ifEmpty { "ok" }, target = tname)
                }
                val checker = options.horizonCheckers[target]
                if (checker != null && checker.available() && hmod != null) {
                    val r = checker.check(hmod)
                    steps += StepResult("Horizon's own checker (cargo horizon-mod check)", if (r.success) StepStatus.PASSED else StepStatus.FAILED, r.log.lines().take(4).joinToString(" "), r.log, tname)
                } else {
                    steps += StepResult("Horizon's own checker (cargo horizon-mod check)", StepStatus.NOT_RUN, "not installed on this device; RustMod Forge's validator ran instead", target = tname)
                }
                project.stage(Stage.VALIDATE, if (errors.isEmpty()) StageState.DONE else StageState.FAILED)

                // ---- compile and repair ----
                if (nativeTree != null) compileAndRepair(nativeTree, id, steps, tname)
                else if (target == TargetId.HORIZON_ANDROID) steps += StepResult("Rust compilation", StepStatus.SKIPPED,
                    "Horizon Android loads .hmod only; behaviours are data pack functions, which need no compiler", target = tname)

                // ---- the reconstruction agent ----
                // It runs after the generators, so it reads a real first version and the engine
                // can compare validator and compiler results before and after its work.
                if (quality.usesAi && options.agentProvider != null && entities.isNotEmpty()) {
                    project.stage(Stage.RECONSTRUCT, StageState.RUNNING, "agent")
                    val knowledge = dev.rustmodforge.core.agent.Knowledge(File(project.dir, "knowledge"))
                    val agentCtx = dev.rustmodforge.core.agent.AgentContext(
                        analysis = a.copy(entities = entities), archive = archive, modId = id, target = target, knowledge = knowledge,
                        content = tree, native = nativeTree, backend = options.buildBackend,
                        validator = {
                            val hv = Validator.validateTree(tree.root, target)
                            val nv = nativeTree?.let { Validator.validateNativeTree(it.root, id) } ?: emptyList()
                            hv + nv
                        },
                    )
                    val agent = dev.rustmodforge.core.agent.ReconstructionAgent(
                        options.agentProvider, agentCtx, options.agentMaxSteps, options.agentTokenBudget, cancel,
                        onStep = { st -> options.onAgentStep(st); p(Stage.RECONSTRUCT, 0.6f, "${st.phase}: ${st.detail.take(80)}") },
                    )
                    val task = buildString {
                        append("Reconstruct the behaviour of ")
                        append(entities.joinToString { it.id })
                        append(" for ${profile.name}. ")
                        append(if (nativeTree != null) "This target has a native mod: write Rust goals through write_rust and compile them. "
                        else "This target has no native mod (Horizon Android loads .hmod only): improve the generated data and functions through write_content. ")
                        append("Start from entity_report, look up every API before using it, and finish with what is reconstructed and what Horizon cannot do.")
                    }
                    val run = agent.run(task)
                    agentRuns += run
                    warnings += run.steps.filter { !it.ok }.map { "[agent] ${it.phase}: ${it.detail}" }
                    steps += StepResult("AI reconstruction agent (${options.agentProvider.let { pr -> (pr as? dev.rustmodforge.core.ai.OpenRouterProvider)?.preferred?.firstOrNull() ?: "configured model" }})",
                        when {
                            run.outcome == dev.rustmodforge.core.agent.AgentOutcome.NO_PROVIDER -> StepStatus.NOT_RUN
                            run.verified -> StepStatus.PASSED
                            run.filesWritten.isEmpty() -> if (run.outcome == dev.rustmodforge.core.agent.AgentOutcome.FINISHED) StepStatus.SKIPPED else StepStatus.FAILED
                            // Work was kept and the validators are clean, but nothing compiled it.
                            run.verification.contains("unverified") -> StepStatus.UNVERIFIED
                            else -> StepStatus.FAILED
                        },
                        "${run.steps.size} steps, ${run.filesWritten.size} file(s) kept, ${run.inputTokens + run.outputTokens} tokens — ${run.verification}",
                        run.steps.joinToString("\n") { "${it.phase} · ${it.tool}: ${it.detail}" }, tname)
                    if (run.summary.isNotEmpty()) features += FeatureResult("Behaviour", "AI reconstruction", if (run.verified) FeatureStatus.PARTIAL else FeatureStatus.UNSUPPORTED,
                        run.summary.take(300), if (run.verified) run.verification else "not kept: ${run.verification}", target = tname)
                    if (run.unsupported.isNotEmpty()) features += FeatureResult("Behaviour", "Missing Horizon capability", FeatureStatus.UNSUPPORTED,
                        "", run.unsupported.take(400), target = tname)
                    project.stage(Stage.RECONSTRUCT, if (run.verified || run.filesWritten.isEmpty()) StageState.DONE else StageState.FAILED, run.verification)
                    // The agent may have changed the trees: pack and validate again.
                    if (run.filesWritten.isNotEmpty()) {
                        hmod?.let { Packager.pack(tree.root, it) }
                        nativeTree?.let { nt -> Packager.pack(nt.root, File(project.out, "$id.hnmod")) }
                    }
                }

                steps += StepResult("Runtime test in Horizon", StepStatus.NOT_RUN,
                    "No Horizon game is available to RustMod Forge to load the mod; test it in the launcher. Nothing here claims it works in-game.", target = tname)
            }
            project.stage(Stage.TEST, StageState.SKIPPED, "no runtime available")
        }

        val verdict = verdict(outputs, features)
        val report = ConversionReport(
            modName = a.metadata.name, modId = a.metadata.modId, modVersion = a.metadata.version, sourceFile = a.sourceFile, sha256 = a.sha256,
            loader = a.metadata.loader.name, minecraftVersion = a.metadata.minecraftVersion, quality = quality.label,
            targets = state.targets.map { HorizonCompat.profile(it).name }, createdAt = Instant.now().toString(), engineVersion = ENGINE_VERSION,
            analysis = analysisLines(a), features = features, build = steps, outputs = outputs, dependencies = dependencies(a, provided),
            warnings = warnings.distinct(), aiUsage = options.ai?.let { it.usageSummary() + "\n" + it.log.joinToString("\n") { l -> "- $l" } } ?: "",
            verdict = verdict,
        )
        File(project.out, "$id-report.md").writeText(report.toMarkdown())
        File(project.out, "$id-report.json").writeText(Project.json.encodeToString(ConversionReport.serializer(), report))
        project.stage(Stage.REPORT, StageState.DONE)
        p(Stage.REPORT, 1f, "Done")
        return report
    }

    private fun compileAndRepair(tree: OutputTree, id: String, steps: MutableList<StepResult>, tname: String) {
        val backend = options.buildBackend
        if (backend == null || !backend.available()) {
            project.stage(Stage.COMPILE, StageState.SKIPPED, "no build backend")
            steps += StepResult("Rust compilation", StepStatus.NOT_RUN,
                "No build backend: a phone cannot rebuild Horizon. Set a remote build server in Settings, or build on a PC with horizon-launcher native-build.", target = tname)
            return
        }
        project.stage(Stage.COMPILE, StageState.RUNNING)
        p(Stage.COMPILE, 0.8f, "Compiling with ${backend.name}")
        var result: BuildResult = backend.check(tree.root, id)
        var attempt = 0
        val ai = options.ai
        while (result.ran && !result.success && ai != null && attempt < options.maxRepairs) {
            cancel.check()
            attempt++
            project.stage(Stage.REPAIR, StageState.RUNNING, "attempt $attempt")
            val lib = "mixins/$id/api/src/lib.rs"
            val text = tree.readText(lib)
            val start = text.indexOf(NativeModGenerator.REGION_START); val end = text.indexOf(NativeModGenerator.REGION_END)
            if (start < 0 || end < start) break
            val errors = result.diagnostics.filter { it.level == "error" }.joinToString("\n") { "${it.file}:${it.line}: ${it.message}" }.ifEmpty { result.log.takeLast(4000) }
            val fixed = ai.repairRegion(text.substring(start + NativeModGenerator.REGION_START.length, end), errors, NativeModGenerator.API_NOTES) ?: break
            tree.putText(lib, text.substring(0, start + NativeModGenerator.REGION_START.length) + "\n" + fixed + "\n" + text.substring(end))
            result = backend.check(tree.root, id)
            steps += StepResult("Error repair attempt $attempt", if (result.success) StepStatus.PASSED else StepStatus.FAILED, "${result.diagnostics.count { it.level == "error" }} errors after the fix", target = tname)
        }
        if (attempt > 0) project.stage(Stage.REPAIR, if (result.success) StageState.DONE else StageState.FAILED)
        steps += StepResult("Rust compilation (${backend.name})",
            if (!result.ran) StepStatus.NOT_RUN else if (result.success) StepStatus.PASSED else StepStatus.FAILED,
            if (!result.ran) result.log.take(300) else "${result.diagnostics.count { it.level == "error" }} errors, ${result.diagnostics.count { it.level == "warning" }} warnings",
            result.log, tname)
        project.stage(Stage.COMPILE, if (result.success) StageState.DONE else StageState.FAILED)
        if (result.success && attempt > 0) {
            // Re-pack the repaired source.
            Packager.pack(tree.root, File(project.out, "$id.hnmod"))
        }
    }

    /**
     * Whether the files change anything once installed, and which one does it. A mod whose
     * behaviour is Java code converts to files that add nothing, and saying so plainly is worth
     * more than a list of green rows.
     */
    private fun verdict(outputs: List<OutputFile>, features: List<FeatureResult>): String {
        val pack = outputs.firstOrNull { it.kind.startsWith("resource pack") }
        val data = outputs.firstOrNull { it.kind.startsWith("data pack") }
        val gameplay = features.any { f ->
            f.status != FeatureStatus.UNSUPPORTED && f.status != FeatureStatus.NOT_APPLICABLE &&
                (f.category == "Entities" || f.category == "Behaviour" || f.category == "Blocks" || f.category == "Items")
        }
        val changes = ArrayList<String>()
        if (pack != null) changes += "${pack.name} changes the game's own sounds, textures or text"
        if (data != null) changes += "${data.name} changes the game's own recipes, loot or advancements"
        if (gameplay) changes += "the .hmod adds this mod's own content to your worlds"
        return when {
            changes.isEmpty() -> "Installing these changes nothing in game on their own: what this mod does lives in its Java code, which Horizon cannot run. See the unsupported rows below for what that is."
            else -> "What changes in game: " + changes.joinToString("; ") + "." +
                (if (pack != null) " The resource pack is imported on the Packs page, not Mods." else "")
        }
    }

    private fun analysisLines(a: ModAnalysis): List<String> = buildList {
        add("Jar inspected: ${a.resources.size} files, ${a.classes.size} classes (bytecode parsed, never executed).")
        add("Loader ${a.metadata.loader}, Minecraft ${a.metadata.minecraftVersion.ifEmpty { "not declared" }}, ${a.metadata.dependencies.size} declared dependencies.")
        add("${a.registrations.size} registrations: ${a.registrations.groupBy { it.kind }.entries.joinToString { "${it.value.size} ${it.key.name.lowercase()}" }}.")
        add("${a.entities.size} entities; ${a.entities.sumOf { it.goals.size }} AI goals and ${a.entities.sumOf { it.traits.size }} behaviours recognised.")
        add("${a.resourcesOf(ResourceKind.TEXTURE).size} textures, ${a.geoModels.size} GeckoLib models, ${a.animations.size} animation files, ${a.sounds.size} sound events.")
        if (a.mixins.isNotEmpty()) add("${a.mixins.size} mixins (not translatable: they patch Java classes).")
        if (a.unsupportedApis.isNotEmpty()) add("APIs without a Horizon equivalent: ${a.unsupportedApis.joinToString { it.api }}.")
        if (a.nested.isNotEmpty()) add("${a.nested.size} nested jars analysed: ${a.nested.joinToString { it.metadata.modId }}.")
    }

    private fun dependencies(a: ModAnalysis, provided: Set<String>): List<DependencyStatus> {
        val platform = setOf("minecraft", "forge", "neoforge", "fabricloader", "fabric", "fabric-api", "fabric_api", "quilt_loader", "quilted_fabric_api", "java")
        val reconstructed = mapOf("geckolib" to "GeckoLib models and animations are converted by RustMod Forge (display rig on Android, mob_submit on desktop)",
            "geckolib3" to "GeckoLib models and animations are converted by RustMod Forge")
        val viewers = setOf("jei", "rei", "emi", "roughlyenoughitems")
        val config = setOf("cloth-config", "cloth_config", "cloth-config2", "modmenu", "configured", "yet_another_config_lib_v3", "yacl")
        return a.metadata.dependencies.map { d ->
            val (status, note) = when {
                d.kind == DependencyKind.INCOMPATIBLE -> "incompatible" to "the original declares it incompatible; nothing to convert"
                d.kind == DependencyKind.EMBEDDED -> "embedded" to "bundled inside the jar; analysed as a nested jar"
                d.id in platform -> "platform" to "provided by Horizon itself (it is the game and the loader)"
                d.id in reconstructed -> "reconstructed" to reconstructed.getValue(d.id)
                d.id in provided -> "imported" to "converted alongside from the files you imported"
                d.id in viewers -> "replaced" to "recipe viewers: Horizon has its own Recipes mod"
                d.id in config -> "not needed" to "config screens are not reproduced; generated mods have no Java config"
                d.kind == DependencyKind.OPTIONAL -> "optional, missing" to "optional integration left out"
                else -> "missing" to "not imported: whatever ${d.id} provides to this mod (APIs, items, rendering) is not available. Import its jar too if you are allowed to use it."
            }
            DependencyStatus(d.id, d.kind.name, d.versionRange, status, note)
        }
    }
}
