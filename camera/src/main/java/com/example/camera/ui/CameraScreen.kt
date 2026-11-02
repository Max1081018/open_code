package com.example.camera.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.ImageCapture
import androidx.camera.view.PreviewView
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.example.camera.camera.CameraSession
import com.example.camera.data.PhotoStore
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.Locale

@Composable
fun CameraScreen(vm: CameraViewModel) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var granted by remember { mutableStateOf(hasCameraPermission(context)) }
    var asked by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { ok ->
        granted = ok
        asked = true
    }

    LaunchedEffect(Unit) {
        if (!granted) launcher.launch(Manifest.permission.CAMERA)
    }

    if (!granted) {
        PermissionScreen(showSettings = asked, onRequest = {
            launcher.launch(Manifest.permission.CAMERA)
        })
        return
    }

    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val session = remember { CameraSession(context) }
    val scope = rememberCoroutineScope()

    var timer by remember { mutableStateOf(0) }
    var countdown by remember { mutableStateOf(0) }
    var grid by remember { mutableStateOf(true) }
    var capturing by remember { mutableStateOf(false) }
    var focusAt by remember { mutableStateOf<Offset?>(null) }
    var zoomHint by remember { mutableStateOf<String?>(null) }
    val flash = remember { Animatable(0f) }

    DisposableEffect(Unit) {
        onDispose { session.release() }
    }

    LaunchedEffect(Unit) {
        session.bind(previewView, lifecycleOwner)
    }

    LaunchedEffect(zoomHint) {
        if (zoomHint != null) {
            delay(900)
            zoomHint = null
        }
    }

    fun captureNow() {
        if (capturing) return
        capturing = true
        scope.launch {
            flash.snapTo(0.8f)
            flash.animateTo(0f, animationSpec = tween(340))
        }
        val file = vm.newCaptureFile()
        session.capture(file) { ok, message ->
            capturing = false
            if (ok && file.length() > 0) {
                vm.onCaptured(file)
            } else {
                file.delete()
                vm.showToast(message ?: "Capture failed, try again")
            }
        }
    }

    fun shoot() {
        if (capturing || countdown > 0) return
        if (timer == 0) {
            captureNow()
            return
        }
        val seconds = timer
        scope.launch {
            for (s in seconds downTo 1) {
                countdown = s
                delay(1000)
            }
            countdown = 0
            captureNow()
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
                        zoomHint = String.format(Locale.US, "%.1fx", ratio)
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

        // Top controls
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                RingButton(
                    active = session.flashMode != ImageCapture.FLASH_MODE_OFF,
                    onClick = { session.cycleFlash() }
                ) {
                    GlyphIcon(
                        kind = Glyph.Flash,
                        tint = if (session.flashMode == ImageCapture.FLASH_MODE_AUTO) {
                            Color.White.copy(alpha = 0.5f)
                        } else if (session.flashMode == ImageCapture.FLASH_MODE_OFF) {
                            Color.White
                        } else {
                            Ink
                        },
                        modifier = Modifier.size(19.dp)
                    )
                }
                RingButton(active = timer > 0, onClick = {
                    timer = when (timer) {
                        0 -> 3
                        3 -> 10
                        else -> 0
                    }
                }) {
                    if (timer == 0) {
                        GlyphIcon(Glyph.Timer, Color.White, Modifier.size(19.dp))
                    } else {
                        Text(
                            text = "${timer}s",
                            color = Ink,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
                RingButton(active = grid, onClick = { grid = !grid }) {
                    GlyphIcon(
                        kind = Glyph.Grid,
                        tint = if (grid) Ink else Color.White,
                        modifier = Modifier.size(19.dp)
                    )
                }
            }

            Text(
                text = "HALO",
                color = Mist.copy(alpha = 0.75f),
                fontSize = 11.sp,
                letterSpacing = 4.sp,
                fontWeight = FontWeight.Medium
            )
        }

        // Countdown
        if (countdown > 0) {
            Text(
                text = "$countdown",
                color = Color.White,
                fontSize = 96.sp,
                fontWeight = FontWeight.Light,
                modifier = Modifier.align(Alignment.Center)
            )
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
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(12.dp))
                    .padding(16.dp)
            )
        }

        // Bottom controls
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(bottom = 10.dp),
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
                        .background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(20.dp))
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 26.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                GalleryButton(
                    file = vm.gallery.firstOrNull(),
                    onClick = { vm.openGallery() }
                )

                ShutterButton(enabled = session.ready) { shoot() }

                RingButton(active = false, size = 48.dp, onClick = { session.toggleLens() }) {
                    GlyphIcon(Glyph.Flip, Color.White, Modifier.size(22.dp))
                }
            }
        }

        // Shutter flash
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.White.copy(alpha = flash.value))
        )
    }
}

// ---------------------------------------------------------------- pieces

@Composable
private fun GridOverlay() {
    Canvas(modifier = Modifier.fillMaxSize()) {
        val c = Color.White.copy(alpha = 0.18f)
        val w = 1.dp.toPx()
        drawLine(c, Offset(size.width / 3f, 0f), Offset(size.width / 3f, size.height), w)
        drawLine(c, Offset(size.width * 2f / 3f, 0f), Offset(size.width * 2f / 3f, size.height), w)
        drawLine(c, Offset(0f, size.height / 3f), Offset(size.width, size.height / 3f), w)
        drawLine(c, Offset(0f, size.height * 2f / 3f), Offset(size.width, size.height * 2f / 3f), w)
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
        val radius = 26.dp.toPx() + progress.value * 16.dp.toPx()
        val alpha = (1f - progress.value) * 0.9f
        drawCircle(
            color = Amber.copy(alpha = alpha),
            radius = radius,
            center = point,
            style = Stroke(width = 2.dp.toPx())
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
            .border(1.dp, if (active) Color.Transparent else Color.White.copy(alpha = 0.18f), CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
}

@Composable
private fun ShutterButton(enabled: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.9f else 1f, label = "shutter")

    Box(
        modifier = Modifier
            .size(84.dp)
            .scale(scale)
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
                color = Color.White.copy(alpha = 0.85f),
                radius = outer - 1.dp.toPx(),
                style = Stroke(width = 2.dp.toPx())
            )
            drawCircle(
                color = Color.White.copy(alpha = if (enabled) 1f else 0.35f),
                radius = outer - 9.dp.toPx()
            )
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
            .size(50.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(PanelHigh)
            .border(1.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(12.dp))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (thumb != null) {
            Image(
                bitmap = thumb,
                contentDescription = "Open library",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            GlyphIcon(Glyph.Gallery, Muted, Modifier.size(22.dp))
        }
    }
}

@Composable
private fun PermissionScreen(showSettings: Boolean, onRequest: () -> Unit) {
    val context = LocalContext.current
    var pulse by remember { mutableStateOf(false) }
    val glow by animateFloatAsState(if (pulse) 1f else 0.55f, animationSpec = tween(1200), label = "glow")
    LaunchedEffect(Unit) {
        while (true) {
            pulse = !pulse
            delay(1300)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Canvas(modifier = Modifier.size(96.dp)) {
            val r = size.minDimension / 2f
            drawCircle(Amber.copy(alpha = 0.10f + glow * 0.18f), radius = r)
            drawCircle(Amber, radius = r * 0.62f, style = Stroke(width = 2.dp.toPx()))
            drawCircle(Amber, radius = r * 0.22f)
        }
        Spacer(modifier = Modifier.height(28.dp))
        Text(
            text = "Let Halo see the light",
            color = Mist,
            fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = "Camera access is only used to take photos. They stay on this phone unless you share them.",
            color = Muted,
            fontSize = 14.sp,
            lineHeight = 21.sp,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(30.dp))
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(30.dp))
                .background(Amber)
                .clickable(onClick = onRequest)
                .padding(horizontal = 28.dp, vertical = 14.dp)
        ) {
            Text("Allow camera", color = Ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
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

private fun openAppSettings(context: Context) {
    val intent = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", context.packageName, null)
    )
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (t: Throwable) {
        Toast.makeText(context, "Could not open settings", Toast.LENGTH_SHORT).show()
    }
}
