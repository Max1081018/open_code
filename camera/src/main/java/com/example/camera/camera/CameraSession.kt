package com.example.camera.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CaptureRequest
import android.util.Range
import android.view.Surface
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalUseCaseApi
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.util.Consumer
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.File
import java.util.concurrent.TimeUnit

/** Capture modes available on the shutter carousel. */
enum class CaptureMode(val label: String) {
    PHOTO("Photo"),
    VIDEO("Video"),
    PORTRAIT("Portrait"),
    NIGHT("Night"),
    PRO("Pro")
}

/** Video quality presets. 4K is offered whenever the device reports it. */
enum class VideoQuality(val label: String, val quality: Quality) {
    UHD("4K", Quality.UHD),
    FHD("1080p", Quality.FHD),
    HD("720p", Quality.HD)
}

/** Photo aspect presets. 4:3 captures the largest sensor area. */
enum class PhotoAspect(val label: String, val ratio: Int) {
    RATIO_4_3("4:3", AspectRatio.RATIO_4_3),
    RATIO_16_9("16:9", AspectRatio.RATIO_16_9)
}

/**
 * Thin wrapper around CameraX. Owns the preview, photo and video use cases and
 * exposes the few bits of state the Compose UI needs.
 */
class CameraSession(context: Context) {

    private val appContext = context.applicationContext
    private val mainExecutor = ContextCompat.getMainExecutor(appContext)

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageCapture: ImageCapture? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
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

    var minZoom by mutableStateOf(1f)
        private set

    var maxZoom by mutableStateOf(1f)
        private set

    var exposureIndex by mutableStateOf(0)
        private set

    var exposureMin by mutableStateOf(-2)
        private set

    var exposureMax by mutableStateOf(2)
        private set

    var isRecording by mutableStateOf(false)
        private set

    var hasFlash by mutableStateOf(false)
        private set

    var isTorchOn by mutableStateOf(false)
        private set

    var mode by mutableStateOf(CaptureMode.PHOTO)
        private set

    var videoQuality by mutableStateOf(VideoQuality.FHD)
        private set

    var photoAspect by mutableStateOf(PhotoAspect.RATIO_4_3)
        private set

    var frameRate by mutableStateOf(30)
        private set

    var mirrorSelfie by mutableStateOf(true)
        private set

    private var targetZoom = 1f
    private var binding = false

    fun bind(previewView: PreviewView, lifecycleOwner: LifecycleOwner) {
        view = previewView
        owner = lifecycleOwner
        val future = ProcessCameraProvider.getInstance(appContext)
        future.addListener({ start() }, mainExecutor)
    }

    /** Rebinds the use cases after a mode, quality, aspect or lens change. */
    fun refresh() {
        if (view != null && owner != null) start()
    }

    @OptIn(ExperimentalUseCaseApi::class)
    private fun start() {
        val previewView = view ?: return
        val lifecycleOwner = owner ?: return
        if (binding) return
        binding = true

        val cameraProvider = try {
            ProcessCameraProvider.getInstance(appContext).get()
        } catch (t: Throwable) {
            binding = false
            ready = false
            error = "Camera unavailable on this device"
            return
        }
        provider = cameraProvider

        val previewBuilder = Preview.Builder().apply {
            if (frameRate > 0) {
                try {
                    setTargetFrameRate(Range(frameRate, frameRate))
                } catch (t: Throwable) {
                    // Some devices refuse an exact rate; CameraX keeps auto.
                }
            }
        }
        val preview = previewBuilder.build().apply {
            setSurfaceProvider(previewView.surfaceProvider)
        }

        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val rotation = previewView.display?.rotation ?: Surface.ROTATION_0

        val useCases: MutableList<androidx.camera.core.UseCase> = mutableListOf(preview)
        imageCapture = null
        videoCapture = null

        if (mode == CaptureMode.VIDEO) {
            val qualitySelector = QualitySelector.fromOrderedList(
                listOf(videoQuality.quality),
                androidx.camera.video.FallbackStrategy.higherQualityOrLowerThan(Quality.SD)
            )
            val recorder = Recorder.Builder()
                .setQualitySelector(qualitySelector)
                .setExecutor(mainExecutor)
                .build()
            val capture = VideoCapture.withOutput(recorder)
            capture.targetRotation = rotation
            useCases.add(capture)
            videoCapture = capture
        } else {
            val aspect = when (photoAspect) {
                PhotoAspect.RATIO_4_3 -> AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY
                PhotoAspect.RATIO_16_9 -> AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY
            }
            val resolutionSelector = ResolutionSelector.Builder()
                .setAspectRatioStrategy(aspect)
                .build()
            val capture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                .setResolutionSelector(resolutionSelector)
                .setJpegQuality(100)
                .build()
            capture.flashMode = flashMode
            capture.targetRotation = rotation
            useCases.add(capture)
            imageCapture = capture
        }

        try {
            cameraProvider.unbindAll()
            camera = cameraProvider.bindToLifecycle(
                lifecycleOwner,
                selector,
                *useCases.toTypedArray()
            )
            error = null
            ready = true

            val info = camera?.cameraInfo
            val zoom = info?.zoomState?.value
            minZoom = zoom?.minZoomRatio ?: 1f
            maxZoom = zoom?.maxZoomRatio ?: 1f
            if (targetZoom < minZoom || targetZoom > maxZoom) targetZoom = minZoom
            zoomRatio = targetZoom
            camera?.cameraControl?.setZoomRatio(targetZoom)

            val exposure = info?.exposureState
            if (exposure != null && exposure.isExposureCompensationSupported) {
                exposureMin = exposure.exposureCompensationRange.lower
                exposureMax = exposure.exposureCompensationRange.upper
                exposureIndex = exposure.exposureCompensationIndex
            } else {
                exposureMin = 0
                exposureMax = 0
                exposureIndex = 0
            }

            hasFlash = info?.hasFlashUnit() == true
            isTorchOn = false
            isRecording = false
        } catch (t: Throwable) {
            ready = false
            camera = null
            imageCapture = null
            videoCapture = null
            error = t.message ?: "Could not start the camera"
        } finally {
            binding = false
        }
    }

    fun setMode(next: CaptureMode) {
        if (next == mode) return
        if (isRecording) stopRecording()
        mode = next
        if (next == CaptureMode.VIDEO && flashMode != ImageCapture.FLASH_MODE_OFF) {
            flashMode = ImageCapture.FLASH_MODE_OFF
        }
        refresh()
    }

    fun setVideoQuality(next: VideoQuality) {
        if (next == videoQuality) return
        videoQuality = next
        refresh()
    }

    fun setPhotoAspect(next: PhotoAspect) {
        if (next == photoAspect) return
        photoAspect = next
        refresh()
    }

    fun setFrameRate(next: Int) {
        if (next == frameRate) return
        frameRate = next
        refresh()
    }

    fun setMirrorSelfie(value: Boolean) {
        mirrorSelfie = value
    }

    fun toggleLens() {
        if (isRecording) return
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        ready = false
        refresh()
    }

    /** Off -> On -> Auto -> Off. Returns the new mode. */
    fun cycleFlash(): Int {
        if (lensFacing == CameraSelector.LENS_FACING_FRONT || mode == CaptureMode.VIDEO) {
            flashMode = ImageCapture.FLASH_MODE_OFF
            imageCapture?.flashMode = flashMode
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

    fun toggleTorch() {
        val cam = camera ?: return
        val next = !isTorchOn
        cam.cameraControl.enableTorch(next)
        isTorchOn = next
    }

    fun zoomTo(ratio: Float): Float {
        val cam = camera ?: return zoomRatio
        val state = cam.cameraInfo.zoomState.value ?: return zoomRatio
        val next = ratio.coerceIn(state.minZoomRatio, state.maxZoomRatio)
        targetZoom = next
        cam.cameraControl.setZoomRatio(next)
        zoomRatio = next
        return next
    }

    fun zoomBy(factor: Float): Float = zoomTo(targetZoom * factor)

    fun setExposure(index: Int) {
        val cam = camera ?: return
        val exposure = cam.cameraInfo.exposureState
        if (!exposure.isExposureCompensationSupported) return
        val next = index.coerceIn(
            exposure.exposureCompensationRange.lower,
            exposure.exposureCompensationRange.upper
        )
        exposureIndex = next
        cam.cameraControl.setExposureCompensationIndex(next)
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
        if (capture == null || !ready || mode == CaptureMode.VIDEO) {
            onDone(false, "Camera is still warming up")
            return
        }
        capture.targetRotation = view?.display?.rotation ?: Surface.ROTATION_0
        val metadata = ImageCapture.Metadata().apply {
            isReversedHorizontal = lensFacing == CameraSelector.LENS_FACING_FRONT && mirrorSelfie
        }
        val options = ImageCapture.OutputFileOptions
            .Builder(file)
            .setMetadata(metadata)
            .build()
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

    fun startRecording(file: File, withAudio: Boolean, onDone: (Boolean, String?) -> Unit) {
        val capture = videoCapture ?: run {
            onDone(false, "Video is not ready")
            return
        }
        if (isRecording) {
            onDone(false, "Already recording")
            return
        }
        val permission = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        file.parentFile?.mkdirs()
        val output = FileOutputOptions.Builder(file).build()
        val pending = capture.output.prepareRecording(appContext, output)
        val prepared = if (withAudio && permission) pending.withAudioEnabled() else pending
        try {
            recording = prepared.start(
                mainExecutor,
                object : Consumer<VideoRecordEvent> {
                    override fun accept(event: VideoRecordEvent) {
                        when (event) {
                            is VideoRecordEvent.Start -> {
                                isRecording = true
                            }
                            is VideoRecordEvent.Finalize -> {
                                isRecording = false
                                recording = null
                                if (event.hasError()) {
                                    file.delete()
                                    onDone(false, event.cause?.message ?: "Recording failed")
                                } else {
                                    onDone(file.length() > 0, null)
                                }
                            }
                            else -> Unit
                        }
                    }
                }
            )
            isRecording = true
        } catch (t: Throwable) {
            isRecording = false
            recording = null
            file.delete()
            onDone(false, t.message ?: "Could not start recording")
        }
    }

    fun stopRecording() {
        val current = recording ?: return
        recording = null
        try {
            current.stop()
        } catch (t: Throwable) {
            isRecording = false
        }
    }

    fun release() {
        try {
            recording?.stop()
        } catch (t: Throwable) {
            // Already stopped.
        }
        recording = null
        try {
            provider?.unbindAll()
        } catch (t: Throwable) {
            // Nothing sensible to do while tearing down.
        }
        provider = null
        camera = null
        imageCapture = null
        videoCapture = null
        ready = false
        isRecording = false
    }
}
