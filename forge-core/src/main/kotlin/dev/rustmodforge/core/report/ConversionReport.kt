package dev.rustmodforge.core.report

import kotlinx.serialization.Serializable

/** How completely a feature of the original mod exists in the output. Never a percentage. */
@Serializable
enum class FeatureStatus { IMPLEMENTED, PARTIAL, UNSUPPORTED, NOT_APPLICABLE }

/**
 * Whether a build/validation step ran and passed. NOT_RUN is said plainly, never hidden, and
 * UNVERIFIED is for work that was done but that nothing could confirm — generated Rust with no
 * compiler to check it is neither a pass nor a failure.
 */
@Serializable
enum class StepStatus { PASSED, FAILED, SKIPPED, NOT_RUN, UNVERIFIED }

@Serializable
data class FeatureResult(
    val category: String,
    val name: String,
    val status: FeatureStatus,
    /** How it was reconstructed (`content entity_type from minecraft:zombie`, `functions`, `Rust Goal`). */
    val route: String = "",
    /** Why it is partial or unsupported, in plain words. */
    val reason: String = "",
    val evidence: List<String> = emptyList(),
    val target: String = "",
)

@Serializable
data class StepResult(val name: String, val status: StepStatus, val detail: String = "", val log: String = "", val target: String = "")

/**
 * How far one artifact actually got. Each step is set only when the operation behind it ran and
 * succeeded, so the list is evidence rather than a promise: PACKAGED means a file exists,
 * COMPILED means a compiler exited zero, LOADED and RUNTIME_TESTED need the real client.
 */
@Serializable
enum class Verification { EXTRACTED, ANALYZED, RECONSTRUCTED, GENERATED, COMPILED, PACKAGED, LOADED, RUNTIME_TESTED }

@Serializable
data class OutputFile(
    val name: String, val path: String, val size: Long, val sha256: String, val target: String, val kind: String,
    /** The steps reached for this file, in order. */
    val reached: List<Verification> = emptyList(),
    /** Why the next step was not reached. */
    val stoppedBecause: String = "",
)

@Serializable
data class DependencyStatus(val id: String, val kind: String, val range: String, val status: String, val note: String)

@Serializable
data class ConversionReport(
    val modName: String,
    val modId: String,
    val modVersion: String,
    val sourceFile: String,
    val sha256: String,
    val loader: String,
    val minecraftVersion: String,
    val quality: String,
    val targets: List<String>,
    val createdAt: String,
    val engineVersion: String,
    val analysis: List<String>,
    val features: List<FeatureResult>,
    val build: List<StepResult>,
    val outputs: List<OutputFile>,
    val dependencies: List<DependencyStatus>,
    val warnings: List<String>,
    val aiUsage: String = "",
    /** One plain sentence: what, if anything, these files change once installed. */
    val verdict: String = "",
) {
    fun toMarkdown(): String = buildString {
        appendLine("# Conversion report: $modName")
        appendLine()
        appendLine("| | |")
        appendLine("|---|---|")
        appendLine("| Original mod | $modName `$modId` $modVersion |")
        appendLine("| File | `$sourceFile` (SHA-256 `${sha256.take(16)}…`) |")
        appendLine("| Loader / Minecraft | $loader / ${minecraftVersion.ifEmpty { "not declared" }} |")
        appendLine("| Quality | $quality |")
        appendLine("| Targets | ${targets.joinToString()} |")
        appendLine("| Created | $createdAt (RustMod Forge $engineVersion) |")
        appendLine()
        if (verdict.isNotEmpty()) { appendLine("**$verdict**"); appendLine() }
        appendLine("## Analysis")
        analysis.forEach { appendLine("- $it") }
        appendLine()
        appendLine("## Reconstruction")
        val counts = FeatureStatus.entries.associateWith { s -> features.count { it.status == s } }
        appendLine("${counts[FeatureStatus.IMPLEMENTED]} implemented, ${counts[FeatureStatus.PARTIAL]} partial, ${counts[FeatureStatus.UNSUPPORTED]} unsupported.")
        appendLine()
        for ((category, list) in features.groupBy { it.category }) {
            appendLine("### $category")
            appendLine()
            appendLine("| Feature | Status | How | Why not complete |")
            appendLine("|---|---|---|---|")
            for (f in list) {
                val t = if (f.target.isNotEmpty()) " (${f.target})" else ""
                appendLine("| ${esc(f.name)}$t | ${f.status.name.lowercase()} | ${esc(f.route)} | ${esc(f.reason)} |")
            }
            appendLine()
        }
        if (dependencies.isNotEmpty()) {
            appendLine("## Dependencies")
            appendLine()
            appendLine("| Dependency | Kind | Version | Result |")
            appendLine("|---|---|---|---|")
            dependencies.forEach { appendLine("| ${it.id} | ${it.kind.lowercase()} | ${esc(it.range)} | ${esc(it.status)}: ${esc(it.note)} |") }
            appendLine()
        }
        appendLine("## Build and validation")
        appendLine()
        appendLine("| Step | Result | Detail |")
        appendLine("|---|---|---|")
        build.forEach { appendLine("| ${esc(it.name)}${if (it.target.isNotEmpty()) " (${it.target})" else ""} | ${it.status.name.lowercase().replace('_', ' ')} | ${esc(it.detail)} |") }
        appendLine()
        if (outputs.isNotEmpty()) {
            appendLine("## Output files")
            outputs.forEach { o ->
                appendLine("- `${o.name}` — ${o.kind} for ${o.target}, ${o.size} bytes, SHA-256 `${o.sha256}`")
                val reached = o.reached.joinToString(" → ") { it.name.lowercase().replace('_', ' ') }
                val missing = Verification.entries.filter { it !in o.reached }.joinToString { it.name.lowercase().replace('_', ' ') }
                appendLine("  - reached: ${reached.ifEmpty { "nothing" }}")
                if (missing.isNotEmpty()) appendLine("  - not reached: $missing${o.stoppedBecause.let { if (it.isEmpty()) "" else " ($it)" }}")
            }
            appendLine()
        }
        if (warnings.isNotEmpty()) {
            appendLine("## Warnings")
            warnings.forEach { appendLine("- $it") }
            appendLine()
        }
        if (aiUsage.isNotEmpty()) { appendLine("## AI assistance"); appendLine(aiUsage); appendLine() }
        appendLine("_Runtime behaviour is only claimed where a step above says a runtime test passed. A successful build is not a gameplay test._")
    }

    private fun esc(s: String) = s.replace("|", "\\|").replace("\n", " ")
}
