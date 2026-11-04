package com.example.camera.ui

import android.app.Application
import android.graphics.Bitmap
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.camera.data.AutoEnhance
import com.example.camera.data.EditParams
import com.example.camera.data.FilterId
import com.example.camera.data.ImagePipeline
import com.example.camera.data.PhotoStore
import com.example.camera.data.Scene
import com.example.camera.data.SceneAnalyzer
import com.example.camera.data.SettingsStore
import com.example.camera.data.SubjectMask
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

enum class Screen { Camera, Gallery, Editor, Player }

private const val PREVIEW_MAX = 1440
private const val EXPORT_MAX = 4096
private const val EXPORT_FALLBACK_MAX = 2600
private const val THUMB_MAX = 128
private const val MASK_MAX = 480
private const val STATS_MAX = 360

/** Cached once; FilterId.values() allocates a fresh array on every call. */
private val FILTER_IDS = FilterId.values()

class CameraViewModel(app: Application) : AndroidViewModel(app) {

    val store: PhotoStore = PhotoStore.get(app)
    val settings: SettingsStore = SettingsStore(app)

    var screen by mutableStateOf(Screen.Camera)
        private set

    var gallery by mutableStateOf<List<File>>(emptyList())
        private set

    var params by mutableStateOf(EditParams())
        private set

    var preview by mutableStateOf<ImageBitmap?>(null)
        private set

    var originalPreview by mutableStateOf<ImageBitmap?>(null)
        private set

    var filterThumbs by mutableStateOf<Map<FilterId, ImageBitmap>>(emptyMap())
        private set

    var editingFile by mutableStateOf<File?>(null)
        private set

    var playerFile by mutableStateOf<File?>(null)
        private set

    var busy by mutableStateOf(false)
        private set

    var busyLabel by mutableStateOf("Working")
        private set

    var toast by mutableStateOf<String?>(null)
        private set

    var shareRequest by mutableStateOf<File?>(null)
        private set

    /**
     * Files waiting on the pre-Android-10 WRITE_EXTERNAL_STORAGE grant. The UI
     * shows the system dialog and calls [onStoragePermissionResult] with the answer.
     */
    var pendingExport by mutableStateOf<List<File>?>(null)
        private set

    var scene by mutableStateOf<Scene?>(null)
        private set

    var maskReady by mutableStateOf(false)
        private set

    var maskLoading by mutableStateOf(false)
        private set

    /** Set once per photo when segmentation failed, so sliders stop retrying. */
    var maskFailed by mutableStateOf(false)
        private set

    private var base: Bitmap? = null
    private var mask: SubjectMask? = null
    private var renderJob: Job? = null
    private var maskJob: Job? = null
    private var enhanceJob: Job? = null
    private var openJob: Job? = null
    private var openGeneration = 0
    private var busyCount = 0
    private var backTo = Screen.Camera

    init {
        refreshGallery()
    }

    // ------------------------------------------------------------ navigation

    fun openGallery() {
        refreshGallery()
        screen = Screen.Gallery
    }

    fun openCamera() {
        screen = Screen.Camera
    }

    fun openEditor(file: File, from: Screen = screen, portraitMode: Boolean = false) {
        if (PhotoStore.isVideo(file)) {
            openPlayer(file, from)
            return
        }
        openJob?.cancel()
        backTo = from
        openGeneration++
        val gen = openGeneration
        openJob = viewModelScope.launch {
            beginBusy("Opening photo")
            try {
                val bitmap = withContext(Dispatchers.IO) { store.decode(file, PREVIEW_MAX) }
                // A newer openEditor superseded this one while we decoded.
                if (gen != openGeneration) {
                    bitmap?.recycle()
                    return@launch
                }
                if (bitmap == null) {
                    toast = "Could not open that photo"
                    return@launch
                }
                renderJob?.cancel()
                maskJob?.cancel()
                base = bitmap
                mask = null
                maskReady = false
                maskFailed = false
                editingFile = file
                params = EditParams(portrait = portraitMode)
                scene = null
                originalPreview = bitmap.asImageBitmap()
                preview = originalPreview
                screen = Screen.Editor
                buildFilterThumbs(bitmap)
                if (portraitMode) {
                    ensureMask()
                } else if (settings.autoAi) {
                    autoEnhance()
                }
            } finally {
                endBusy()
            }
        }
    }

    fun openPlayer(file: File, from: Screen = screen) {
        backTo = from
        playerFile = file
        screen = Screen.Player
    }

    fun closeEditor() {
        renderJob?.cancel()
        maskJob?.cancel()
        enhanceJob?.cancel()
        maskLoading = false
        screen = backTo
    }

    fun closePlayer() {
        playerFile = null
        screen = if (backTo == Screen.Gallery) Screen.Gallery else Screen.Camera
    }

    // -------------------------------------------------------------- capture

    fun newCaptureFile(): File = store.newCaptureFile()

    fun newVideoFile(): File = store.newVideoFile()

    fun onCaptured(file: File, portraitMode: Boolean = false) {
        refreshGallery()
        openEditor(file, from = Screen.Camera, portraitMode = portraitMode)
    }

    fun onVideoSaved(file: File) {
        refreshGallery()
        if (file.exists() && file.length() > 0) {
            openPlayer(file, from = Screen.Camera)
        } else {
            toast = "Recording failed"
        }
    }

    fun refreshGallery() {
        viewModelScope.launch {
            gallery = withContext(Dispatchers.IO) { store.all() }
        }
    }

    // --------------------------------------------------------------- editing

    fun update(block: (EditParams) -> EditParams) {
        params = block(params)
        if (params.portrait && mask == null && !maskReady) ensureMask()
        scheduleRender()
    }

    fun resetEdits() {
        params = EditParams()
        scheduleRender()
        toast = "Edits reset"
    }

    fun rotate() {
        update { it.copy(rotation = (it.rotation + 90) % 360) }
    }

    fun flipHorizontal() {
        update { it.copy(flipH = !it.flipH) }
    }

    fun setCropAspect(aspect: Float?) {
        update { it.copy(cropAspect = aspect) }
    }

    fun autoEnhance() {
        if (enhanceJob?.isActive == true) return
        val source = base ?: return
        enhanceJob = viewModelScope.launch {
            beginBusy("Reading the scene")
            val result = try {
                withContext(Dispatchers.Default) {
                    val small = ImagePipeline.render(source, EditParams(), STATS_MAX)
                    val pixels = IntArray(small.width * small.height)
                    small.getPixels(pixels, 0, small.width, 0, 0, small.width, small.height)
                    val stats = AutoEnhance.stats(pixels)
                    val labels = SceneAnalyzer.labels(small)
                    small.recycle()
                    val detected = AutoEnhance.classify(stats, labels)
                    detected to AutoEnhance.suggest(stats, detected)
                }
            } catch (t: Throwable) {
                if (t !is CancellationException) toast = "AI enhance failed"
                return@launch
            } finally {
                endBusy()
            }
            // Only apply if the photo is still the one we analysed.
            if (base !== source) return@launch
            scene = result.first
            params = result.second
            scheduleRender()
            toast = "AI enhanced · ${result.first.label}"
        }
    }

    /**
     * Runs ML Kit subject segmentation on a small copy so the portrait bokeh uses a
     * real mask instead of a radial guess. Failure is remembered per photo so
     * slider drags never re-trigger segmentation; [force] retries explicitly.
     */
    fun ensureMask(force: Boolean = false) {
        if (mask != null || maskLoading) return
        if (maskFailed && !force) return
        val source = base ?: return
        maskJob?.cancel()
        maskLoading = true
        maskFailed = false
        maskJob = viewModelScope.launch {
            val self = coroutineContext[Job]
            try {
                val found = withContext(Dispatchers.Default) {
                    val small = ImagePipeline.render(source, EditParams(), MASK_MAX)
                    val result = SceneAnalyzer.subjectMask(small)
                    small.recycle()
                    result
                }
                // A newer photo may have replaced this one while we ran.
                if (base !== source) return@launch
                mask = found
                maskReady = found != null
                if (found == null) {
                    maskFailed = true
                    toast = "No clear subject found · using edge blur"
                }
                scheduleRender()
            } catch (ce: CancellationException) {
                throw ce
            } catch (t: Throwable) {
                if (base === source) maskFailed = true
            } finally {
                if (maskJob == self) maskLoading = false
            }
        }
    }

    private fun scheduleRender() {
        val source = base ?: return
        val current = params
        val currentMask = mask
        renderJob?.cancel()
        renderJob = viewModelScope.launch {
            delay(70)
            val rendered = withContext(Dispatchers.Default) {
                ImagePipeline.render(
                    source,
                    current,
                    PREVIEW_MAX,
                    if (current.portrait) currentMask?.confidence else null,
                    currentMask?.width ?: 0,
                    currentMask?.height ?: 0
                )
            }
            preview = rendered.asImageBitmap()
        }
    }

    private fun buildFilterThumbs(source: Bitmap) {
        val owner = editingFile
        viewModelScope.launch {
            val thumbs = withContext(Dispatchers.Default) {
                val small = ImagePipeline.render(source, EditParams(), THUMB_MAX)
                val result = LinkedHashMap<FilterId, ImageBitmap>()
                for (id in FILTER_IDS) {
                    val rendered = if (id == FilterId.ORIGINAL) {
                        small
                    } else {
                        ImagePipeline.render(small, EditParams(filter = id), THUMB_MAX)
                    }
                    result[id] = rendered.asImageBitmap()
                }
                // `small` doubles as the ORIGINAL thumbnail, so it must stay alive.
                result
            }
            // Ignore a slow build that finished after another photo was opened.
            if (editingFile == owner) filterThumbs = thumbs
        }
    }

    // ----------------------------------------------------------------- save

    fun saveEdit(share: Boolean, export: Boolean = false) {
        if (busy) return
        val sourceFile = editingFile ?: return
        val current = params
        viewModelScope.launch {
            beginBusy("Rendering full resolution")
            val saved = try {
                // Portrait renders need the subject mask. If segmentation is
                // still running, wait for it instead of baking in the fallback.
                if (current.portrait && mask == null) {
                    val pending = maskJob
                    if (pending != null && pending.isActive) pending.join()
                }
                val currentMask = if (current.portrait) mask else null
                withContext(Dispatchers.IO) {
                    renderFull(sourceFile, current, currentMask)
                }
            } finally {
                endBusy()
            }
            if (saved == null) {
                toast = "Could not save the photo"
                return@launch
            }
            refreshGallery()
            if (export) {
                requestExport(listOf(saved))
            }
            if (share) {
                shareRequest = saved
            } else if (!export) {
                toast = "Saved to library"
                // The user may have backed out while the render ran; don't yank
                // them into the library from another screen.
                if (screen == Screen.Editor) screen = Screen.Gallery
            }
        }
    }

    private fun renderFull(
        sourceFile: File,
        current: EditParams,
        currentMask: SubjectMask?
    ): File? {
        return try {
            val full = store.decode(sourceFile, EXPORT_MAX) ?: return null
            val rendered = ImagePipeline.render(
                full,
                current,
                EXPORT_MAX,
                if (current.portrait) currentMask?.confidence else null,
                currentMask?.width ?: 0,
                currentMask?.height ?: 0
            )
            val target = store.newEditFile()
            val ok = store.write(rendered, target, quality = 100)
            rendered.recycle()
            full.recycle()
            if (ok) target else null
        } catch (oom: OutOfMemoryError) {
            try {
                val smaller = store.decode(sourceFile, EXPORT_FALLBACK_MAX) ?: return null
                val rendered = ImagePipeline.render(smaller, current, EXPORT_FALLBACK_MAX)
                val target = store.newEditFile()
                val ok = store.write(rendered, target, quality = 97)
                rendered.recycle()
                smaller.recycle()
                if (ok) target else null
            } catch (t: Throwable) {
                null
            }
        } catch (t: Throwable) {
            null
        }
    }

    fun export(file: File) {
        if (busy) return
        requestExport(listOf(file))
    }

    /** Asks for the legacy storage grant first on Android 9 and older. */
    private fun requestExport(files: List<File>) {
        if (files.isEmpty()) return
        if (PhotoStore.needsLegacyStoragePermission(getApplication())) {
            pendingExport = files
            return
        }
        runExport(files)
    }

    private fun runExport(files: List<File>) {
        viewModelScope.launch {
            beginBusy(if (files.size == 1) "Saving to gallery" else "Saving ${files.size} items")
            var ok = 0
            try {
                withContext(Dispatchers.IO) {
                    files.forEach { if (store.exportToSystemGallery(getApplication(), it)) ok++ }
                }
            } finally {
                endBusy()
            }
            toast = when {
                files.size == 1 ->
                    if (ok == 1) "Saved to phone gallery" else "Could not save to gallery"
                else -> "Saved $ok of ${files.size} to gallery"
            }
        }
    }

    /** Called by the UI after the WRITE_EXTERNAL_STORAGE dialog closes. */
    fun onStoragePermissionResult(granted: Boolean) {
        val files = pendingExport
        pendingExport = null
        if (files.isNullOrEmpty()) return
        if (granted) {
            runExport(files)
        } else {
            toast = "Storage permission is needed to save to the gallery"
        }
    }

    fun share(file: File) {
        shareRequest = file
    }

    fun deleteCurrent() {
        val file = editingFile ?: return
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { store.delete(file) }
            if (editingFile == file) {
                renderJob?.cancel()
                maskJob?.cancel()
                enhanceJob?.cancel()
                editingFile = null
                base = null
                mask = null
                maskReady = false
                maskFailed = false
                maskLoading = false
                preview = null
                originalPreview = null
                filterThumbs = emptyMap()
            }
            refreshGallery()
            toast = if (ok) "Deleted" else "Could not delete"
            screen = if (backTo == Screen.Gallery) Screen.Gallery else Screen.Camera
        }
    }

    fun delete(file: File) {
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { store.delete(file) }
            refreshGallery()
            toast = if (ok) "Deleted" else "Could not delete"
        }
    }

    /** One delete pass for a whole selection, so the library refreshes once. */
    fun deleteAll(files: List<File>) {
        if (files.isEmpty()) return
        viewModelScope.launch {
            beginBusy("Deleting ${files.size} items")
            var ok = 0
            try {
                withContext(Dispatchers.IO) {
                    files.forEach { if (store.delete(it)) ok++ }
                }
            } finally {
                endBusy()
            }
            refreshGallery()
            toast = if (ok == files.size) {
                "Deleted ${files.size}"
            } else {
                "Deleted $ok of ${files.size}"
            }
        }
    }

    fun exportAll(files: List<File>) {
        if (files.isEmpty() || busy) return
        requestExport(files)
    }

    // ---------------------------------------------------------------- misc

    fun showToast(message: String) {
        toast = message
    }

    fun clearToast() {
        toast = null
    }

    fun clearShare() {
        shareRequest = null
    }

    private fun beginBusy(label: String = "Working") {
        if (busyCount == 0) busyLabel = label
        busyCount++
        busy = true
    }

    private fun endBusy() {
        busyCount = (busyCount - 1).coerceAtLeast(0)
        if (busyCount == 0) busy = false
    }
}
