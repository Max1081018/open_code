package dev.rustmodforge.core.report

import kotlinx.serialization.Serializable

/** How completely a feature of the original mod exists in the output. Never a percentage. */
@Serializable
enum class FeatureStatus { IMPLEMENTED, PARTIAL, UNSUPPORTED, NOT_APPLICABLE }

/** Whether a build/validation step ran and passed. NOT_RUN is said plainly, never hidden. */
@Serializable
enum class StepStatus { PASSED, FAILED, SKIPPED, NOT_RUN }

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

@Serializable
data class OutputFile(val name: String, val path: String, val size: Long, val sha256: String, val target: String, val kind: String)

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
            outputs.forEach { appendLine("- `${it.name}` — ${it.kind} for ${it.target}, ${it.size} bytes, SHA-256 `${it.sha256}`") }
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
