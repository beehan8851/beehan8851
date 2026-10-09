package uz.ata.dawnwick.ui.missions

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.clearAndSetSemantics
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.ui.cat.Shapes
import uz.ata.dawnwick.ui.cat.artClock

/**
 * A small moving picture of each mission, so the picker shows what you will do
 * rather than naming it: keys pressing, a phone shaking, steps walking up the tile,
 * a scan line over a code, a memory grid lighting in order, a line typing itself, a
 * stroke drawing itself, a ball jumping, a paw hopping. Still under reduced motion.
 */
enum class ArtTone {
    /** On an ink tile: paper lines, yolk accents. */
    ON_INK,
    /** On a yolk tile (the mission is chosen): ink lines, white accents. */
    ON_YOLK,
}

@Composable
fun MissionArt(kind: MissionKind, modifier: Modifier = Modifier, tone: ArtTone = ArtTone.ON_INK, animated: Boolean = true) {
    val still = uz.ata.dawnwick.ui.cat.reduceMotion() || !animated
    val t = artClock(!still)
    val time = if (still) MissionArtDrawing.restingTime(kind) else t
    Canvas(modifier.aspectRatio(72f / 48f).clearAndSetSemantics {}) {
        with(MissionArtDrawing) { draw(kind, tone, time) }
    }
}

object MissionArtDrawing {
    private const val W = 72f
    private const val H = 48f

    private class Ink(tone: ArtTone) {
        private val paper = Color(0xFFF4F2ED)
        private val yolk = Color(0xFFFFC629)
        private val inkC = Color(0xFF1B1A17)
        val line = if (tone == ArtTone.ON_INK) paper else inkC
        val accent = if (tone == ArtTone.ON_INK) yolk else Color.White
        val muted = if (tone == ArtTone.ON_INK) paper.copy(alpha = 0.2f) else inkC.copy(alpha = 0.16f)
        val onAccent = inkC
        val onLine = if (tone == ArtTone.ON_INK) inkC else yolk
    }

    /** The frame shown when nothing moves: the most telling moment of each loop. */
    fun restingTime(kind: MissionKind) = when (kind) {
        MissionKind.STEPS -> 1.7
        MissionKind.TYPING -> 1.2
        MissionKind.DRAW -> 1.6
        MissionKind.MEMORY -> 0.5
        MissionKind.JUMP -> 0.6
        MissionKind.CATCH_CAT -> 0.7
        else -> 0.35
    }

    fun DrawScope.draw(kind: MissionKind, tone: ArtTone, t: Double) {
        val k = min(size.width / W, size.height / H)
        val ink = Ink(tone)
        translate((size.width - W * k) / 2, (size.height - H * k) / 2) {
            scale(k, k, pivot = Offset.Zero) {
                when (kind) {
                    MissionKind.MATH -> math(ink, t)
                    MissionKind.SHAKE -> shake(ink, t)
                    MissionKind.STEPS -> steps(ink, t)
                    MissionKind.QR_CODE -> qr(ink, t)
                    MissionKind.MEMORY -> memory(ink, t)
                    MissionKind.TYPING -> typing(ink, t)
                    MissionKind.DRAW -> drawing(ink, t)
                    MissionKind.JUMP -> jump(ink, t)
                    MissionKind.CATCH_CAT -> catchCat(ink, t)
                }
            }
        }
    }

    private fun phase(t: Double, cycle: Double) = t % cycle
    private fun bump(p: Double, start: Double, length: Double) = if (p >= start && p < start + length) sin((p - start) / length * PI) else 0.0
    private fun DrawScope.round(x: Float, y: Float, w: Float, h: Float, r: Float, color: Color) =
        drawRoundRect(color, Offset(x, y), Size(w, h), CornerRadius(r, r))

    private fun DrawScope.key(cx: Float, cy: Float, side: Float, angle: Float, press: Double, fill: Color, glyph: String, glyphColor: Color) {
        withTransform({
            translate(cx, cy + press.toFloat() * 2)
            rotate(angle, Offset.Zero)
            scale(1 - press.toFloat() * 0.1f, 1 - press.toFloat() * 0.1f, Offset.Zero)
        }) {
            round(-side / 2, -side / 2, side, side, side * 0.26f, fill)
            // Text in design units: the canvas is already scaled.
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = glyphColor.toArgb(); textSize = side * 0.62f; textAlign = Paint.Align.CENTER
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }
            val fm = paint.fontMetrics
            drawContext.canvas.nativeCanvas.drawText(glyph, 0f, -(fm.ascent + fm.descent) / 2, paint)
        }
    }

    private fun DrawScope.math(ink: Ink, t: Double) {
        val p = phase(t, 1.6)
        key(24f, 24f, 32f, -9f, bump(p, 0.05, 0.3), ink.accent, "÷", ink.onAccent)
        key(51f, 27f, 27f, 9f, bump(p, 0.85, 0.3), ink.line, "+", ink.onLine)
    }

    private fun DrawScope.shake(ink: Ink, t: Double) {
        val p = phase(t, 1.8)
        val burst = if (p < 0.75) 1 - p / 0.75 else 0.0
        val angle = (sin(p * 2 * PI * 5.5) * 15 * burst).toFloat()
        for (side in listOf(-1f, 1f)) {
            listOf(19f, 26f).forEachIndexed { i, r ->
                drawArc(ink.accent.copy(alpha = (burst * if (i == 0) 1.0 else 0.55).toFloat()),
                    startAngle = if (side > 0) -28f else 152f, sweepAngle = 56f, useCenter = false,
                    topLeft = Offset(36 - r, 24 - r), size = Size(r * 2, r * 2), style = Stroke(2.6f, cap = StrokeCap.Round))
            }
        }
        withTransform({ translate(36f, 24f); rotate(angle, Offset.Zero) }) {
            drawRoundRect(ink.line, Offset(-10f, -17f), Size(20f, 34f), CornerRadius(5.5f), style = Stroke(3f))
            round(-3.5f, -13f, 7f, 2.4f, 1.2f, ink.line)
        }
    }

    private fun DrawScope.steps(ink: Ink, t: Double) {
        val p = phase(t, 2.6)
        val prints = listOf(Triple(14f, 36f, true), Triple(28f, 30f, false), Triple(40f, 20f, true), Triple(54f, 14f, false))
        val shown = min(prints.size, (p / 0.45).toInt() + 1)
        val fade = (if (p > 2.2) 1 - (p - 2.2) / 0.4 else 1.0).toFloat()
        prints.take(shown).forEachIndexed { i, (x, y, left) ->
            val newest = i == shown - 1
            val color = (if (newest) ink.accent else ink.line.copy(alpha = 0.35f + 0.15f * i)).let { it.copy(alpha = it.alpha * fade) }
            withTransform({ translate(x, y); rotate(28f, Offset.Zero) }) {
                val dx = if (left) -2f else 2f
                drawOval(color, Offset(-4.2f + dx, -9f), Size(8.4f, 11f))
                drawOval(color, Offset(-3.2f + dx, 3f), Size(6.4f, 6f))
            }
        }
    }

    private fun DrawScope.qr(ink: Ink, t: Double) {
        val p = phase(t, 2.0)
        val ox = 21f
        val oy = 7f
        val side = 34f
        for ((cx, cy) in listOf(0f to 0f, side - 11 to 0f, 0f to side - 11)) {
            drawRoundRect(ink.line, Offset(ox + cx + 1.25f, oy + cy + 1.25f), Size(8.5f, 8.5f), CornerRadius(2f), style = Stroke(2.5f))
            round(ox + cx + 3.6f, oy + cy + 3.6f, 3.8f, 3.8f, 1f, ink.line)
        }
        val modules = listOf(15f to 2f, 19f to 6f, 15f to 10f, 2f to 15f, 8f to 15f, 15f to 15f, 23f to 15f, 28f to 19f,
            19f to 23f, 15f to 28f, 23f to 28f, 28f to 28f, 30f to 24f)
        for ((x, y) in modules) round(ox + x, oy + y, 3.6f, 3.6f, 0.8f, ink.line.copy(alpha = 0.75f))
        val y = oy + 2 + (side - 4) * (0.5 - 0.5 * cos(p / 2.0 * 2 * PI)).toFloat()
        round(ox - 4, y - 1.4f, side + 8, 2.8f, 1.4f, ink.accent)
    }

    private fun DrawScope.memory(ink: Ink, t: Double) {
        val order = listOf(0, 4, 2, 5, 1, 3)
        val lit = order[(phase(t, 2.7) / 0.45).toInt() % order.size]
        val tile = 14f
        val gap = 5f
        val ox = (W - (tile * 3 + gap * 2)) / 2
        for (i in 0 until 6) {
            var x = ox + (i % 3) * (tile + gap)
            var y = 7f + (i / 3) * (tile + gap)
            var s = tile
            if (i == lit) { x -= 1; y -= 1; s += 2 }
            round(x, y, s, s, 4f, if (i == lit) ink.accent else ink.muted)
        }
    }

    private fun DrawScope.typing(ink: Ink, t: Double) {
        val p = phase(t, 2.6)
        val typed = min(p / 1.8, 1.0).toFloat()
        val barX = 10f
        val barW = 52f
        round(barX, 6f, barW, 8f, 2.5f, ink.muted)
        val filled = barW * typed
        if (filled > 1) round(barX, 6f, filled, 8f, 2.5f, ink.line.copy(alpha = 0.9f))
        val cursorOn = p < 1.8 || sin(p * 2 * PI * 2) > 0
        if (cursorOn) drawRect(ink.accent, Offset(min(barX + filled + 1.5f, barX + barW + 1.5f), 3.5f), Size(2.4f, 13f))
        val keys = (0 until 5).map { Rect(Offset(10 + it * 10.75f, 22f), Size(8.5f, 8.5f)) } +
            listOf(Rect(Offset(10f, 33.5f), Size(8.5f, 8.5f)), Rect(Offset(21.5f, 33.5f), Size(29f, 8.5f)), Rect(Offset(53.5f, 33.5f), Size(8.5f, 8.5f)))
        val pressed = if (p < 1.8) listOf(2, 5, 0, 6, 3, 1, 7, 4)[(p / 0.16).toInt() % 8] else -1
        keys.forEachIndexed { i, r -> round(r.left, r.top, r.width, r.height, 2.4f, if (i == pressed) ink.accent else ink.muted) }
    }

    private fun DrawScope.drawing(ink: Ink, t: Double) {
        val p = phase(t, 2.8)
        val stroke = Path().apply {
            moveTo(9f, 34f)
            cubicTo(12f, 18f, 20f, 10f, 28f, 12f)
            cubicTo(36f, 14f, 32f, 34f, 40f, 34f)
            cubicTo(48f, 34f, 52f, 12f, 63f, 14f)
        }
        val progress = min(p / 1.6, 1.0).toFloat()
        val fade = (if (p > 2.3) maxOf(0.0, 1 - (p - 2.3) / 0.5) else 1.0).toFloat()
        val style = Stroke(3.6f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawPath(stroke, ink.muted.copy(alpha = ink.muted.alpha * fade), style = style)
        val measure = PathMeasure().apply { setPath(stroke, false) }
        val drawn = Path()
        measure.getSegment(0f, measure.length * progress, drawn, true)
        drawPath(drawn, ink.accent.copy(alpha = fade), style = style)
        val tip = measure.getPosition(measure.length * progress)
        drawCircle(ink.line.copy(alpha = fade), 3.4f, tip)
    }

    private fun DrawScope.jump(ink: Ink, t: Double) {
        val p = phase(t, 1.15) / 1.15
        val height = (4 * p * (1 - p)).toFloat()
        val landing = if (p < 0.08 || p > 0.92) 1f else 0f
        round(16f, 42f, 40f, 2.4f, 1.2f, ink.muted)
        val sw = 16 * (1 - 0.45f * height)
        drawOval(ink.line.copy(alpha = 0.22f * (1 - 0.6f * height)), Offset(36 - sw / 2, 39.5f), Size(sw, 3.2f))
        val r = 8.5f
        val sx = 1 + 0.18f * landing
        val sy = 1 - 0.18f * landing
        val cy = 41 - r * sy - height * 26
        drawOval(ink.accent, Offset(36 - r * sx, cy - r * sy), Size(r * 2 * sx, r * 2 * sy))
    }

    /** A paw print hopping from one side of a fold to the other, and a tap ring where it sits. */
    private fun DrawScope.catchCat(ink: Ink, t: Double) {
        val p = phase(t, 2.0) / 2.0
        drawLine(ink.muted, Offset(36f, 8f), Offset(36f, 42f), 2f, cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3f, 4f)))
        val left = Offset(20f, 30f)
        val right = Offset(52f, 30f)
        fun leap(from: Offset, to: Offset, u: Double): Offset {
            val e = (u * u * (3 - 2 * u)).toFloat()
            return Offset(from.x + (to.x - from.x) * e, from.y + (to.y - from.y) * e - sin(u * PI).toFloat() * 18)
        }
        val (at, sitting) = when {
            p < 0.35 -> left to p / 0.35
            p < 0.5 -> leap(left, right, (p - 0.35) / 0.15) to -1.0
            p < 0.85 -> right to (p - 0.5) / 0.35
            else -> leap(right, left, (p - 0.85) / 0.15) to -1.0
        }
        if (sitting >= 0) {
            val ring = bump(sitting, 0.3, 0.5)
            if (ring > 0) drawCircle(ink.line.copy(alpha = (0.5 * ring).toFloat()), 9 + ring.toFloat() * 6, at, style = Stroke(1.6f))
        }
        drawPath(Shapes.pawPrint(Rect(Offset(at.x - 9, at.y - 9), Size(18f, 18f))), ink.accent)
    }
}
