package dev.rustmodforge.core.pipeline

import dev.rustmodforge.core.compat.TargetId
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** What each quality level actually does differently (not a cosmetic setting). */
@Serializable
enum class Quality(val label: String, val description: String) {
    FAST("Fast", "Assets, data and declarations as a content-only mod; dependency analysis; validation. No behaviour or model reconstruction."),
    ADVANCED("Advanced", "Fast, plus bytecode behaviour reconstruction, the display-entity model rig and function AI (Android), the native Rust mod (desktop), and compilation where a build backend is set."),
    MAXIMUM("Maximum fidelity", "Advanced, plus animations sampled every tick instead of every 2, AI-assisted analysis of custom Java goals the rules do not recognise, compiler-error repair, and the stricter checks of Horizon's own tool when available.");

    val reconstructsBehaviour get() = this != FAST
    val frameStep get() = if (this == MAXIMUM) 1 else 2
    val usesAi get() = this == MAXIMUM
}

@Serializable
enum class Stage(val label: String) {
    ANALYZE("Analysis"), EXTRACT("Asset extraction"), RECONSTRUCT("Behaviour reconstruction"), CONTENT("Content generation"),
    NATIVE("Rust code generation"), PACKAGE("Packaging"), VALIDATE("Validation"), COMPILE("Compilation"), REPAIR("Error repair"),
    TEST("Testing"), REPORT("Report");
}

@Serializable
enum class StageState { PENDING, RUNNING, DONE, FAILED, SKIPPED }

@Serializable
data class StageRecord(val stage: Stage, val state: StageState = StageState.PENDING, val detail: String = "", val finishedAt: Long = 0)

@Serializable
data class ProjectSource(val fileName: String, val sha256: String, val size: Long)

@Serializable
data class ProjectState(
    val id: String,
    val name: String,
    val createdAt: Long,
    val updatedAt: Long,
    val quality: Quality,
    val targets: List<TargetId>,
    val sources: List<ProjectSource>,
    val stages: List<StageRecord> = Stage.entries.map { StageRecord(it) },
    val modIds: List<String> = emptyList(),
    val outputs: List<String> = emptyList(),
    val lastError: String? = null,
)

/**
 * A conversion project on disk. The imported jars are copied into `input/` (the originals are
 * never touched), each stage's results are saved so an interrupted conversion resumes where it
 * stopped, and previous outputs are kept in `backups/` before they are replaced.
 */
class Project(val dir: File) {
    val input = File(dir, "input")
    val work = File(dir, "work")
    val analysisDir = File(dir, "analysis")
    val build = File(dir, "build")
    val out = File(dir, "out")
    val backups = File(dir, "backups")
    val cache = File(dir, "cache")
    private val stateFile = File(dir, "project.json")

    val exists get() = stateFile.exists()

    fun load(): ProjectState = json.decodeFromString(ProjectState.serializer(), stateFile.readText())

    @Synchronized
    fun save(state: ProjectState) {
        dir.mkdirs()
        val tmp = File(dir, "project.json.tmp")
        tmp.writeText(json.encodeToString(ProjectState.serializer(), state.copy(updatedAt = System.currentTimeMillis())))
        if (stateFile.exists()) stateFile.delete()
        tmp.renameTo(stateFile)
    }

    fun update(f: (ProjectState) -> ProjectState) = save(f(load()))

    fun stage(stage: Stage, state: StageState, detail: String = "") = update { s ->
        s.copy(stages = s.stages.map { if (it.stage == stage) it.copy(state = state, detail = detail, finishedAt = if (state == StageState.DONE) System.currentTimeMillis() else it.finishedAt) else it })
    }

    /** Moves the current outputs to `backups/<time>/` so a rebuild never loses the previous result. */
    fun backupOutputs() {
        val files = out.listFiles()?.filter { it.isFile } ?: return
        if (files.isEmpty()) return
        val dest = File(backups, System.currentTimeMillis().toString()).apply { mkdirs() }
        files.forEach { it.copyTo(File(dest, it.name), overwrite = true) }
        backups.listFiles()?.sortedByDescending { it.name }?.drop(5)?.forEach { it.deleteRecursively() }
    }

    companion object {
        val json = Json { prettyPrint = true; ignoreUnknownKeys = true; encodeDefaults = true }

        fun create(root: File, name: String, quality: Quality, targets: List<TargetId>, jars: List<File>): Project {
            val id = "p" + System.currentTimeMillis().toString(36) + (0..999).random()
            val p = Project(File(root, id))
            p.input.mkdirs()
            val sources = jars.map { j ->
                val copy = File(p.input, j.name.replace(Regex("[^A-Za-z0-9._+-]"), "_"))
                j.copyTo(copy, overwrite = true)
                ProjectSource(copy.name, dev.rustmodforge.core.build.Packager.sha256(copy), copy.length())
            }
            val now = System.currentTimeMillis()
            p.save(ProjectState(id, name, now, now, quality, targets, sources))
            return p
        }

        fun list(root: File): List<Project> = root.listFiles()?.filter { File(it, "project.json").exists() }?.map { Project(it) }
            ?.sortedByDescending { runCatching { it.load().updatedAt }.getOrDefault(0) } ?: emptyList()
    }
}
