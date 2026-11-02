package com.example.camera.ui

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke

enum class Glyph {
    Flash,
    Timer,
    Grid,
    Flip,
    Gallery,
    Close,
    Check,
    Reset,
    Share,
    Trash,
    Sliders,
    Spark
}

/**
 * Icons are drawn with Canvas primitives instead of an icon font so the app has
 * no extra dependency and every control can be themed and animated freely.
 */
@Composable
fun GlyphIcon(
    kind: Glyph,
    tint: Color,
    modifier: Modifier = Modifier
) {
    Canvas(modifier) { drawGlyph(kind, tint) }
}

private fun DrawScope.unit(v: Float): Float = size.minDimension * v / 24f

private fun DrawScope.at(x: Float, y: Float): Offset = Offset(unit(x), unit(y))

private fun DrawScope.polygon(vararg coords: Float, color: Color) {
    if (coords.size < 6) return
    val path = Path()
    var i = 0
    while (i + 1 < coords.size) {
        val p = at(coords[i], coords[i + 1])
        if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
        i += 2
    }
    path.close()
    drawPath(path, color)
}

private fun DrawScope.strokeLine(x1: Float, y1: Float, x2: Float, y2: Float, color: Color, width: Float = 1.9f) {
    drawLine(
        color = color,
        start = at(x1, y1),
        end = at(x2, y2),
        strokeWidth = unit(width),
        cap = StrokeCap.Round
    )
}

private fun DrawScope.ring(cx: Float, cy: Float, r: Float, color: Color, width: Float = 1.9f) {
    drawCircle(
        color = color,
        radius = unit(r),
        center = at(cx, cy),
        style = Stroke(width = unit(width))
    )
}

private fun DrawScope.drawGlyph(kind: Glyph, tint: Color) {
    when (kind) {
        Glyph.Flash -> polygon(
            13f, 2f,
            4.5f, 13.5f,
            10.5f, 13.5f,
            9f, 22f,
            19.5f, 10f,
            12.5f, 10f,
            color = tint
        )

        Glyph.Timer -> {
            ring(12f, 13.5f, 8f, tint)
            strokeLine(12f, 9f, 12f, 14f, tint)
            strokeLine(12f, 14f, 15.5f, 16f, tint)
            strokeLine(9.5f, 2.5f, 14.5f, 2.5f, tint, 2.1f)
        }

        Glyph.Grid -> {
            drawRoundRect(
                color = tint,
                topLeft = at(3.5f, 3.5f),
                size = Size(unit(17f), unit(17f)),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(unit(3f), unit(3f)),
                style = Stroke(width = unit(1.7f))
            )
            strokeLine(12f, 4f, 12f, 20f, tint, 1.3f)
            strokeLine(4f, 12f, 20f, 12f, tint, 1.3f)
        }

        Glyph.Flip -> {
            strokeLine(4f, 8.5f, 18f, 8.5f, tint)
            polygon(18f, 5.5f, 22f, 8.5f, 18f, 11.5f, color = tint)
            strokeLine(20f, 15.5f, 6f, 15.5f, tint)
            polygon(6f, 12.5f, 2f, 15.5f, 6f, 18.5f, color = tint)
        }

        Glyph.Gallery -> {
            drawRoundRect(
                color = tint,
                topLeft = at(3f, 4.5f),
                size = Size(unit(18f), unit(15f)),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(unit(2.5f), unit(2.5f)),
                style = Stroke(width = unit(1.8f))
            )
            drawCircle(color = tint, radius = unit(1.5f), center = at(8f, 9.5f))
            strokeLine(5f, 17f, 10f, 12f, tint, 1.6f)
            strokeLine(10f, 12f, 14f, 16f, tint, 1.6f)
            strokeLine(14f, 16f, 17f, 13f, tint, 1.6f)
            strokeLine(17f, 13f, 20f, 16f, tint, 1.6f)
        }

        Glyph.Close -> {
            strokeLine(6f, 6f, 18f, 18f, tint, 2.1f)
            strokeLine(18f, 6f, 6f, 18f, tint, 2.1f)
        }

        Glyph.Check -> {
            strokeLine(4.5f, 12.5f, 9.5f, 17.5f, tint, 2.2f)
            strokeLine(9.5f, 17.5f, 19.5f, 6.5f, tint, 2.2f)
        }

        Glyph.Reset -> {
            drawArc(
                color = tint,
                startAngle = 200f,
                sweepAngle = 280f,
                useCenter = false,
                topLeft = at(4f, 4f),
                size = Size(unit(16f), unit(16f)),
                style = Stroke(width = unit(1.9f), cap = StrokeCap.Round)
            )
            polygon(13f, 2f, 20f, 4.5f, 15.5f, 8.5f, color = tint)
        }

        Glyph.Share -> {
            strokeLine(8f, 11f, 16f, 7f, tint, 1.7f)
            strokeLine(8f, 13f, 16f, 17f, tint, 1.7f)
            drawCircle(color = tint, radius = unit(2.2f), center = at(6f, 12f))
            drawCircle(color = tint, radius = unit(2.2f), center = at(17.5f, 5.8f))
            drawCircle(color = tint, radius = unit(2.2f), center = at(17.5f, 18.2f))
        }

        Glyph.Trash -> {
            strokeLine(4f, 6.5f, 20f, 6.5f, tint, 1.9f)
            strokeLine(9.5f, 3.5f, 14.5f, 3.5f, tint, 1.9f)
            strokeLine(6.5f, 6.5f, 7.5f, 20.5f, tint, 1.9f)
            strokeLine(17.5f, 6.5f, 16.5f, 20.5f, tint, 1.9f)
            strokeLine(7.5f, 20.5f, 16.5f, 20.5f, tint, 1.9f)
        }

        Glyph.Sliders -> {
            strokeLine(3.5f, 7f, 20.5f, 7f, tint, 1.7f)
            strokeLine(3.5f, 12f, 20.5f, 12f, tint, 1.7f)
            strokeLine(3.5f, 17f, 20.5f, 17f, tint, 1.7f)
            drawCircle(color = tint, radius = unit(2.1f), center = at(9f, 7f))
            drawCircle(color = tint, radius = unit(2.1f), center = at(15f, 12f))
            drawCircle(color = tint, radius = unit(2.1f), center = at(11f, 17f))
        }

        Glyph.Spark -> polygon(
            12f, 2f,
            14.2f, 9.8f,
            22f, 12f,
            14.2f, 14.2f,
            12f, 22f,
            9.8f, 14.2f,
            2f, 12f,
            9.8f, 9.8f,
            color = tint
        )
    }
}
