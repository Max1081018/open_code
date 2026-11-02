package com.example.camera.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val Ink = Color(0xFF08080A)
val Panel = Color(0xFF121216)
val PanelHigh = Color(0xFF1C1C22)
val Amber = Color(0xFFFFC857)
val Mist = Color(0xFFEDEDF2)
val Muted = Color(0xFF9A9AA6)
val Hairline = Color(0xFF2A2A32)

private val HaloColors = darkColorScheme(
    primary = Amber,
    onPrimary = Color(0xFF1A1408),
    primaryContainer = Color(0xFF3A2F14),
    onPrimaryContainer = Amber,
    secondary = Mist,
    onSecondary = Ink,
    background = Ink,
    onBackground = Mist,
    surface = Panel,
    onSurface = Mist,
    surfaceVariant = PanelHigh,
    onSurfaceVariant = Muted,
    outline = Hairline,
    error = Color(0xFFFF6B6B),
    onError = Ink
)

private val HaloType = Typography(
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.4.sp),
    titleMedium = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.2.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, letterSpacing = 0.1.sp),
    labelLarge = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.4.sp),
    labelSmall = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.8.sp)
)

@Composable
fun HaloTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = HaloColors,
        typography = HaloType,
        content = content
    )
}
