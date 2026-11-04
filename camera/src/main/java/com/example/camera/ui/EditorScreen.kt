package com.example.camera.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.AutoFixHigh
import androidx.compose.material.icons.rounded.Brightness6
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CropRotate
import androidx.compose.material.icons.rounded.Face
import androidx.compose.material.icons.rounded.Flip
import androidx.compose.material.icons.rounded.HdrOn
import androidx.compose.material.icons.rounded.NightsStay
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.BlurOn
import androidx.compose.material.icons.rounded.Rotate90DegreesCcw
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.camera.data.FilterId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private enum class EditTab(val label: String) {
    Looks("Looks"),
    Light("Light"),
    Color("Color"),
    Detail("Detail"),
    Ai("AI"),
    Crop("Crop")
}

private val CROP_ASPECTS = listOf(
    "Full" to null,
    "1:1" to 1f,
    "4:5" to 0.8f,
    "3:2" to 1.5f,
    "16:9" to 16f / 9f
)

/** Cached once; enum .values() allocates on every call. */
private val EDIT_TABS = EditTab.values()
private val FILTERS = FilterId.values()

@Composable
fun EditorScreen(vm: CameraViewModel) {
    var tab by remember { mutableStateOf(EditTab.Looks) }
    var showOriginal by remember { mutableStateOf(false) }
    val params = vm.params
    val image = if (showOriginal) vm.originalPreview else vm.preview

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        // ---------------------------------------------------------- top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            HaloIconButton(
                icon = Icons.Rounded.Close,
                contentDescription = "Close editor",
                onClick = { vm.closeEditor() }
            )
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Edit",
                    color = Mist,
                    fontFamily = DisplayFont,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = when {
                        params.portrait -> "Portrait · ${params.filter.label}"
                        params.aiVision -> "AI Vision · ${params.filter.label}"
                        params.night -> "Night · ${params.filter.label}"
                        else -> params.filter.label
                    },
                    color = Muted,
                    fontSize = 11.sp
                )
            }
            HaloIconButton(
                icon = Icons.AutoMirrored.Rounded.Undo,
                contentDescription = "Reset edits",
                onClick = { vm.resetEdits() }
            )
            Spacer(modifier = Modifier.width(8.dp))
            HaloIconButton(
                icon = Icons.Rounded.Share,
                contentDescription = "Share",
                onClick = { vm.saveEdit(share = true) }
            )
            Spacer(modifier = Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .clip(CircleShape)
                    .background(Amber)
                    .clickable { vm.saveEdit(share = false) },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = "Save",
                    tint = Ink,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        // ------------------------------------------------------------ image
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 4.dp),
            contentAlignment = Alignment.Center
        ) {
            if (image != null) {
                Image(
                    bitmap = image,
                    contentDescription = "Edit preview",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .pointerInput(Unit) {
                            detectTapGestures(
                                onPress = {
                                    showOriginal = true
                                    tryAwaitRelease()
                                    showOriginal = false
                                }
                            )
                        }
                )
            } else {
                CircularProgressIndicator(color = Amber, strokeWidth = 2.dp)
            }

            if (showOriginal) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .clip(RoundedCornerShape(50))
                        .background(Color.Black.copy(alpha = 0.6f))
                        .padding(horizontal = 12.dp, vertical = 5.dp)
                ) {
                    Text(
                        text = "ORIGINAL",
                        color = Mist,
                        fontFamily = DisplayFont,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            } else {
                EditHistogram(
                    image = vm.preview,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(10.dp)
                        .size(width = 84.dp, height = 48.dp)
                )
            }
        }

        // ------------------------------------------------------------ panel
        EditorPanel(vm, tab, onTab = { tab = it })
    }
}

// ------------------------------------------------------------- tabs rail

@Composable
private fun EditorPanel(vm: CameraViewModel, tab: EditTab, onTab: (EditTab) -> Unit) {
    val tabs = EDIT_TABS
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Panel)
    ) {
        when (tab) {
            EditTab.Looks -> LooksPanel(vm)
            EditTab.Light -> LightPanel(vm)
            EditTab.Color -> ColorPanel(vm)
            EditTab.Detail -> DetailPanel(vm)
            EditTab.Ai -> AiPanel(vm)
            EditTab.Crop -> CropPanel(vm)
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            tabs.forEach { entry ->
                val selected = entry == tab
                Column(
                    modifier = Modifier.haloClick { onTab(entry) },
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Icon(
                        imageVector = when (entry) {
                            EditTab.Looks -> Icons.Rounded.Palette
                            EditTab.Light -> Icons.Rounded.Brightness6
                            EditTab.Color -> Icons.Rounded.Tune
                            EditTab.Detail -> Icons.Rounded.AutoFixHigh
                            EditTab.Ai -> Icons.Rounded.Visibility
                            EditTab.Crop -> Icons.Rounded.CropRotate
                        },
                        contentDescription = entry.label,
                        tint = if (selected) Amber else Muted,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = entry.label,
                        color = if (selected) Amber else Muted,
                        fontSize = 10.sp,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium
                    )
                    Spacer(modifier = Modifier.height(3.dp))
                    Box(
                        modifier = Modifier
                            .width(22.dp)
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
}

// -------------------------------------------------------------- looks tab

@Composable
private fun LooksPanel(vm: CameraViewModel) {
    val params = vm.params
    Column(modifier = Modifier.padding(vertical = 10.dp)) {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(FILTERS.toList()) { id ->
                val selected = params.filter == id
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier
                            .size(58.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(PanelHigh)
                            .border(
                                2.dp,
                                if (selected) Amber else Color.Transparent,
                                RoundedCornerShape(14.dp)
                            )
                            .clickable { vm.update { it.withFilter(id) } }
                    ) {
                        vm.filterThumbs[id]?.let { thumb ->
                            Image(
                                bitmap = thumb,
                                contentDescription = id.label,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = id.label,
                        color = if (selected) Amber else Muted,
                        fontSize = 9.sp,
                        maxLines = 1
                    )
                }
            }
        }
        if (params.filter != FilterId.ORIGINAL) {
            Spacer(modifier = Modifier.height(4.dp))
            HaloSlider(
                label = "Intensity",
                value = params.filterIntensity,
                range = 0f..1f,
                onChange = { v -> vm.update { it.copy(filterIntensity = v) } },
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp),
                valueLabel = "${(params.filterIntensity * 100).toInt()}%"
            )
        }
    }
}

// -------------------------------------------------------------- light tab

@Composable
private fun LightPanel(vm: CameraViewModel) {
    val p = vm.params
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
        HaloSlider("Exposure", p.exposure, -1f..1f) { v -> vm.update { it.copy(exposure = v) } }
        HaloSlider("Contrast", p.contrast, -1f..1f) { v -> vm.update { it.copy(contrast = v) } }
        HaloSlider("Highlights", p.highlights, -1f..1f) { v -> vm.update { it.copy(highlights = v) } }
        HaloSlider("Shadows", p.shadows, -1f..1f) { v -> vm.update { it.copy(shadows = v) } }
        HaloSlider("Fade", p.fade, 0f..1f) { v -> vm.update { it.copy(fade = v) } }
        Spacer(modifier = Modifier.height(6.dp))
    }
}

// -------------------------------------------------------------- color tab

@Composable
private fun ColorPanel(vm: CameraViewModel) {
    val p = vm.params
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
        HaloSlider("Saturation", p.saturation, -1f..1f) { v -> vm.update { it.copy(saturation = v) } }
        HaloSlider("Warmth", p.warmth, -1f..1f) { v -> vm.update { it.copy(warmth = v) } }
        HaloSlider("Tint", p.tint, -1f..1f) { v -> vm.update { it.copy(tint = v) } }
        Spacer(modifier = Modifier.height(6.dp))
    }
}

// ------------------------------------------------------------- detail tab

@Composable
private fun DetailPanel(vm: CameraViewModel) {
    val p = vm.params
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
        HaloSlider("Clarity", p.clarity, 0f..1f) { v -> vm.update { it.copy(clarity = v) } }
        HaloSlider("Sharpen", p.sharpen, 0f..1f) { v -> vm.update { it.copy(sharpen = v) } }
        HaloSlider("Denoise", p.denoise, 0f..1f) { v -> vm.update { it.copy(denoise = v) } }
        HaloSlider("Grain", p.grain, 0f..1f) { v -> vm.update { it.copy(grain = v) } }
        HaloSlider("Vignette", p.vignette, 0f..1f) { v -> vm.update { it.copy(vignette = v) } }
        Spacer(modifier = Modifier.height(6.dp))
    }
}

// ----------------------------------------------------------------- ai tab

@Composable
private fun AiPanel(vm: CameraViewModel) {
    val p = vm.params
    Column(
        modifier = Modifier
            // Bound the scroll viewport, otherwise a scrollable Column inside an
            // unconstrained parent takes its full content height and pushes the
            // tab rail off the bottom of the screen.
            .heightIn(max = 300.dp)
            .padding(horizontal = 12.dp)
            .verticalScroll(rememberScrollState())
    ) {
        vm.scene?.let { scene ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(PanelHigh)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Rounded.Visibility,
                    contentDescription = null,
                    tint = Teal,
                    modifier = Modifier.size(16.dp)
                )
                Spacer(modifier = Modifier.width(10.dp))
                Column {
                    Text("Scene · ${scene.label}", color = Mist, fontSize = 12.sp)
                    Text("Read on-device, nothing uploaded", color = Muted, fontSize = 10.sp)
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }
        GradientButton(
            text = "AI enhance this photo",
            leading = Icons.Rounded.Visibility,
            onClick = { vm.autoEnhance() },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(8.dp))
        ToggleCard(
            title = "AI vision",
            subtitle = "Lift micro-detail and colour the way Halo sees it",
            on = p.aiVision,
            icon = Icons.Rounded.Visibility,
            onClick = { vm.update { it.copy(aiVision = !it.aiVision) } },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(6.dp))
        ToggleCard(
            title = "Night boost",
            subtitle = "Brighten dark shots and tame noise",
            on = p.night,
            icon = Icons.Rounded.NightsStay,
            onClick = { vm.update { it.copy(night = !it.night) } },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(6.dp))
        ToggleCard(
            title = "Smart HDR",
            subtitle = "Pull back blown skies and lift deep shadows",
            on = p.hdr,
            icon = Icons.Rounded.HdrOn,
            onClick = { vm.update { it.copy(hdr = !it.hdr) } },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(6.dp))
        ToggleCard(
            title = "Detail boost",
            subtitle = "Edge-aware sharpening for ultra crisp crops",
            on = p.detail,
            icon = Icons.Rounded.AutoFixHigh,
            onClick = { vm.update { it.copy(detail = !it.detail) } },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(6.dp))
        ToggleCard(
            title = "Portrait bokeh",
            subtitle = "Blur the backdrop around the subject",
            on = p.portrait,
            icon = Icons.Rounded.BlurOn,
            onClick = { vm.update { it.copy(portrait = !it.portrait) } },
            modifier = Modifier.fillMaxWidth()
        )
        if (p.portrait) {
            Spacer(modifier = Modifier.height(2.dp))
            HaloSlider(
                label = "Blur strength",
                value = p.portraitStrength,
                range = 0f..1f,
                onChange = { v -> vm.update { it.copy(portraitStrength = v) } }
            )
        }
        Spacer(modifier = Modifier.height(6.dp))
        ToggleCard(
            title = "Beautify",
            subtitle = "Gentle skin smoothing that keeps texture",
            on = p.beauty,
            icon = Icons.Rounded.Face,
            onClick = { vm.update { it.copy(beauty = !it.beauty) } },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(10.dp))
    }
}

// --------------------------------------------------------------- crop tab

@Composable
private fun CropPanel(vm: CameraViewModel) {
    val p = vm.params
    Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            HaloIconButton(
                icon = Icons.Rounded.Rotate90DegreesCcw,
                contentDescription = "Rotate 90 degrees",
                onClick = { vm.rotate() },
                size = 52.dp,
                iconSize = 22.dp
            )
            HaloIconButton(
                icon = Icons.Rounded.Flip,
                contentDescription = "Flip horizontally",
                onClick = { vm.flipHorizontal() },
                size = 52.dp,
                iconSize = 22.dp
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            CROP_ASPECTS.forEach { (label, ratio) ->
                TextPill(
                    text = label,
                    selected = p.cropAspect == ratio,
                    onClick = { vm.setCropAspect(ratio) }
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Crop, rotate and flip update the preview live and are baked in at full resolution on save.",
            color = Muted,
            fontSize = 11.sp
        )
        Spacer(modifier = Modifier.height(8.dp))
    }
}

// ------------------------------------------------------------- histogram

private class HistogramBins {
    val r = IntArray(48)
    val g = IntArray(48)
    val b = IntArray(48)
    var max = 1
}

@Composable
private fun EditHistogram(
    image: ImageBitmap?,
    modifier: Modifier = Modifier
) {
    val bins by produceState(initialValue = HistogramBins(), image) {
        if (image == null) return@produceState
        val computed = withContext(Dispatchers.Default) {
            val result = HistogramBins()
            try {
                val src = image.asAndroidBitmap()
                val scale = 96f / maxOf(src.width, src.height).coerceAtLeast(1)
                val w = (src.width * scale).toInt().coerceIn(4, 96)
                val h = (src.height * scale).toInt().coerceIn(4, 96)
                val scaled = if (w == src.width && h == src.height) {
                    src
                } else {
                    android.graphics.Bitmap.createScaledBitmap(src, w, h, true)
                }
                val pixels = IntArray(scaled.width * scaled.height)
                scaled.getPixels(pixels, 0, scaled.width, 0, 0, scaled.width, scaled.height)
                val denom = pixels.size.coerceAtLeast(1) / 10
                pixels.forEach { px ->
                    result.r[(((px shr 16) and 0xFF) * 47) / 255]++
                    result.g[(((px shr 8) and 0xFF) * 47) / 255]++
                    result.b[((px and 0xFF) * 47) / 255]++
                }
                result.max = denom.coerceAtLeast(1)
                if (scaled !== src) scaled.recycle()
            } catch (t: Throwable) {
                // Skip the histogram rather than blocking editing.
            }
            result
        }
        value = computed
    }

    Canvas(modifier = modifier) {
        drawRoundRect(
            color = Color.Black.copy(alpha = 0.45f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(8.dp.toPx())
        )
        val h = size.height
        val w = size.width
        val channels = listOf(
            bins.r to Color(0xFFE45A5A),
            bins.g to Color(0xFF55D97B),
            bins.b to Color(0xFF5AA0E4)
        )
        channels.forEach { (channel, color) ->
            val path = Path()
            path.moveTo(0f, h)
            for (i in channel.indices) {
                val x = i * w / (channel.size - 1)
                val v = (channel[i].toFloat() / bins.max).coerceIn(0f, 1f)
                path.lineTo(x, h - v * h)
            }
            path.lineTo(w, h)
            drawPath(path, color.copy(alpha = 0.45f))
        }
    }
}
