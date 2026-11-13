package dev.rustmodforge.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.rustmodforge.core.report.FeatureStatus
import dev.rustmodforge.core.report.StepStatus

object Palette {
    val Ember = Color(0xFFF2994A)
    val Steel = Color(0xFF56CCF2)
    val Bg = Color(0xFF0E1116)
    val Surface = Color(0xFF161B22)
    val SurfaceHigh = Color(0xFF1F2630)
    val Text = Color(0xFFE8EDF5)
    val Muted = Color(0xFF8B95A5)
    val Good = Color(0xFF6FCF97)
    val Partial = Color(0xFFF2C94C)
    val Bad = Color(0xFFEB5757)
}

@Composable
fun ForgeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Palette.Ember, onPrimary = Color(0xFF1A1206), secondary = Palette.Steel, onSecondary = Color(0xFF04151C),
            background = Palette.Bg, onBackground = Palette.Text, surface = Palette.Surface, onSurface = Palette.Text,
            surfaceVariant = Palette.SurfaceHigh, onSurfaceVariant = Palette.Muted, error = Palette.Bad,
            primaryContainer = Color(0xFF3A2614), onPrimaryContainer = Palette.Ember,
            secondaryContainer = Color(0xFF12313D), onSecondaryContainer = Palette.Steel,
        ),
        content = content,
    )
}

@Composable
fun SectionCard(title: String, modifier: Modifier = Modifier, subtitle: String? = null, content: @Composable () -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp),
        colors = CardDefaults.cardColors(containerColor = Palette.Surface),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = Palette.Text)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = Palette.Muted)
            Spacer(Modifier.size(10.dp))
            content()
        }
    }
}

@Composable
fun Pill(text: String, color: Color, modifier: Modifier = Modifier) {
    Box(
        modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.16f)).padding(horizontal = 10.dp, vertical = 3.dp),
    ) { Text(text, color = color, fontSize = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1) }
}

fun FeatureStatus.color() = when (this) {
    FeatureStatus.IMPLEMENTED -> Palette.Good
    FeatureStatus.PARTIAL -> Palette.Partial
    FeatureStatus.UNSUPPORTED -> Palette.Bad
    FeatureStatus.NOT_APPLICABLE -> Palette.Muted
}

fun FeatureStatus.label() = when (this) {
    FeatureStatus.IMPLEMENTED -> "Implemented"
    FeatureStatus.PARTIAL -> "Partial"
    FeatureStatus.UNSUPPORTED -> "Unsupported"
    FeatureStatus.NOT_APPLICABLE -> "N/A"
}

fun StepStatus.color() = when (this) {
    StepStatus.PASSED -> Palette.Good
    StepStatus.FAILED -> Palette.Bad
    StepStatus.SKIPPED -> Palette.Muted
    StepStatus.NOT_RUN -> Palette.Partial
}

@Composable
fun KeyValue(key: String, value: String, mono: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.Top) {
        Text(key, color = Palette.Muted, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.width(120.dp))
        Text(value, color = Palette.Text, style = MaterialTheme.typography.bodyMedium, fontFamily = if (mono) FontFamily.Monospace else null,
            modifier = Modifier.weight(1f))
    }
}

@Composable
fun Bullet(text: String, color: Color = Palette.Text) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("•", color = Palette.Ember)
        Text(text, color = color, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
fun MonoLine(text: String) {
    Text(text, fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = Palette.Text, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

fun bytes(n: Long): String = when {
    n >= 1L shl 30 -> "%.1f GiB".format(n / (1L shl 30).toDouble())
    n >= 1L shl 20 -> "%.1f MiB".format(n / (1L shl 20).toDouble())
    n >= 1L shl 10 -> "%.1f KiB".format(n / 1024.0)
    else -> "$n B"
}
