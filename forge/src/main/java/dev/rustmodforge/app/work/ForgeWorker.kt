package dev.rustmodforge.app.work

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import dev.rustmodforge.app.ForgeApp
import dev.rustmodforge.app.R
import dev.rustmodforge.core.ai.AiAssistant
import dev.rustmodforge.core.analysis.ModAnalyzer
import dev.rustmodforge.core.build.RemoteBuildBackend
import dev.rustmodforge.core.model.ModAnalysis
import dev.rustmodforge.core.pipeline.CancellationToken
import dev.rustmodforge.core.pipeline.CancelledException
import dev.rustmodforge.core.pipeline.ConversionPipeline
import dev.rustmodforge.core.pipeline.PipelineOptions
import dev.rustmodforge.core.pipeline.Project
import dev.rustmodforge.core.pipeline.Stage
import dev.rustmodforge.core.pipeline.StageState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import kotlin.coroutines.cancellation.CancellationException

/**
 * Runs a project's analysis or full conversion off the main thread, as a foreground job so a
 * long conversion survives leaving the app. Progress is published for the UI; cancelling the
 * work cancels the pipeline between steps, and enqueueing again resumes (finished analyses are
 * reused from the project folder).
 */
class ForgeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private val token = CancellationToken()

    override suspend fun getForegroundInfo(): ForegroundInfo = foreground("Preparing", 0f)

    private fun foreground(text: String, fraction: Float): ForegroundInfo {
        val nm = applicationContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, applicationContext.getString(R.string.channel_name), NotificationManager.IMPORTANCE_LOW))
        }
        val n = NotificationCompat.Builder(applicationContext, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("RustMod Forge")
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, (fraction * 100).toInt(), false)
            .build()
        return if (Build.VERSION.SDK_INT >= 29) ForegroundInfo(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else ForegroundInfo(NOTIFICATION_ID, n)
    }

    override suspend fun doWork(): Result {
        val app = applicationContext as ForgeApp
        val projectId = inputData.getString(KEY_PROJECT) ?: return Result.failure()
        val mode = inputData.getString(KEY_MODE) ?: MODE_CONVERT
        val project = Project(File(app.projectsRoot, projectId))
        if (!project.exists) return Result.failure(workDataOf(KEY_ERROR to "project not found"))
        runCatching { setForeground(foreground("Starting", 0f)) }
        var last = 0L
        val listener = { stage: String, fraction: Float, detail: String ->
            val now = System.currentTimeMillis()
            if (now - last > 250 || fraction >= 1f) {
                last = now
                setProgressAsync(workDataOf(KEY_STAGE to stage, KEY_FRACTION to fraction, KEY_DETAIL to detail))
                runCatching { setForegroundAsync(foreground("$stage: $detail", fraction)) }
            }
        }
        return withContext(Dispatchers.IO) {
            try {
                if (mode == MODE_ANALYZE) analyzeOnly(project, listener) else {
                    val settings = app.settings.state.value
                    val ai = settings.aiConfig()?.let { AiAssistant(it, project.cache.resolve("ai")) }
                    val backend = settings.buildServerUrl.takeIf { it.isNotBlank() }?.let { RemoteBuildBackend(it, settings.buildServerToken) }
                    val options = PipelineOptions(buildBackend = backend, ai = ai, maxRepairs = settings.maxRepairs)
                    ConversionPipeline(project, options, dev.rustmodforge.core.pipeline.ProgressListener { s, f, d -> listener(s, f, d) }, token).run()
                }
                Result.success()
            } catch (e: CancelledException) {
                Result.failure(workDataOf(KEY_ERROR to "Cancelled"))
            } catch (e: CancellationException) {
                token.cancel()
                throw e
            } catch (e: OutOfMemoryError) {
                project.update { it.copy(lastError = "Out of memory: this mod is too large for the memory Android gives the app") }
                Result.failure(workDataOf(KEY_ERROR to "Out of memory"))
            } catch (e: Exception) {
                if (app.settings.state.value.debugLogging) {
                    val sw = StringWriter(); e.printStackTrace(PrintWriter(sw))
                    File(project.dir, "error.log").writeText(sw.toString())
                }
                Result.failure(workDataOf(KEY_ERROR to (e.message ?: e::class.java.simpleName)))
            }
        }
    }

    /** Only the analysis, saved where the pipeline will reuse it. */
    private fun analyzeOnly(project: Project, listener: (String, Float, String) -> Unit) {
        val state = project.load()
        for (s in state.sources) {
            token.check()
            val cached = File(project.analysisDir, "${s.sha256}.json")
            if (cached.exists()) continue
            project.stage(Stage.ANALYZE, StageState.RUNNING, s.fileName)
            val analyzer = ModAnalyzer(progress = { st, f, d -> listener(st, f, d) }, cancel = token, scratch = project.work)
            val a: ModAnalysis = analyzer.analyze(File(project.input, s.fileName))
            project.analysisDir.mkdirs()
            cached.writeText(Project.json.encodeToString(ModAnalysis.serializer(), a))
            File(project.analysisDir, "${s.sha256}.layers.json").writeText(
                Project.json.encodeToString(kotlinx.serialization.builtins.ListSerializer(dev.rustmodforge.core.bytecode.JavaLayer.serializer()), analyzer.lastExtras.javaLayers))
        }
        project.stage(Stage.ANALYZE, StageState.DONE, "${state.sources.size} file(s) analysed")
    }

    override suspend fun onStopped() { /* coroutine cancellation reaches doWork; the token stops the pipeline */ }

    companion object {
        const val CHANNEL = "conversions"
        const val NOTIFICATION_ID = 4107
        const val KEY_PROJECT = "project"
        const val KEY_MODE = "mode"
        const val KEY_STAGE = "stage"
        const val KEY_FRACTION = "fraction"
        const val KEY_DETAIL = "detail"
        const val KEY_ERROR = "error"
        const val MODE_ANALYZE = "analyze"
        const val MODE_CONVERT = "convert"

        fun workName(projectId: String) = "forge-$projectId"

        fun enqueue(context: Context, projectId: String, mode: String) {
            val req = OneTimeWorkRequestBuilder<ForgeWorker>()
                .setInputData(Data.Builder().putString(KEY_PROJECT, projectId).putString(KEY_MODE, mode).build())
                .addTag("forge")
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(workName(projectId), ExistingWorkPolicy.REPLACE, req)
        }

        fun cancel(context: Context, projectId: String) {
            WorkManager.getInstance(context).cancelUniqueWork(workName(projectId))
        }
    }
}
