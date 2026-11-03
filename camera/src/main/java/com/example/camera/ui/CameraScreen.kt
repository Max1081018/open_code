package com.example.camera.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.ImageCapture
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Cameraswitch
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.FlashAuto
import androidx.compose.material.icons.rounded.FlashOff
import androidx.compose.material.icons.rounded.FlashOn
import androidx.compose.material.icons.rounded.GridOn
import androidx.compose.material.icons.rounded.Nightlight
import androidx.compose.material.icons.rounded.PhotoCamera
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.example.camera.camera.CaptureMode
import com.example.camera.camera.CameraSession
import com.example.camera.camera.PhotoAspect
import com.example.camera.camera.VideoQuality
import com.example.camera.data.PhotoStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale

@Composable
fun CameraScreen(vm: CameraViewModel) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val haptics = LocalHapticFeedback.current

    var granted by remember { mutableStateOf(hasCameraPermission(context)) }
    var asked by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { ok ->
        granted = ok
        asked = true
    }

    val audioLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    LaunchedEffect(Unit) {
        if (!granted) launcher.launch(Manifest.permission.CAMERA)
    }

    if (!granted) {
        PermissionScreen(showSettings = asked, onRequest = {
            launcher.launch(Manifest.permission.CAMERA)
        })
        return
    }

    val settings = vm.settings
    var grid by remember { mutableStateOf(settings.grid) }
    var timer by remember { mutableStateOf(settings.timerSeconds) }
    var showSettings by remember { mutableStateOf(false) }
    var mode by remember {
        mutableStateOf(
            runCatching { CaptureMode.valueOf(settings.lastMode) }.getOrDefault(CaptureMode.PHOTO)
        )
    }
    var videoQuality by remember {
        mutableStateOf(
            runCatching { VideoQuality.valueOf(settings.videoQuality) }.getOrDefault(VideoQuality.FHD)
        )
    }
    var photoAspect by remember {
        mutableStateOf(
            runCatching { PhotoAspect.valueOf(settings.photoAspect) }.getOrDefault(PhotoAspect.RATIO_4_3)
        )
    }
    var frameRate by remember { mutableStateOf(settings.frameRate) }
    var hapticsOn by remember { mutableStateOf(settings.haptics) }

    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val session = remember {
        CameraSession(context).apply {
            setVideoQuality(videoQuality)
            setPhotoAspect(photoAspect)
            setFrameRate(frameRate)
            setMirrorSelfie(settings.mirrorSelfie)
        }
    }

    LaunchedEffect(Unit) {
        session.bind(previewView, lifecycleOwner)
    }

    LaunchedEffect(mode) {
        session.setMode(mode)
        settings.lastMode = mode.name
        if (mode == CaptureMode.VIDEO && !hasAudioPermission(context)) {
            audioLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    LaunchedEffect(videoQuality) {
        session.setVideoQuality(videoQuality)
        settings.videoQuality = videoQuality.name
    }
    LaunchedEffect(photoAspect) {
        session.setPhotoAspect(photoAspect)
        settings.photoAspect = photoAspect.name
    }
    LaunchedEffect(frameRate) {
        session.setFrameRate(frameRate)
        settings.frameRate = frameRate
    }

    DisposableEffect(Unit) {
        onDispose { session.release() }
    }

    var countdown by remember { mutableStateOf(0) }
    var capturing by remember { mutableStateOf(false) }
    var focusAt by remember { mutableStateOf<Offset?>(null) }
    var zoomHint by remember { mutableStateOf<String?>(null) }
    var recordStart by remember { mutableStateOf(0L) }
    var recordSeconds by remember { mutableStateOf(0L) }
    val flash = remember { Animatable(0f) }
    val shutterScale = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(session.isRecording) {
        if (session.isRecording) {
            recordStart = SystemClock.elapsedRealtime()
            while (session.isRecording) {
                recordSeconds = (SystemClock.elapsedRealtime() - recordStart) / 1000
                delay(250)
            }
        } else {
            recordSeconds = 0
        }
    }

    LaunchedEffect(zoomHint) {
        if (zoomHint != null) {
            delay(900)
            zoomHint = null
        }
    }

    fun buzz(type: HapticFeedbackType = HapticFeedbackType.LongPress) {
        if (hapticsOn) haptics.performHapticFeedback(type)
    }

    fun captureNow() {
        if (capturing) return
        capturing = true
        buzz()
        scope.launch {
            shutterScale.snapTo(1.14f)
            shutterScale.animateTo(1f, animationSpec = tween(240))
        }
        scope.launch {
            flash.snapTo(0.72f)
            flash.animateTo(0f, animationSpec = tween(320))
        }
        val file = vm.newCaptureFile()
        session.capture(file) { ok, message ->
            capturing = false
            if (ok && file.length() > 0) {
                vm.onCaptured(file, portraitMode = mode == CaptureMode.PORTRAIT)
            } else {
                file.delete()
                vm.showToast(message ?: "Capture failed, try again")
            }
        }
    }

    fun shoot() {
        if (capturing || countdown > 0) return
        when (mode) {
            CaptureMode.VIDEO -> {
                if (session.isRecording) {
                    buzz()
                    session.stopRecording()
                } else {
                    buzz()
                    val file = vm.newVideoFile()
                    recordStart = SystemClock.elapsedRealtime()
                    session.startRecording(
                        file = file,
                        withAudio = hasAudioPermission(context)
                    ) { ok, message ->
                        if (ok) {
                            vm.onVideoSaved(file)
                        } else {
                            file.delete()
                            vm.showToast(message ?: "Recording failed")
                        }
                    }
                }
            }
            else -> {
                if (timer == 0) {
                    captureNow()
                    return
                }
                val seconds = timer
                scope.launch {
                    for (s in seconds downTo 1) {
                        countdown = s
                        buzz()
                        delay(1000)
                    }
                    countdown = 0
                    captureNow()
                }
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { previewView },
            modifier = Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    detectTransformGestures { _, _, zoom, _ ->
                        val ratio = session.zoomBy(zoom)
                        zoomHint = String.format(Locale.US, "%.2fx", ratio)
                    }
                }
                .pointerInput(Unit) {
                    detectTapGestures { offset ->
                        session.focus(offset.x, offset.y)
                        focusAt = offset
                    }
                }
        )

        if (grid) {
            GridOverlay()
        }

        focusAt?.let { point ->
            FocusReticle(point) { focusAt = null }
        }

        CameraTopBar(
            session = session,
            timer = timer,
            grid = grid,
            mode = mode,
            videoQuality = videoQuality,
            photoAspect = photoAspect,
            frameRate = frameRate,
            autoAi = settings.autoAi,
            onFlash = { session.cycleFlash() },
            onTimer = {
                timer = when (timer) {
                    0 -> 3
                    3 -> 10
                    else -> 0
                }
                settings.timerSeconds = timer
                buzz()
            },
            onGrid = {
                grid = !grid
                settings.grid = grid
                buzz()
            },
            onAutoAi = {
                settings.autoAi = !settings.autoAi
            },
            onSettings = { showSettings = true }
        )

        if (countdown > 0) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "$countdown",
                    color = Color.White,
                    fontFamily = DisplayFont,
                    fontSize = 110.sp,
                    fontWeight = FontWeight.Light
                )
            }
        }

        session.error?.let { message ->
            Text(
                text = message,
                color = Color.White,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(32.dp)
                    .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(16.dp))
                    .padding(horizontal = 18.dp, vertical = 14.dp)
            )
        }

        if (session.isRecording) {
            RecordingPill(
                seconds = recordSeconds,
                modifier = Modifier.align(Alignment.TopCenter)
            )
        }

        if (mode == CaptureMode.PRO && !session.isRecording) {
            ExposureControl(
                value = session.exposureIndex.toFloat(),
                range = session.exposureMin.toFloat()..session.exposureMax.toFloat(),
                onChange = { session.setExposure(it.toInt()) },
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 10.dp, bottom = 170.dp)
            )
        }

        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(bottom = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            zoomHint?.let { hint ->
                Text(
                    text = hint,
                    color = Mist,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier
                        .padding(bottom = 8.dp)
                        .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(20.dp))
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                )
            }

            ZoomSelector(
                session = session,
                onSelected = { ratio ->
                    session.zoomTo(ratio)
                    zoomHint = String.format(Locale.US, "%.2fx", ratio)
                    buzz()
                },
                modifier = Modifier.padding(bottom = 10.dp)
            )

            ModeCarousel(
                mode = mode,
                onSelected = { next ->
                    mode = next
                    buzz()
                },
                modifier = Modifier.padding(bottom = 8.dp)
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 30.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                GalleryButton(
                    file = vm.gallery.firstOrNull(),
                    onClick = {
                        buzz()
                        vm.openGallery()
                    }
                )

                ShutterButton(
                    enabled = session.ready,
                    recording = session.isRecording,
                    mode = mode,
                    onClick = { shoot() },
                    scale = shutterScale
                )

                RingButton(active = false, size = 50.dp, onClick = {
                    buzz()
                    session.toggleLens()
                }) {
                    Icon(
                        imageVector = Icons.Rounded.Cameraswitch,
                        contentDescription = "Flip camera",
                        tint = Color.White,
                        modifier = Modifier.size(22.dp)
                    )
                }
            }
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White.copy(alpha = flash.value))
        )

        AnimatedVisibility(
            visible = showSettings,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize()
        ) {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))) {
                SettingsSheet(
                    session = session,
                    settings = settings,
                    grid = grid,
                    timer = timer,
                    hapticsOn = hapticsOn,
                    frameRate = frameRate,
                    photoAspect = photoAspect,
                    videoQuality = videoQuality,
                    onGrid = { grid = it; settings.grid = it },
                    onTimer = { timer = it; settings.timerSeconds = it },
                    onHaptics = { hapticsOn = it; settings.haptics = it },
                    onFrameRate = { frameRate = it },
                    onPhotoAspect = { photoAspect = it },
                    onVideoQuality = { videoQuality = it },
                    onClose = { showSettings = false },
                    modifier = Modifier.align(Alignment.BottomCenter)
                )
            }
        }
    }
}

// ---------------------------------------------------------------- pieces

@Composable
private fun CameraTopBar(
    session: CameraSession,
    timer: Int,
    grid: Boolean,
    mode: CaptureMode,
    videoQuality: VideoQuality,
    photoAspect: PhotoAspect,
    frameRate: Int,
    autoAi: Boolean,
    onFlash: () -> Unit,
    onTimer: () -> Unit,
    onGrid: () -> Unit,
    onAutoAi: () -> Unit,
    onSettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                RingButton(
                    active = session.flashMode != ImageCapture.FLASH_MODE_OFF,
                    onClick = onFlash
                ) {
                    Icon(
                        imageVector = when (session.flashMode) {
                            ImageCapture.FLASH_MODE_ON -> Icons.Rounded.FlashOn
                            ImageCapture.FLASH_MODE_AUTO -> Icons.Rounded.FlashAuto
                            else -> Icons.Rounded.FlashOff
                        },
                        contentDescription = "Flash",
                        tint = if (session.flashMode == ImageCapture.FLASH_MODE_OFF) {
                            Color.White
                        } else if (session.flashMode == ImageCapture.FLASH_MODE_AUTO) {
                            Color.White.copy(alpha = 0.65f)
                        } else {
                            Ink
                        },
                        modifier = Modifier.size(18.dp)
                    )
                }
                RingButton(active = timer > 0, onClick = onTimer) {
                    if (timer == 0) {
                        Icon(
                            imageVector = Icons.Rounded.Timer,
                            contentDescription = "Timer",
                            tint = Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                    } else {
                        Text(
                            text = "${timer}s",
                            color = Ink,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
                RingButton(active = grid, onClick = onGrid) {
                    Icon(
                        imageVector = Icons.Rounded.GridOn,
                        contentDescription = "Grid",
                        tint = if (grid) Ink else Color.White,
                        modifier = Modifier.size(18.dp)
                    )
                }
            }

            Text(
                text = "HALO",
                color = Mist.copy(alpha = 0.8f),
                fontFamily = DisplayFont,
                fontSize = 12.sp,
                letterSpacing = 5.sp,
                fontWeight = FontWeight.SemiBold
            )

            RingButton(active = false, onClick = onSettings) {
                Icon(
                    imageVector = Icons.Rounded.Settings,
                    contentDescription = "Settings",
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatChip(
                    text = when (mode) {
                        CaptureMode.VIDEO -> "${videoQuality.label} · ${frameRate}fps"
                        CaptureMode.PHOTO, CaptureMode.PORTRAIT, CaptureMode.NIGHT ->
                            "${photoAspect.label} · Max"
                        CaptureMode.PRO -> "${photoAspect.label} · Manual"
                    },
                    accent = Teal
                )
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .clickable { onAutoAi() }
                ) {
                    StatChip(
                        text = if (autoAi) "Auto AI on" else "Auto AI off",
                        icon = Icons.Rounded.AutoAwesome,
                        accent = if (autoAi) Amber else Muted
                    )
                }
            }
        }
    }
}

@Composable
private fun ZoomSelector(
    session: CameraSession,
    onSelected: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    val presets = listOf(0.5f, 1f, 2f, 5f).filter { ratio ->
        ratio == 1f || ratio in session.minZoom..session.maxZoom
    }
    val current = session.zoomRatio
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.40f))
            .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(50))
            .padding(horizontal = 6.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        presets.forEach { ratio ->
            val selected = kotlin.math.abs(current - ratio) < 0.15f ||
                (ratio == presets.last() && current >= ratio * 0.95f)
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(if (selected) Amber else Color.Transparent)
                    .clickable { onSelected(ratio) },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = if (ratio < 1f) "0.5" else "${ratio.toInt()}",
                    color = if (selected) Ink else Mist,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun ModeCarousel(
    mode: CaptureMode,
    onSelected: (CaptureMode) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        CaptureMode.values().forEach { entry ->
            val selected = entry == mode
            Column(
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .clickable { onSelected(entry) }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = entry.label.uppercase(Locale.US),
                    color = if (selected) Amber else Mist.copy(alpha = 0.65f),
                    fontFamily = DisplayFont,
                    fontSize = if (selected) 12.sp else 11.sp,
                    letterSpacing = 1.4.sp,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium
                )
                Spacer(modifier = Modifier.height(3.dp))
                Box(
                    modifier = Modifier
                        .width(18.dp)
                        .height(2.dp)
                        .background(
                            if (selected) Amber else Color.Transparent,
                            RoundedCornerShape(2.dp)
                        )
                )
            }
        }
    }
}

@Composable
private fun RecordingPill(seconds: Long, modifier: Modifier = Modifier) {
    val minutes = seconds / 60
    val remainder = seconds % 60
    Row(
        modifier = modifier
            .statusBarsPadding()
            .padding(top = 74.dp)
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.6f))
            .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
            .padding(horizontal = 14.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(Danger)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = String.format(Locale.US, "%02d:%02d", minutes, remainder),
            color = Color.White,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

@Composable
private fun ExposureControl(
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    if (range.start >= range.endInclusive) return
    val span = range.endInclusive - range.start
    GlassSurface(
        modifier = modifier.width(58.dp),
        shape = RoundedCornerShape(22.dp),
        alpha = 0.55f
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp, horizontal = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "EV",
                color = Muted,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold
            )
            Spacer(modifier = Modifier.height(10.dp))
            // Vertical drag track: top = max exposure.
            val trackHeight = 150.dp
            Box(
                modifier = Modifier
                    .width(24.dp)
                    .height(trackHeight)
                    .pointerInput(range) {
                        detectTapGestures { offset ->
                            onChange(range.start + (1f - (offset.y / trackHeight.toPx().coerceAtLeast(1f))) * span)
                        }
                    }
                    .pointerInput(range) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                onChange(range.start + (1f - (offset.y / trackHeight.toPx().coerceAtLeast(1f))) * span)
                            },
                            onDrag = { change, _ ->
                                change.consume()
                                val y = change.position.y
                                onChange(range.start + (1f - (y / trackHeight.toPx().coerceAtLeast(1f))) * span)
                            }
                        )
                    }
            ) {
                // Track groove
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .width(4.dp)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(2.dp))
                        .background(Color.White.copy(alpha = 0.18f))
                )
                // Thumb
                val frac = ((value - range.start) / span).coerceIn(0f, 1f)
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .offset(y = with(LocalDensity.current) { trackHeight.times(frac) - 11.dp })
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(Amber, CircleShape)
                )
                // Center marker (neutral)
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .offset(y = with(LocalDensity.current) { trackHeight.div(2f) - 1.dp })
                        .width(14.dp)
                        .height(1.dp)
                        .background(Color.White.copy(alpha = 0.35f))
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = String.format(Locale.US, "%+.1f", value),
                color = Mist,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
}

@Composable
private fun GridOverlay() {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val c = Color.White.copy(alpha = 0.16f)
        val w = 1.dp.toPx()
        drawLine(c, Offset(size.width / 3f, 0f), Offset(size.width / 3f, size.height), w)
        drawLine(
            c,
            Offset(size.width * 2f / 3f, 0f),
            Offset(size.width * 2f / 3f, size.height),
            w
        )
        drawLine(c, Offset(0f, size.height / 3f), Offset(size.width, size.height / 3f), w)
        drawLine(
            c,
            Offset(0f, size.height * 2f / 3f),
            Offset(size.width, size.height * 2f / 3f),
            w
        )
    }
}

@Composable
private fun FocusReticle(point: Offset, onFinished: () -> Unit) {
    val progress = remember { Animatable(0f) }
    LaunchedEffect(point) {
        progress.snapTo(0f)
        progress.animateTo(1f, animationSpec = tween(650))
        onFinished()
    }
    Canvas(modifier = Modifier.fillMaxSize()) {
        val radius = 26.dp.toPx() + progress.value * 18.dp.toPx()
        val alpha = (1f - progress.value) * 0.95f
        drawCircle(
            color = Amber.copy(alpha = alpha),
            radius = radius,
            center = point,
            style = Stroke(width = 2.dp.toPx())
        )
        drawCircle(
            color = Amber.copy(alpha = alpha * 0.5f),
            radius = 4.dp.toPx(),
            center = point
        )
    }
}

@Composable
private fun RingButton(
    active: Boolean,
    onClick: () -> Unit,
    size: Dp = 42.dp,
    content: @Composable () -> Unit
) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(if (active) Amber else Color.Black.copy(alpha = 0.4f))
            .border(
                1.dp,
                if (active) Color.Transparent else Color.White.copy(alpha = 0.16f),
                CircleShape
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
}

@Composable
private fun ShutterButton(
    enabled: Boolean,
    recording: Boolean,
    mode: CaptureMode,
    onClick: () -> Unit,
    scale: Animatable<Float, *>
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val pressScale by animateFloatAsState(if (pressed) 0.9f else 1f, label = "shutter")
    val total = scale.value * pressScale

    Box(
        modifier = Modifier
            .size(88.dp)
            .scale(total)
            .clip(CircleShape)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick
            ),
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val outer = size.minDimension / 2f
            drawCircle(
                color = if (recording) Danger else Color.White.copy(alpha = 0.9f),
                radius = outer - 1.dp.toPx(),
                style = Stroke(width = 3.dp.toPx())
            )
            if (recording) {
                val side = outer * 0.55f
                drawRoundRect(
                    color = Danger,
                    topLeft = Offset(outer - side, outer - side),
                    size = androidx.compose.ui.geometry.Size(side * 2f, side * 2f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx())
                )
            } else if (mode == CaptureMode.VIDEO) {
                drawCircle(
                    color = Danger.copy(alpha = if (enabled) 1f else 0.35f),
                    radius = outer - 12.dp.toPx()
                )
            } else {
                drawCircle(
                    color = Color.White.copy(alpha = if (enabled) 1f else 0.35f),
                    radius = outer - 12.dp.toPx()
                )
            }
        }
    }
}

@Composable
private fun GalleryButton(file: File?, onClick: () -> Unit) {
    val context = LocalContext.current
    val store = remember(context) { PhotoStore.get(context.applicationContext) }
    val thumb = rememberThumbnail(store, file, 200)

    Box(
        modifier = Modifier
            .size(52.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(PanelHigh)
            .border(1.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (thumb != null) {
            androidx.compose.foundation.Image(
                bitmap = thumb,
                contentDescription = "Open library",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.PhotoLibrary,
                contentDescription = "Open library",
                tint = Muted,
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

// -------------------------------------------------------------- settings

@Composable
private fun SettingsSheet(
    session: CameraSession,
    settings: com.example.camera.data.SettingsStore,
    grid: Boolean,
    timer: Int,
    hapticsOn: Boolean,
    frameRate: Int,
    photoAspect: PhotoAspect,
    videoQuality: VideoQuality,
    onGrid: (Boolean) -> Unit,
    onTimer: (Int) -> Unit,
    onHaptics: (Boolean) -> Unit,
    onFrameRate: (Int) -> Unit,
    onPhotoAspect: (PhotoAspect) -> Unit,
    onVideoQuality: (VideoQuality) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    GlassSurface(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
        shape = RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp),
        alpha = 0.97f
    ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Camera settings",
                    color = Mist,
                    style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f)
                )
                RingButton(active = false, size = 34.dp, onClick = onClose) {
                    Icon(
                        imageVector = Icons.Rounded.Check,
                        contentDescription = "Close settings",
                        tint = Mist,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))
            SectionHeader("Capture")
            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SettingPillGroup(
                    options = PhotoAspect.values().map { it.label },
                    selected = photoAspect.label,
                    onSelect = { label ->
                        onPhotoAspect(PhotoAspect.values().first { it.label == label })
                    },
                    modifier = Modifier.weight(1f)
                )
            }

            Spacer(modifier = Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SettingPillGroup(
                    options = VideoQuality.values().map { it.label },
                    selected = videoQuality.label,
                    onSelect = { label ->
                        onVideoQuality(VideoQuality.values().first { it.label == label })
                    },
                    modifier = Modifier.weight(1f)
                )
                SettingPillGroup(
                    options = listOf("30fps", "60fps"),
                    selected = "${frameRate}fps",
                    onSelect = { label -> onFrameRate(label.removeSuffix("fps").toIntOrNull() ?: 30) },
                    modifier = Modifier.weight(1f)
                )
            }

            Spacer(modifier = Modifier.height(14.dp))
            SectionHeader("Behaviour")
            Spacer(modifier = Modifier.height(8.dp))

            SettingRow(
                title = "Rule of thirds grid",
                subtitle = "Overlay while framing",
                checked = grid,
                onCheckedChange = onGrid
            )
            Spacer(modifier = Modifier.height(6.dp))
            SettingRow(
                title = "Haptic feedback",
                subtitle = "Tiny buzz on shutter and controls",
                checked = hapticsOn,
                onCheckedChange = onHaptics
            )
            Spacer(modifier = Modifier.height(6.dp))
            SettingRow(
                title = "Auto AI after capture",
                subtitle = "Read the scene and enhance straight away",
                checked = settings.autoAi,
                onCheckedChange = { settings.autoAi = it }
            )
            Spacer(modifier = Modifier.height(6.dp))
            SettingRow(
                title = "Mirror selfies",
                subtitle = "Save front camera shots as you see them",
                checked = settings.mirrorSelfie,
                onCheckedChange = {
                    settings.mirrorSelfie = it
                    session.setMirrorSelfie(it)
                }
            )

            Spacer(modifier = Modifier.height(14.dp))
            SectionHeader("Timer")
            Spacer(modifier = Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0, 3, 10).forEach { seconds ->
                    TextPill(
                        text = if (seconds == 0) "Off" else "${seconds}s",
                        selected = timer == seconds,
                        onClick = { onTimer(seconds) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Halo Camera · on-device AI, nothing leaves this phone.",
                color = Muted,
                fontSize = 11.sp,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
            Spacer(modifier = Modifier.height(4.dp))
    }
}

@Composable
private fun SettingPillGroup(
    options: List<String>,
    selected: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(PanelHigh)
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        options.forEach { option ->
            val active = option == selected
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(11.dp))
                    .background(if (active) Amber else Color.Transparent)
                    .clickable { onSelect(option) }
                    .padding(vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = option,
                    color = if (active) Ink else Muted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

// -------------------------------------------------------------- permission

@Composable
private fun PermissionScreen(showSettings: Boolean, onRequest: () -> Unit) {
    val context = LocalContext.current
    var pulse by remember { mutableStateOf(false) }
    val glow by animateFloatAsState(
        if (pulse) 1f else 0.55f,
        animationSpec = tween(1300),
        label = "glow"
    )
    LaunchedEffect(Unit) {
        while (true) {
            pulse = !pulse
            delay(1400)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 34.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        HaloLogo(size = 120.dp, glow = glow)
        Spacer(modifier = Modifier.height(30.dp))
        Text(
            text = "Let Halo see the light",
            color = Mist,
            fontFamily = DisplayFont,
            fontSize = 24.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Camera access is only used to take photos and video. They stay on this phone unless you share them.",
            color = Muted,
            fontSize = 14.sp,
            lineHeight = 21.sp,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(32.dp))
        GradientButton(text = "Allow camera", onClick = onRequest, leading = Icons.Rounded.PhotoCamera)
        if (showSettings) {
            Spacer(modifier = Modifier.height(14.dp))
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(30.dp))
                    .clickable { openAppSettings(context) }
                    .padding(horizontal = 20.dp, vertical = 10.dp)
            ) {
                Text("Open settings", color = Muted, fontSize = 14.sp)
            }
        }
    }
}

// ----------------------------------------------------------------- utils

private fun hasCameraPermission(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
        PackageManager.PERMISSION_GRANTED

private fun hasAudioPermission(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
        PackageManager.PERMISSION_GRANTED

private fun openAppSettings(context: Context) {
    val intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null)
    )
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (t: Throwable) {
        // No settings activity available on this build.
    }
}

