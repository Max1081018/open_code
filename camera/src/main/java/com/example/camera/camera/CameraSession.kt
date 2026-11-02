package com.example.camera.camera

import android.content.Context
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Thin wrapper around CameraX. Owns the preview + capture use cases and exposes
 * the few bits of state the Compose UI needs (ready, lens, flash, zoom).
 */
class CameraSession(context: Context) {

    private val appContext = context.applicationContext
    private val mainExecutor = ContextCompat.getMainExecutor(appContext)

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var view: PreviewView? = null
    private var owner: LifecycleOwner? = null

    var ready by mutableStateOf(false)
        private set

    var error by mutableStateOf<String?>(null)
        private set

    var lensFacing by mutableStateOf(CameraSelector.LENS_FACING_BACK)
        private set

    var flashMode by mutableStateOf(ImageCapture.FLASH_MODE_OFF)
        private set

    var zoomRatio by mutableStateOf(1f)
        private set

    private var targetZoom = 1f

    fun bind(previewView: PreviewView, lifecycleOwner: LifecycleOwner) {
        view = previewView
        owner = lifecycleOwner
        val future = ProcessCameraProvider.getInstance(appContext)
        future.addListener({ start() }, mainExecutor)
    }

    private fun start() {
        val previewView = view ?: return
        val lifecycleOwner = owner ?: return

        val cameraProvider = try {
            ProcessCameraProvider.getInstance(appContext).get()
        } catch (t: Throwable) {
            ready = false
            error = "Camera unavailable on this device"
            return
        }
        provider = cameraProvider

        val preview = Preview.Builder().build().apply {
            setSurfaceProvider(previewView.surfaceProvider)
        }
        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .build()
        capture.flashMode = flashMode
        capture.targetRotation = previewView.display?.rotation ?: Surface.ROTATION_0

        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()

        try {
            cameraProvider.unbindAll()
            camera = cameraProvider.bindToLifecycle(lifecycleOwner, selector, preview, capture)
            imageCapture = capture
            error = null
            ready = true
            targetZoom = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: 1f
            zoomRatio = targetZoom
        } catch (t: Throwable) {
            ready = false
            camera = null
            imageCapture = null
            error = t.message ?: "Could not start the camera"
        }
    }

    fun toggleLens() {
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        ready = false
        start()
    }

    /** Off -> On -> Auto -> Off. Returns the new mode. */
    fun cycleFlash(): Int {
        if (lensFacing == CameraSelector.LENS_FACING_FRONT) {
            flashMode = ImageCapture.FLASH_MODE_OFF
            return flashMode
        }
        flashMode = when (flashMode) {
            ImageCapture.FLASH_MODE_OFF -> ImageCapture.FLASH_MODE_ON
            ImageCapture.FLASH_MODE_ON -> ImageCapture.FLASH_MODE_AUTO
            else -> ImageCapture.FLASH_MODE_OFF
        }
        imageCapture?.flashMode = flashMode
        return flashMode
    }

    fun zoomBy(factor: Float): Float {
        val cam = camera ?: return zoomRatio
        val state = cam.cameraInfo.zoomState.value ?: return zoomRatio
        val next = (targetZoom * factor).coerceIn(state.minZoomRatio, state.maxZoomRatio)
        targetZoom = next
        cam.cameraControl.setZoomRatio(next)
        zoomRatio = next
        return next
    }

    fun focus(x: Float, y: Float) {
        val cam = camera ?: return
        val previewView = view ?: return
        val point = previewView.meteringPointFactory.createPoint(x, y)
        val action = FocusMeteringAction
            .Builder(point, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
            .setAutoCancelDuration(3, TimeUnit.SECONDS)
            .build()
        try {
            cam.cameraControl.startFocusAndMetering(action)
        } catch (t: Throwable) {
            // Focus is a nice-to-have; never break the preview for it.
        }
    }

    fun capture(file: File, onDone: (Boolean, String?) -> Unit) {
        val capture = imageCapture
        if (capture == null || !ready) {
            onDone(false, "Camera is still warming up")
            return
        }
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        capture.takePicture(
            options,
            mainExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    onDone(true, null)
                }

                override fun onError(exception: ImageCaptureException) {
                    onDone(false, exception.message)
                }
            }
        )
    }

    fun release() {
        try {
            provider?.unbindAll()
        } catch (t: Throwable) {
            // Nothing sensible to do while tearing down.
        }
        provider = null
        camera = null
        imageCapture = null
        ready = false
    }
}
