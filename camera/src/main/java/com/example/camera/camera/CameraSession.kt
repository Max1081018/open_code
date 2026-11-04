package com.example.camera.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CaptureRequest
import android.util.Range
import android.view.Surface
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
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
import com.google.common.util.concurrent.ListenableFuture
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

    var isPaused by mutableStateOf(false)
        private set

    var isMuted by mutableStateOf(false)
        private set

    var hasFlash by mutableStateOf(false)
        private set

    var isTorchOn by mutableStateOf(false)
        private set

    var requestedMode by mutableStateOf(CaptureMode.PHOTO)
        private set

    var requestedVideoQuality by mutableStateOf(VideoQuality.FHD)
        private set

    var requestedPhotoAspect by mutableStateOf(PhotoAspect.RATIO_4_3)
        private set

    var requestedFrameRate by mutableStateOf(30)
        private set

    var requestedMirrorSelfie by mutableStateOf(true)
        private set

    private var targetZoom = 1f
    private var binding = false
    private var initFuture: ListenableFuture<ProcessCameraProvider>? = null
    /** Cleared after one failed bind so we retry with CameraX's own fps choice. */
    private var interopFps = true

    fun bind(previewView: PreviewView, lifecycleOwner: LifecycleOwner) {
        view = previewView
        owner = lifecycleOwner
        ensureInitialized()
    }

    /** Rebinds the use cases after a mode, quality, aspect or lens change. */
    fun refresh() {
        if (view == null || owner == null) return
        ensureInitialized()
    }

    /** Clears a previous bind failure so the retry overlay can rebind cleanly. */
    fun clearError() {
        error = null
        ready = false
    }

    /**
     * Init runs exactly once and never blocks the UI thread: [start] only ever
     * reads an already-completed future, and the listener drives the very first
     * bind once the provider is ready.
     */
    private fun ensureInitialized() {
        val existing = initFuture
        if (existing != null) {
            if (existing.isDone) start()
            return
        }
        val future = ProcessCameraProvider.getInstance(appContext)
        initFuture = future
        future.addListener({
            if (initFuture === future) start()
        }, mainExecutor)
    }

    @OptIn(ExperimentalUseCaseApi::class, ExperimentalCamera2Interop::class)
    private fun start() {
        val previewView = view ?: return
        val lifecycleOwner = owner ?: return
        val initDone = initFuture
        if (initDone == null || !initDone.isDone) return // listener will re-enter
        if (binding) return
        binding = true

        val cameraProvider = try {
            // Never blocks: start() is only reached when the future is done.
            initDone.get()
        } catch (t: Throwable) {
            binding = false
            ready = false
            error = "Camera unavailable on this device"
            return
        }
        provider = cameraProvider

        val previewBuilder = Preview.Builder().apply {
            if (interopFps && requestedMode == CaptureMode.VIDEO && requestedFrameRate > 0) {
                // Pin the preview to the chosen rate so the viewfinder matches
                // what gets recorded. Photo mode keeps AE free for low light.
                try {
                    Camera2Interop.Extender(this).setCaptureRequestOption(
                        CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                        Range(requestedFrameRate, requestedFrameRate)
                    )
                } catch (t: Throwable) {
                    // Device rejected the interop path; CameraX keeps auto rate.
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

        if (requestedMode == CaptureMode.VIDEO) {
            val qualitySelector = QualitySelector.fromOrderedList(
                listOf(requestedVideoQuality.quality),
                androidx.camera.video.FallbackStrategy.higherQualityOrLowerThan(Quality.SD)
            )
            val recorder = Recorder.Builder()
                .setQualitySelector(qualitySelector)
                .setExecutor(mainExecutor)
                .setTargetVideoEncodingBitRate(
                    when (requestedVideoQuality) {
                        VideoQuality.UHD -> 45_000_000
                        VideoQuality.FHD -> 22_000_000
                        VideoQuality.HD -> 12_000_000
                    }
                )
                .build()
            val captureBuilder = VideoCapture.Builder(recorder)
            if (interopFps && requestedFrameRate > 0) {
                // The recorder's own use case must carry the fps option; an
                // option set on Preview only affects the viewfinder stream.
                try {
                    Camera2Interop.Extender(captureBuilder).setCaptureRequestOption(
                        CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                        Range(requestedFrameRate, requestedFrameRate)
                    )
                } catch (t: Throwable) {
                    // Encoder rejected the rate; CameraX falls back to auto.
                }
            }
            val capture = captureBuilder.build()
            capture.targetRotation = rotation
            useCases.add(capture)
            videoCapture = capture
        } else {
            val aspect = when (requestedPhotoAspect) {
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
            isPaused = false
            isMuted = false
        } catch (t: Throwable) {
            ready = false
            camera = null
            imageCapture = null
            videoCapture = null
            if (interopFps && requestedMode == CaptureMode.VIDEO && requestedFrameRate > 0) {
                // The device refused the exact fps range. Retry once with the
                // default CameraX rate instead of leaving a dead camera.
                interopFps = false
                error = null
                mainExecutor.execute { start() }
            } else {
                error = t.message ?: "Could not start the camera"
            }
        } finally {
            binding = false
        }
    }

    fun setMode(next: CaptureMode) {
        if (next == requestedMode) return
        if (isRecording) stopRecording()
        requestedMode = next
        if (next == CaptureMode.VIDEO && flashMode != ImageCapture.FLASH_MODE_OFF) {
            flashMode = ImageCapture.FLASH_MODE_OFF
        }
        refresh()
    }

    fun setVideoQuality(next: VideoQuality) {
        if (next == requestedVideoQuality) return
        // Rebinding tears down the recorder, which finalises the clip with an
        // error and deletes it. Never reconfigure mid-recording.
        if (isRecording) return
        requestedVideoQuality = next
        refresh()
    }

    fun setPhotoAspect(next: PhotoAspect) {
        if (next == requestedPhotoAspect) return
        if (isRecording) return
        requestedPhotoAspect = next
        refresh()
    }

    fun setFrameRate(next: Int) {
        if (next == requestedFrameRate) return
        if (isRecording) return
        requestedFrameRate = next
        refresh()
    }

    fun setMirrorSelfie(value: Boolean) {
        requestedMirrorSelfie = value
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
        if (!hasFlash ||
            lensFacing == CameraSelector.LENS_FACING_FRONT ||
            requestedMode == CaptureMode.VIDEO
        ) {
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
        if (!cam.cameraInfo.hasFlashUnit()) {
            isTorchOn = false
            return
        }
        val next = !isTorchOn
        try {
            cam.cameraControl.enableTorch(next).addListener(
                { isTorchOn = next },
                mainExecutor
            )
        } catch (t: Throwable) {
            isTorchOn = false
        }
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
        if (capture == null || !ready || requestedMode == CaptureMode.VIDEO) {
            onDone(false, "Camera is still warming up")
            return
        }
        capture.targetRotation = view?.display?.rotation ?: Surface.ROTATION_0
        val metadata = ImageCapture.Metadata().apply {
            isReversedHorizontal = lensFacing == CameraSelector.LENS_FACING_FRONT && requestedMirrorSelfie
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
        isMuted = false
        try {
            recording = prepared.start(
                mainExecutor,
                object : Consumer<VideoRecordEvent> {
                    override fun accept(event: VideoRecordEvent) {
                        when (event) {
                            is VideoRecordEvent.Start -> {
                                isRecording = true
                                isPaused = false
                            }
                            is VideoRecordEvent.Pause -> {
                                isPaused = true
                            }
                            is VideoRecordEvent.Resume -> {
                                isPaused = false
                            }
                            is VideoRecordEvent.Finalize -> {
                                isRecording = false
                                isPaused = false
                                isMuted = false
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
        isPaused = false
        isMuted = false
        try {
            current.stop()
        } catch (t: Throwable) {
            isRecording = false
        }
    }

    /** Pauses the current clip; the file stays open so the take can continue. */
    fun pauseRecording() {
        val current = recording ?: return
        try {
            current.pause()
        } catch (t: Throwable) {
            // Some encoders cannot pause; keep recording untouched.
        }
    }

    /** Resumes a paused clip. */
    fun resumeRecording() {
        val current = recording ?: return
        try {
            current.resume()
        } catch (t: Throwable) {
            // Already recording or unsupported.
        }
    }

    /**
     * Silences or unmutes the clip that is currently being written. The audio
     * track stays in the file; muting just drops the samples, so the video and
     * the rest of the recording are untouched.
     */
    fun toggleMute(): Boolean {
        val current = recording ?: return isMuted
        val next = !isMuted
        return try {
            current.mute(next)
            isMuted = next
            next
        } catch (t: Throwable) {
            // Encoder without audio support; leave the flag alone.
            isMuted
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
        view = null
        owner = null
        ready = false
        isRecording = false
        isPaused = false
        isMuted = false
    }
}
