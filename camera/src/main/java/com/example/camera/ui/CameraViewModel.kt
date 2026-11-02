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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

enum class Screen { Camera, Gallery, Editor }

private const val PREVIEW_MAX = 1440
private const val EXPORT_MAX = 4096

class CameraViewModel(app: Application) : AndroidViewModel(app) {

    val store: PhotoStore = PhotoStore.get(app)

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

    var busy by mutableStateOf(false)
        private set

    var toast by mutableStateOf<String?>(null)
        private set

    var shareRequest by mutableStateOf<File?>(null)
        private set

    private var base: Bitmap? = null
    private var renderJob: Job? = null
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

    fun openEditor(file: File, from: Screen = screen) {
        backTo = from
        viewModelScope.launch {
            busy = true
            val bitmap = withContext(Dispatchers.IO) { store.decode(file, PREVIEW_MAX) }
            busy = false
            if (bitmap == null) {
                toast = "Could not open that photo"
                return@launch
            }
            renderJob?.cancel()
            base = bitmap
            editingFile = file
            params = EditParams()
            originalPreview = bitmap.asImageBitmap()
            preview = originalPreview
            screen = Screen.Editor
            buildFilterThumbs(bitmap)
        }
    }

    fun closeEditor() {
        screen = backTo
    }

    // -------------------------------------------------------------- capture

    fun newCaptureFile(): File = store.newCaptureFile()

    fun onCaptured(file: File) {
        refreshGallery()
        openEditor(file, from = Screen.Camera)
    }

    fun refreshGallery() {
        viewModelScope.launch {
            gallery = withContext(Dispatchers.IO) { store.list() }
        }
    }

    // --------------------------------------------------------------- editing

    fun update(block: (EditParams) -> EditParams) {
        params = block(params)
        scheduleRender()
    }

    fun resetEdits() {
        params = EditParams()
        scheduleRender()
    }

    fun autoEnhance() {
        val source = base ?: return
        viewModelScope.launch {
            busy = true
            val suggestion = withContext(Dispatchers.Default) {
                val small = ImagePipeline.render(source, EditParams(), 360)
                val pixels = IntArray(small.width * small.height)
                small.getPixels(pixels, 0, small.width, 0, 0, small.width, small.height)
                val stats = AutoEnhance.stats(pixels)
                small.recycle()
                AutoEnhance.suggest(stats)
            }
            busy = false
            params = suggestion
            scheduleRender()
            toast = "Auto enhanced"
        }
    }

    private fun scheduleRender() {
        val source = base ?: return
        val current = params
        renderJob?.cancel()
        renderJob = viewModelScope.launch {
            delay(80)
            val rendered = withContext(Dispatchers.Default) {
                ImagePipeline.render(source, current, PREVIEW_MAX)
            }
            preview = rendered.asImageBitmap()
        }
    }

    private fun buildFilterThumbs(source: Bitmap) {
        viewModelScope.launch {
            val thumbs = withContext(Dispatchers.Default) {
                val small = ImagePipeline.render(source, EditParams(), 128)
                val result = LinkedHashMap<FilterId, ImageBitmap>()
                for (id in FilterId.values()) {
                    val rendered = if (id == FilterId.ORIGINAL) {
                        small
                    } else {
                        ImagePipeline.render(small, EditParams(filter = id), 128)
                    }
                    result[id] = rendered.asImageBitmap()
                }
                small.recycle()
                result
            }
            filterThumbs = thumbs
        }
    }

    // ----------------------------------------------------------------- save

    fun saveEdit(share: Boolean) {
        val sourceFile = editingFile ?: return
        val current = params
        viewModelScope.launch {
            busy = true
            val saved = withContext(Dispatchers.IO) {
                val full = store.decode(sourceFile, EXPORT_MAX) ?: return@withContext null
                val rendered = ImagePipeline.render(full, current, EXPORT_MAX)
                val target = store.newEditFile()
                val ok = store.write(rendered, target)
                rendered.recycle()
                full.recycle()
                if (ok) target else null
            }
            busy = false
            if (saved == null) {
                toast = "Could not save the photo"
                return@launch
            }
            refreshGallery()
            if (share) {
                shareRequest = saved
            } else {
                toast = "Saved to library"
                screen = Screen.Gallery
            }
        }
    }

    fun deleteCurrent() {
        val file = editingFile ?: return
        viewModelScope.launch {
            val ok = withContext(Dispatchers.IO) { store.delete(file) }
            if (editingFile == file) {
                editingFile = null
                base = null
                preview = null
                originalPreview = null
            }
            refreshGallery()
            toast = if (ok) "Photo deleted" else "Could not delete"
            screen = if (backTo == Screen.Gallery) Screen.Gallery else Screen.Camera
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
}
