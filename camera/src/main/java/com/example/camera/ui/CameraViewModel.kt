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

    var scene by mutableStateOf<Scene?>(null)
        private set

    var maskReady by mutableStateOf(false)
        private set

    var maskLoading by mutableStateOf(false)
        private set

    private var base: Bitmap? = null
    private var mask: SubjectMask? = null
    private var renderJob: Job? = null
    private var maskJob: Job? = null
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
            openPlayer(file)
            return
        }
        backTo = from
        viewModelScope.launch {
            setBusy(true, "Opening photo")
            val bitmap = withContext(Dispatchers.IO) { store.decode(file, PREVIEW_MAX) }
            setBusy(false)
            if (bitmap == null) {
                toast = "Could not open that photo"
                return@launch
            }
            renderJob?.cancel()
            maskJob?.cancel()
            base = bitmap
            mask = null
            maskReady = false
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
        }
    }

    fun openPlayer(file: File) {
        playerFile = file
        screen = Screen.Player
    }

    fun closeEditor() {
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
            openPlayer(file)
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
        params = params.copy(
            exposure = 0f,
            contrast = 0f,
            saturation = 0f,
            warmth = 0f,
            tint = 0f,
            highlights = 0f,
            shadows = 0f,
            clarity = 0f,
            sharpen = 0f,
            denoise = 0f,
            grain = 0f,
            vignette = 0f,
            fade = 0f,
            night = false,
            hdr = false,
            beauty = false,
            portrait = false,
            aiVision = false,
            detail = false
        )
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
        val source = base ?: return
        viewModelScope.launch {
            setBusy(true, "Reading the scene")
            val result = withContext(Dispatchers.Default) {
                val small = ImagePipeline.render(source, EditParams(), STATS_MAX)
                val pixels = IntArray(small.width * small.height)
                small.getPixels(pixels, 0, small.width, 0, 0, small.width, small.height)
                val stats = AutoEnhance.stats(pixels)
                val labels = SceneAnalyzer.labels(small)
                small.recycle()
                val detected = AutoEnhance.classify(stats, labels)
                detected to AutoEnhance.suggest(stats, detected)
            }
            setBusy(false)
            scene = result.first
            params = result.second
            scheduleRender()
            toast = "AI enhanced · ${result.first.label}"
        }
    }

    /**
     * Runs ML Kit subject segmentation on a small copy so the portrait bokeh uses a
     * real mask instead of a radial guess.
     */
    fun ensureMask() {
        if (mask != null || maskLoading) return
        val source = base ?: return
        maskJob?.cancel()
        maskJob = viewModelScope.launch {
            maskLoading = true
            val found = withContext(Dispatchers.Default) {
                val small = ImagePipeline.render(source, EditParams(), MASK_MAX)
                val result = SceneAnalyzer.subjectMask(small)
                small.recycle()
                result
            }
            maskLoading = false
            mask = found
            maskReady = found != null
            if (found == null) {
                toast = "No clear subject found · using edge blur"
            }
            scheduleRender()
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
        viewModelScope.launch {
            val thumbs = withContext(Dispatchers.Default) {
                val small = ImagePipeline.render(source, EditParams(), THUMB_MAX)
                val result = LinkedHashMap<FilterId, ImageBitmap>()
                for (id in FilterId.values()) {
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
            filterThumbs = thumbs
        }
    }

    // ----------------------------------------------------------------- save

    fun saveEdit(share: Boolean, export: Boolean = false) {
        val sourceFile = editingFile ?: return
        val current = params
        val currentMask = mask
        viewModelScope.launch {
            setBusy(true, "Rendering full resolution")
            val saved = withContext(Dispatchers.IO) {
                renderFull(sourceFile, current, currentMask)
            }
            setBusy(false)
            if (saved == null) {
                toast = "Could not save the photo"
                return@launch
            }
            refreshGallery()
            if (export) {
                val ok = withContext(Dispatchers.IO) {
                    store.exportToSystemGallery(getApplication(), saved)
                }
                toast = if (ok) "Saved to phone gallery" else "Could not save to gallery"
            }
            if (share) {
                shareRequest = saved
            } else if (!export) {
                toast = "Saved to library"
                screen = Screen.Gallery
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
            val ok = store.write(rendered, target, quality = 98)
            rendered.recycle()
            full.recycle()
            if (ok) target else null
        } catch (oom: OutOfMemoryError) {
            try {
                val smaller = store.decode(sourceFile, EXPORT_FALLBACK_MAX) ?: return null
                val rendered = ImagePipeline.render(smaller, current, EXPORT_FALLBACK_MAX)
                val target = store.newEditFile()
                val ok = store.write(rendered, target, quality = 95)
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
        viewModelScope.launch {
            setBusy(true, "Saving to gallery")
            val ok = withContext(Dispatchers.IO) {
                store.exportToSystemGallery(getApplication(), file)
            }
            setBusy(false)
            toast = if (ok) "Saved to phone gallery" else "Could not save to gallery"
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
                editingFile = null
                base = null
                mask = null
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

    fun exportAll(files: List<File>) {
        if (files.isEmpty()) return
        viewModelScope.launch {
            setBusy(true, "Saving ${files.size} items")
            var ok = 0
            withContext(Dispatchers.IO) {
                files.forEach { if (store.exportToSystemGallery(getApplication(), it)) ok++ }
            }
            setBusy(false)
            toast = "Saved $ok of ${files.size} to gallery"
        }
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

    private fun setBusy(value: Boolean, label: String = "Working") {
        busy = value
        busyLabel = label
    }
}
