package com.example.camera.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.camera.data.FilterId
import kotlin.math.roundToInt

private enum class EditTab(val label: String) {
    Filters("Filters"),
    Adjust("Adjust"),
    Ai("AI")
}

@Composable
fun EditorScreen(vm: CameraViewModel) {
    var tab by remember { mutableStateOf(EditTab.Filters) }
    val image = vm.preview

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Ink)
            .statusBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            CircleAction(onClick = { vm.closeEditor() }) {
                GlyphIcon(Glyph.Close, Mist, Modifier.size(17.dp))
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text("Edit", color = Mist, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    text = if (vm.params.filter == FilterId.ORIGINAL) "Original" else vm.params.filter.label,
                    color = Muted,
                    fontSize = 11.sp
                )
            }
            CircleAction(onClick = { vm.resetEdits() }) {
                GlyphIcon(Glyph.Reset, Mist, Modifier.size(17.dp))
            }
            Spacer(modifier = Modifier.width(8.dp))
            CircleAction(onClick = { vm.saveEdit(share = true) }) {
                GlyphIcon(Glyph.Share, Mist, Modifier.size(17.dp))
            }
            Spacer(modifier = Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .size(42.dp)
                    .clip(CircleShape)
                    .background(Amber)
                    .clickable { vm.saveEdit(share = false) },
                contentAlignment = Alignment.Center
            ) {
                GlyphIcon(Glyph.Check, Ink, Modifier.size(18.dp))
            }
        }

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 6.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Color.Black),
            contentAlignment = Alignment.Center
        ) {
            if (image != null) {
                Image(
                    bitmap = image,
                    contentDescription = "Edit preview",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                CircularProgressIndicator(color = Amber, strokeWidth = 2.dp)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(top = 8.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(Panel)
                        .padding(3.dp)
                ) {
                    EditTab.values().forEach { entry ->
                        val selected = entry == tab
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .clip(RoundedCornerShape(10.dp))
                                .background(if (selected) PanelHigh else Color.Transparent)
                                .clickable { tab = entry }
                                .padding(vertical = 8.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = entry.label,
                                color = if (selected) Amber else Muted,
                                fontSize = 12.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal
                            )
                        }
                    }
                }
                Spacer(modifier = Modifier.width(10.dp))
                Box(
                    modifier = Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(Panel)
                        .clickable { vm.deleteCurrent() },
                    contentAlignment = Alignment.Center
                ) {
                    GlyphIcon(Glyph.Trash, Muted, Modifier.size(15.dp))
                }
            }

            Spacer(modifier = Modifier.height(10.dp))

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(238.dp)
                    .padding(horizontal = 16.dp)
            ) {
                when (tab) {
                    EditTab.Filters -> FiltersPanel(vm)
                    EditTab.Adjust -> AdjustPanel(vm)
                    EditTab.Ai -> AiPanel(vm)
                }
            }
        }
    }
}

@Composable
private fun FiltersPanel(vm: CameraViewModel) {
    LazyRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(vertical = 4.dp)
    ) {
        items(FilterId.values().toList(), key = { it.name }) { id ->
            val selected = vm.params.filter == id
            Column(
                modifier = Modifier
                    .width(66.dp)
                    .clickable { vm.update { it.withFilter(id) } },
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Box(
                    modifier = Modifier
                        .size(62.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(PanelHigh)
                        .border(
                            width = 2.dp,
                            color = if (selected) Amber else Color.Transparent,
                            shape = RoundedCornerShape(14.dp)
                        )
                ) {
                    val thumb = vm.filterThumbs[id]
                    if (thumb != null) {
                        Image(
                            bitmap = thumb,
                            contentDescription = id.label,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = id.label,
                    color = if (selected) Amber else Muted,
                    fontSize = 11.sp,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
private fun AdjustPanel(vm: CameraViewModel) {
    val params = vm.params
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        SliderRow("Exposure", params.exposure, -1f..1f) { v ->
            vm.update { it.copy(exposure = v) }
        }
        SliderRow("Contrast", params.contrast, -1f..1f) { v ->
            vm.update { it.copy(contrast = v) }
        }
        SliderRow("Saturation", params.saturation, -0.6f..1f) { v ->
            vm.update { it.copy(saturation = v) }
        }
        SliderRow("Warmth", params.warmth, -0.6f..0.6f) { v ->
            vm.update { it.copy(warmth = v) }
        }
        SliderRow("Sharpen", params.sharpen, 0f..1f) { v ->
            vm.update { it.copy(sharpen = v) }
        }
    }
}

@Composable
private fun SliderRow(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    onChange: (Float) -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 1.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 2.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(label, color = Muted, fontSize = 12.sp)
            Text(percentLabel(value, range), color = Mist, fontSize = 12.sp)
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = range,
            colors = SliderDefaults.colors(
                thumbColor = Amber,
                activeTrackColor = Amber,
                inactiveTrackColor = Hairline
            )
        )
    }
}

@Composable
private fun AiPanel(vm: CameraViewModel) {
    val params = vm.params
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(Amber)
                .clickable { vm.autoEnhance() }
                .padding(vertical = 14.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            GlyphIcon(Glyph.Spark, Ink, Modifier.size(17.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "Auto enhance",
                color = Ink,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AiToggle(
                title = "Night",
                subtitle = "Lift shadows",
                on = params.night,
                modifier = Modifier.weight(1f)
            ) { vm.update { it.copy(night = !it.night) } }
            AiToggle(
                title = "HDR",
                subtitle = "Local contrast",
                on = params.hdr,
                modifier = Modifier.weight(1f)
            ) { vm.update { it.copy(hdr = !it.hdr) } }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            AiToggle(
                title = "Retouch",
                subtitle = "Smooth skin",
                on = params.beauty,
                modifier = Modifier.weight(1f)
            ) { vm.update { it.copy(beauty = !it.beauty) } }
            AiToggle(
                title = "Portrait",
                subtitle = "Edge blur",
                on = params.portrait,
                modifier = Modifier.weight(1f)
            ) { vm.update { it.copy(portrait = !it.portrait) } }
        }

        Text(
            text = "Every effect runs on this device. Nothing is uploaded.",
            color = Muted.copy(alpha = 0.85f),
            fontSize = 10.sp
        )
    }
}

@Composable
private fun AiToggle(
    title: String,
    subtitle: String,
    on: Boolean,
    modifier: Modifier = Modifier,
    onToggle: () -> Unit
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(if (on) Amber.copy(alpha = 0.15f) else PanelHigh)
            .border(1.dp, if (on) Amber else Hairline, RoundedCornerShape(14.dp))
            .clickable(onClick = onToggle)
            .padding(horizontal = 14.dp, vertical = 12.dp)
    ) {
        Text(
            text = title,
            color = if (on) Amber else Mist,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium
        )
        Text(text = subtitle, color = Muted, fontSize = 10.sp)
    }
}

@Composable
private fun CircleAction(size: Dp = 42.dp, onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(Panel)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
}

private fun percentLabel(value: Float, range: ClosedFloatingPointRange<Float>): String {
    val span = range.endInclusive - range.start
    if (span <= 0f) return "0%"
    val ratio = ((value - range.start) / span * 100f).roundToInt().coerceIn(0, 100)
    return "$ratio%"
}
