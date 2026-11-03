package com.example.camera.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

// ---------------------------------------------------------------- surface

@Composable
fun GlassSurface(
    modifier: Modifier = Modifier,
    shape: androidx.compose.ui.graphics.Shape = RoundedCornerShape(20.dp),
    alpha: Float = 0.72f,
    borderColor: Color = Color.White.copy(alpha = 0.08f),
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .clip(shape)
            .background(InkSoft.copy(alpha = alpha))
            .border(1.dp, borderColor, shape)
            .padding(14.dp),
        content = content
    )
}

// ------------------------------------------------------------------ logo

@Composable
fun HaloLogo(size: Dp, glow: Float = 1f, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier.size(size)) {
        val r = size.minDimension.toPx() / 2f
        val ring = r * 0.72f
        drawCircle(
            brush = Brush.radialGradient(
                listOf(Amber.copy(alpha = 0.20f * glow), Color.Transparent)
            ),
            radius = r * 0.95f
        )
        drawCircle(
            color = Amber.copy(alpha = 0.25f),
            radius = ring + r * 0.10f,
            style = Stroke(width = r * 0.06f)
        )
        drawCircle(
            color = Amber,
            radius = ring,
            style = Stroke(width = r * 0.045f)
        )
        drawCircle(
            color = Ink,
            radius = ring * 0.62f
        )
        drawCircle(
            color = PanelHigh,
            radius = ring * 0.48f
        )
        drawCircle(
            color = Teal.copy(alpha = 0.9f),
            radius = ring * 0.16f
        )
        drawArc(
            color = Teal.copy(alpha = 0.85f),
            startAngle = -70f,
            sweepAngle = 55f,
            useCenter = false,
            topLeft = androidx.compose.ui.geometry.Offset(r - ring, r - ring),
            size = androidx.compose.ui.geometry.Size(ring * 2f, ring * 2f),
            style = Stroke(width = r * 0.05f, cap = StrokeCap.Round)
        )
    }
}

// --------------------------------------------------------------- buttons

@Composable
fun HaloIconButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = Mist,
    background: Color = Color.Black.copy(alpha = 0.35f),
    borderColor: Color = Color.White.copy(alpha = 0.12f),
    active: Boolean = false,
    size: Dp = 42.dp,
    iconSize: Dp = 19.dp
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.92f else 1f, label = "icon-press")
    Box(
        modifier = modifier
            .size(size)
            .scale(scale)
            .clip(CircleShape)
            .background(if (active) Amber else background)
            .border(1.dp, if (active) Color.Transparent else borderColor, CircleShape)
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick
            ),
        contentAlignment = Alignment.Center
    ) {
        androidx.compose.material3.Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = if (active) Ink else tint,
            modifier = Modifier.size(iconSize)
        )
    }
}

@Composable
fun GradientButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    gradient: Brush = AmberGold,
    leading: ImageVector? = null,
    height: Dp = 52.dp
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, label = "btn-press")
    Row(
        modifier = modifier
            .height(height)
            .scale(scale)
            .clip(RoundedCornerShape(height / 2f))
            .background(if (enabled) gradient else Color.White.copy(alpha = 0.10f))
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick
            )
            .padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center
    ) {
        if (leading != null) {
            androidx.compose.material3.Icon(
                imageVector = leading,
                contentDescription = null,
                tint = if (enabled) Ink else Muted,
                modifier = Modifier.size(18.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
        }
        Text(
            text = text,
            color = if (enabled) Ink else Muted,
            style = MaterialTheme.typography.labelLarge,
            fontSize = 15.sp
        )
    }
}

@Composable
fun TextPill(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color = Mist
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(if (selected) Amber else Color.White.copy(alpha = 0.07f))
            .border(
                1.dp,
                if (selected) Color.Transparent else Color.White.copy(alpha = 0.10f),
                RoundedCornerShape(50)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 7.dp)
    ) {
        Text(
            text = text,
            color = if (selected) Ink else tint,
            style = MaterialTheme.typography.labelLarge,
            fontSize = 12.sp
        )
    }
}

// ---------------------------------------------------------------- layout

@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            color = Mist,
            style = MaterialTheme.typography.titleMedium,
            fontSize = 14.sp,
            modifier = Modifier.weight(1f)
        )
        trailing?.invoke()
    }
}

@Composable
fun StatChip(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    accent: Color = Amber
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.45f))
            .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            androidx.compose.material3.Icon(
                imageVector = icon,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(13.dp)
            )
            Spacer(modifier = Modifier.width(5.dp))
        }
        Text(
            text = text,
            color = Mist,
            style = MaterialTheme.typography.labelMedium,
            fontSize = 11.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// ---------------------------------------------------------------- sliders

@Composable
fun HaloSlider(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    modifier: Modifier = Modifier,
    valueLabel: String? = null,
    onChange: (Float) -> Unit
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = label,
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
                fontSize = 12.sp
            )
            Text(
                text = valueLabel ?: percentLabel(value, range),
                color = if (kotlin.math.abs(value) > 0.001f) Amber else Muted,
                style = MaterialTheme.typography.labelMedium,
                fontSize = 12.sp
            )
        }
        Slider(
            value = value,
            onValueChange = onChange,
            valueRange = range,
            colors = SliderDefaults.colors(
                thumbColor = Amber,
                activeTrackColor = Amber,
                inactiveTrackColor = Color.White.copy(alpha = 0.14f)
            ),
            modifier = Modifier.height(28.dp)
        )
    }
}

private fun percentLabel(value: Float, range: ClosedFloatingPointRange<Float>): String {
    val span = range.endInclusive - range.start
    if (span <= 0f) return "0"
    val ratio = ((value - range.start) / span * 100f).roundToInt().coerceIn(0, 100)
    return "$ratio%"
}

// ---------------------------------------------------------------- toggles

@Composable
fun ToggleCard(
    title: String,
    subtitle: String,
    on: Boolean,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accent: Color = Amber
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, label = "toggle-press")
    Row(
        modifier = modifier
            .scale(scale)
            .clip(RoundedCornerShape(18.dp))
            .background(if (on) accent.copy(alpha = 0.14f) else PanelHigh)
            .border(
                1.dp,
                if (on) accent.copy(alpha = 0.75f) else Hairline,
                RoundedCornerShape(18.dp)
            )
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick
            )
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                color = if (on) accent else Mist,
                style = MaterialTheme.typography.titleSmall,
                fontSize = 13.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = subtitle,
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
                fontSize = 11.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
        Spacer(modifier = Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .size(26.dp)
                .clip(CircleShape)
                .background(if (on) accent else Color.White.copy(alpha = 0.06f)),
            contentAlignment = Alignment.Center
        ) {
            androidx.compose.material3.Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (on) Ink else Muted,
                modifier = Modifier.size(15.dp)
            )
        }
    }
}

@Composable
fun SettingRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Panel)
            .clickable { onCheckedChange(!checked) }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                color = Mist,
                style = MaterialTheme.typography.titleSmall,
                fontSize = 13.sp
            )
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    color = Muted,
                    style = MaterialTheme.typography.bodySmall,
                    fontSize = 11.sp
                )
            }
        }
        Spacer(modifier = Modifier.width(10.dp))
        Box(
            modifier = Modifier
                .width(42.dp)
                .height(24.dp)
                .clip(RoundedCornerShape(50))
                .background(if (checked) Amber else Color.White.copy(alpha = 0.10f))
                .clickable(role = Role.Switch) { onCheckedChange(!checked) }
                .padding(3.dp),
            contentAlignment = if (checked) Alignment.CenterEnd else Alignment.CenterStart
        ) {
            Box(
                modifier = Modifier
                    .size(18.dp)
                    .clip(CircleShape)
                    .background(if (checked) Ink else Muted)
            )
        }
    }
}

// --------------------------------------------------------------- snackbar

@Composable
fun HaloSnackbar(
    message: String,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp, vertical = 18.dp),
        contentAlignment = Alignment.Center
    ) {
        AnimatedVisibility(
            visible = message.isNotBlank(),
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically()
        ) {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(InkSoft.copy(alpha = 0.94f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(50))
                    .padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                Text(
                    text = message,
                    color = Mist,
                    style = MaterialTheme.typography.labelLarge,
                    fontSize = 13.sp
                )
            }
        }
    }
}

// -------------------------------------------------------------- overlays

@Composable
fun BusyOverlay(label: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 0.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(50))
                .background(InkSoft.copy(alpha = 0.92f))
                .border(1.dp, Color.White.copy(alpha = 0.10f), RoundedCornerShape(50))
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            androidx.compose.material3.CircularProgressIndicator(
                color = Amber,
                strokeWidth = 2.dp,
                modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = label,
                color = Mist,
                style = MaterialTheme.typography.labelLarge,
                fontSize = 12.sp
            )
        }
    }
}

fun Modifier.haloClick(enabled: Boolean = true, onClick: () -> Unit): Modifier =
    this.clickable(
        interactionSource = MutableInteractionSource(),
        indication = null,
        enabled = enabled,
        onClick = onClick
    )
