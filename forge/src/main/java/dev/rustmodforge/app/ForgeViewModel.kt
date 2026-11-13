package dev.rustmodforge.app

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.WorkInfo
import androidx.work.WorkManager
import dev.rustmodforge.app.data.Exports
import dev.rustmodforge.app.data.Imports
import dev.rustmodforge.app.work.ForgeWorker
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.pipeline.Project
import dev.rustmodforge.core.pipeline.ProjectState
import dev.rustmodforge.core.pipeline.Quality
import dev.rustmodforge.core.report.ConversionReport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import java.io.File

/** A project as the lists show it. */
data class ProjectSummary(val state: ProjectState, val dir: File)

/** Everything one project screen needs, read from the project folder. */
data class ProjectDetail(
    val state: ProjectState,
    val analyses: List<ModAnalysis>,
    val reports: List<ConversionReport>,
    val outputs: List<File>,
)

data class WorkStatus(val running: Boolean, val finished: Boolean, val failed: Boolean, val stage: String, val fraction: Float, val detail: String, val error: String?)

class ForgeViewModel(app: Application) : AndroidViewModel(app) {
    private val forge = app as ForgeApp
    val settings = forge.settings

    private val _projects = MutableStateFlow<List<ProjectSummary>>(emptyList())
    val projects: StateFlow<List<ProjectSummary>> = _projects.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    init { refresh() }

    fun say(text: String?) { _message.value = text }

    fun refresh() = viewModelScope.launch {
        _projects.value = withContext(Dispatchers.IO) {
            Project.list(forge.projectsRoot).mapNotNull { p -> runCatching { ProjectSummary(p.load(), p.dir) }.getOrNull() }
        }
    }

    fun project(id: String) = Project(File(forge.projectsRoot, id))

    suspend fun detail(id: String): ProjectDetail? = withContext(Dispatchers.IO) {
        val p = project(id)
        if (!p.exists) return@withContext null
        val state = p.load()
        val analyses = state.sources.mapNotNull { s ->
            File(p.analysisDir, "${s.sha256}.json").takeIf { it.exists() }?.let { f -> runCatching { Project.json.decodeFromString(ModAnalysis.serializer(), f.readText()) }.getOrNull() }
        }
        val reports = File(p.dir, "reports.json").takeIf { it.exists() }?.let { f ->
            runCatching { Project.json.decodeFromString(ListSerializer(ConversionReport.serializer()), f.readText()) }.getOrNull()
        } ?: emptyList()
        ProjectDetail(state, analyses, reports, p.out.listFiles()?.filter { it.isFile }?.sortedBy { it.name } ?: emptyList())
    }

    /** Copies the picked files in, creates a project and starts its analysis. Calls [then] with its id. */
    fun import(uris: List<Uri>, then: (String) -> Unit) = viewModelScope.launch {
        if (uris.isEmpty()) return@launch
        _busy.value = true
        try {
            val id = withContext(Dispatchers.IO) {
                val ctx = getApplication<Application>()
                val tmp = File(ctx.cacheDir, "import-" + System.currentTimeMillis()).apply { mkdirs() }
                try {
                    val files = uris.map { Imports.copyIn(ctx, it, tmp) }
                    val s = settings.state.value
                    val name = if (files.size == 1) files[0].nameWithoutExtension else "${files.size} mods"
                    Project.create(forge.projectsRoot, name, s.defaultQuality, s.targets, files).dir.name
                } finally {
                    tmp.deleteRecursively()
                }
            }
            ForgeWorker.enqueue(getApplication(), id, ForgeWorker.MODE_ANALYZE)
            refresh()
            then(id)
        } catch (e: Exception) {
            say("Import failed: ${e.message}")
        } finally {
            _busy.value = false
        }
    }

    fun convert(id: String, quality: Quality, targets: List<TargetId>) = viewModelScope.launch {
        withContext(Dispatchers.IO) {
            project(id).update { s ->
                s.copy(quality = quality, targets = targets.ifEmpty { listOf(TargetId.HORIZON_ANDROID) }, lastError = null,
                    stages = s.stages.map { if (it.stage == dev.rustmodforge.core.pipeline.Stage.ANALYZE) it else dev.rustmodforge.core.pipeline.StageRecord(it.stage) })
            }
        }
        ForgeWorker.enqueue(getApplication(), id, ForgeWorker.MODE_CONVERT)
        refresh()
    }

    fun reanalyze(id: String) = ForgeWorker.enqueue(getApplication(), id, ForgeWorker.MODE_ANALYZE)

    fun cancel(id: String) = ForgeWorker.cancel(getApplication(), id)

    fun delete(id: String) = viewModelScope.launch {
        ForgeWorker.cancel(getApplication(), id)
        withContext(Dispatchers.IO) { project(id).dir.deleteRecursively() }
        refresh()
    }

    fun work(id: String): Flow<WorkStatus?> = WorkManager.getInstance(getApplication()).getWorkInfosForUniqueWorkFlow(ForgeWorker.workName(id)).map { list ->
        val w = list.lastOrNull() ?: return@map null
        val p = w.progress
        WorkStatus(
            running = w.state == WorkInfo.State.RUNNING || w.state == WorkInfo.State.ENQUEUED,
            finished = w.state == WorkInfo.State.SUCCEEDED,
            failed = w.state == WorkInfo.State.FAILED || w.state == WorkInfo.State.CANCELLED,
            stage = p.getString(ForgeWorker.KEY_STAGE) ?: "",
            fraction = p.getFloat(ForgeWorker.KEY_FRACTION, 0f),
            detail = p.getString(ForgeWorker.KEY_DETAIL) ?: "",
            error = w.outputData.getString(ForgeWorker.KEY_ERROR) ?: if (w.state == WorkInfo.State.CANCELLED) "Cancelled" else null,
        )
    }

    fun exportToUri(file: File, uri: Uri) = viewModelScope.launch {
        val r = withContext(Dispatchers.IO) { runCatching { Exports.copyTo(getApplication(), file, uri) } }
        say(r.fold({ "Saved ${file.name}" }, { "Export failed: ${it.message}" }))
    }

    fun exportToHorizon(file: File) = viewModelScope.launch {
        val tree = settings.state.value.horizonModsTree
        if (tree.isBlank()) { say("Choose the Horizon Mods folder first (Settings › Target launcher)"); return@launch }
        val r = withContext(Dispatchers.IO) { runCatching { Exports.copyToTree(getApplication(), file, tree) } }
        say(r.fold({ "Saved ${file.name} into $it. Open Horizon Android › Mods › Installed and switch it on." }, { "Export failed: ${it.message}" }))
    }

    fun exportToHorizonPacks(file: File) = viewModelScope.launch {
        val tree = settings.state.value.horizonPacksTree
        if (tree.isBlank()) { say("Choose the Horizon Resource Packs folder first (Settings › Target launcher)"); return@launch }
        val r = withContext(Dispatchers.IO) { runCatching { Exports.copyToTree(getApplication(), file, tree) } }
        say(r.fold({ "Saved ${file.name} into $it. Open Horizon Android › Packs › Installed and switch it on." }, { "Export failed: ${it.message}" }))
    }

    fun storageBytes(): Long = forge.projectsRoot.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    fun clearCaches() = viewModelScope.launch {
        withContext(Dispatchers.IO) {
            Project.list(forge.projectsRoot).forEach { p -> p.cache.deleteRecursively(); p.work.deleteRecursively(); p.build.deleteRecursively() }
            getApplication<Application>().cacheDir.listFiles()?.forEach { it.deleteRecursively() }
        }
        say("Caches cleared. Projects, analyses and outputs are kept.")
    }
}
