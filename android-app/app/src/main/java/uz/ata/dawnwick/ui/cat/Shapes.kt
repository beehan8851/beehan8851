package uz.ata.dawnwick.ui.cat

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.nativeCanvas
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/** The shapes the brand art is built from, as the iOS app draws them. */
object Shapes {
    fun ellipse(x: Float, y: Float, w: Float, h: Float) = Path().apply { addOval(Rect(x, y, x + w, y + h)) }

    fun circle(c: Offset, r: Float) = Path().apply { addOval(Rect(c, r)) }

    fun roundedRect(x: Float, y: Float, w: Float, h: Float, r: Float) =
        Path().apply { addRoundRect(RoundRect(Rect(x, y, x + w, y + h), CornerRadius(r, r))) }

    fun rect(x: Float, y: Float, w: Float, h: Float) = Path().apply { addRect(Rect(x, y, x + w, y + h)) }

    fun subtract(a: Path, b: Path) = Path.combine(PathOperation.Difference, a, b)
    fun union(a: Path, b: Path) = Path.combine(PathOperation.Union, a, b)
    fun intersect(a: Path, b: Path) = Path.combine(PathOperation.Intersect, a, b)

    fun Path.shifted(dx: Float, dy: Float) = Path().also { it.addPath(this, Offset(dx, dy)) }

    /** A rounded square-ish ellipse, wider at the bottom when `flare` > 0. */
    fun squircle(c: Offset, a: Float, b: Float, exponent: Float = 2.5f, flare: Float = 0f): Path {
        val p = Path()
        val steps = 160
        val e = 2.0 / exponent
        for (i in 0 until steps) {
            val th = i.toDouble() / steps * 2 * PI
            val ct = cos(th)
            val st = sin(th)
            var x = a * (abs(ct).pow(e) * if (ct < 0) -1 else 1).toFloat()
            val y = b * (abs(st).pow(e) * if (st < 0) -1 else 1).toFloat()
            x *= 1 + flare * (y / b)
            if (i == 0) p.moveTo(c.x + x, c.y + y) else p.lineTo(c.x + x, c.y + y)
        }
        p.close()
        return p
    }

    /** A polygon with every corner rounded to `radius`: the tangent arcs of CoreGraphics' `addArc(tangent1End:…)`. */
    fun roundedPolygon(points: List<Offset>, radius: Float): Path {
        val p = Path()
        val n = points.size
        if (n < 3) return p
        p.moveTo((points[n - 1].x + points[0].x) / 2, (points[n - 1].y + points[0].y) / 2)
        for (i in 0 until n) {
            val prev = points[(i - 1 + n) % n]
            val corner = points[i]
            val next = points[(i + 1) % n]
            val v1 = unit(prev - corner)
            val v2 = unit(next - corner)
            val cosA = (v1.x * v2.x + v1.y * v2.y).coerceIn(-1f, 1f)
            val angle = acos(cosA)
            if (radius <= 0f || angle < 1e-4f || PI - angle < 1e-4) {
                p.lineTo(corner.x, corner.y)
                continue
            }
            val distance = radius / tan(angle / 2)
            val t1 = corner + v1 * distance
            val t2 = corner + v2 * distance
            val bisector = unit(v1 + v2)
            val center = corner + bisector * (radius / sin(angle / 2))
            val a1 = Math.toDegrees(atan2((t1.y - center.y).toDouble(), (t1.x - center.x).toDouble())).toFloat()
            val a2 = Math.toDegrees(atan2((t2.y - center.y).toDouble(), (t2.x - center.x).toDouble())).toFloat()
            var sweep = a2 - a1
            while (sweep > 180f) sweep -= 360f
            while (sweep <= -180f) sweep += 360f
            p.lineTo(t1.x, t1.y)
            p.arcTo(Rect(center, radius), a1, sweep, false)
        }
        p.close()
        return p
    }

    private fun unit(v: Offset): Offset {
        val d = v.getDistance()
        return if (d == 0f) Offset.Zero else v / d
    }

    /** A crescent between two arcs through the same two corners; `sag` < 0 bows it upwards. */
    fun sliver(c: Offset, halfWidth: Float, sag: Float, thickness: Float): Path {
        val l = halfWidth
        val direction = if (sag < 0) -1f else 1f
        val s1 = max(abs(sag), 1f)
        val s2 = min(max(s1 - thickness, 0.5f), s1 - 0.5f)
        val r1 = (s1 * s1 + l * l) / (2 * s1)
        val r2 = (s2 * s2 + l * l) / (2 * s2)
        val c1 = Offset(c.x, c.y + direction * (s1 - r1))
        val c2 = Offset(c.x, c.y + direction * (s2 - r2))
        return subtract(circle(c1, r1), circle(c2, r2))
    }

    /** The icon's four-point star. */
    fun sparkle(c: Offset, r: Float): Path {
        val w = r * 0.16f
        return Path().apply {
            moveTo(c.x, c.y - r)
            quadraticTo(c.x + w, c.y - w, c.x + r, c.y)
            quadraticTo(c.x + w, c.y + w, c.x, c.y + r)
            quadraticTo(c.x - w, c.y + w, c.x - r, c.y)
            quadraticTo(c.x - w, c.y - w, c.x, c.y - r)
            close()
        }
    }

    /** A paw print in `rect`: one won morning. */
    fun pawPrint(rect: Rect): Path {
        val s = min(rect.width, rect.height)
        val o = Offset(rect.center.x - s / 2, rect.center.y - s / 2)
        fun r(x: Float, y: Float, w: Float, h: Float) = Rect(o.x + x * s, o.y + y * s, o.x + (x + w) * s, o.y + (y + h) * s)
        return Path().apply {
            addPath(roundedPolygon(listOf(
                Offset(o.x + 0.50f * s, o.y + 0.43f * s), Offset(o.x + 0.80f * s, o.y + 0.80f * s),
                Offset(o.x + 0.50f * s, o.y + 0.96f * s), Offset(o.x + 0.20f * s, o.y + 0.80f * s),
            ), 0.17f * s))
            addOval(r(0.02f, 0.36f, 0.20f, 0.25f))
            addOval(r(0.21f, 0.08f, 0.21f, 0.27f))
            addOval(r(0.58f, 0.08f, 0.21f, 0.27f))
            addOval(r(0.78f, 0.36f, 0.20f, 0.25f))
        }
    }

    /** An open curve stroked `width` wide with round caps, as a shape (Compose has no `strokedPath`). */
    fun strokeOutline(curve: Path, width: Float, samples: Int = 48): Path {
        val measure = PathMeasure().apply { setPath(curve, false) }
        val length = measure.length
        val half = width / 2
        val left = ArrayList<Offset>()
        val right = ArrayList<Offset>()
        for (i in 0..samples) {
            val d = length * i / samples
            val pos = measure.getPosition(d)
            val tan = measure.getTangent(d)
            val normal = Offset(-tan.y, tan.x)
            left += pos + normal * half
            right += pos - normal * half
        }
        val band = Path().apply {
            moveTo(left[0].x, left[0].y)
            for (pt in left.drop(1)) lineTo(pt.x, pt.y)
            for (pt in right.reversed()) lineTo(pt.x, pt.y)
            close()
        }
        var result = union(band, circle(measure.getPosition(0f), half))
        result = union(result, circle(measure.getPosition(length), half))
        return result
    }

    /** `shape` grown by `radius` all round, by sweeping it round a circle. */
    fun dilate(shape: Path, radius: Float, directions: Int = 24): Path {
        var result = shape
        for (i in 0 until directions) {
            val a = i.toDouble() / directions * 2 * PI
            result = union(result, shape.shifted((cos(a) * radius).toFloat(), (sin(a) * radius).toFloat()))
        }
        return result
    }
}

/** A cubic Bézier with what the startled cat needs: points, normals and tufts of fur. */
class Cubic(val p0: Offset, val c1: Offset, val c2: Offset, val p3: Offset) {
    val path: Path get() = Path().apply { moveTo(p0.x, p0.y); cubicTo(c1.x, c1.y, c2.x, c2.y, p3.x, p3.y) }

    fun point(u: Float): Offset {
        val v = 1 - u
        val a = v * v * v; val b = 3 * v * v * u; val c = 3 * v * u * u; val d = u * u * u
        return Offset(a * p0.x + b * c1.x + c * c2.x + d * p3.x, a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    fun normal(u: Float, side: Float): Offset {
        val a = point(max(0f, u - 0.01f)); val b = point(min(1f, u + 0.01f))
        val dx = b.x - a.x; val dy = b.y - a.y
        val len = max(sqrt(dx * dx + dy * dy), 0.0001f)
        return Offset(side * dy / len, -side * dx / len)
    }

    fun flame(u: Float, side: Float, length: Float, halfWidth: Float, sweep: Float, along: Float = 0f): Path {
        val n = normal(u.coerceIn(0.01f, 0.99f), side)
        fun inward(p: Offset) = Offset(p.x - n.x * 4, p.y - n.y * 4)
        val a = inward(point(max(0f, u - halfWidth)))
        val b = inward(point(min(1f, u + halfWidth)))
        val foot = point(min(1f, u + sweep))
        val dir = point(min(1f, u + 0.01f)) - point(max(0f, u - 0.01f))
        val dirLen = max(dir.getDistance(), 0.0001f)
        val tip = Offset(foot.x + n.x * length + dir.x / dirLen * length * along, foot.y + n.y * length + dir.y / dirLen * length * along)
        val mid = point(u)
        return Path().apply {
            moveTo(a.x, a.y)
            quadraticTo(mid.x + n.x * length * 0.75f, mid.y + n.y * length * 0.75f, tip.x, tip.y)
            quadraticTo(b.x + n.x * length * 0.3f, b.y + n.y * length * 0.3f, b.x, b.y)
            close()
        }
    }
}

// MARK: - Drawing helpers

fun DrawScope.fill(path: Path, color: Color) = drawPath(path, color)

fun DrawScope.line(path: Path, color: Color, width: Float, cap: StrokeCap = StrokeCap.Round, join: StrokeJoin = StrokeJoin.Miter) =
    drawPath(path, color, style = Stroke(width = width, cap = cap, join = join))

/** Draws `block` moved to (x, y), turned by `degrees` and scaled, as SwiftUI's copied contexts do. */
inline fun DrawScope.at(x: Float, y: Float, degrees: Float = 0f, sx: Float = 1f, sy: Float = sx, block: DrawScope.() -> Unit) =
    withTransform({
        translate(x, y)
        if (degrees != 0f) rotate(degrees, pivot = Offset.Zero)
        if (sx != 1f || sy != 1f) scale(sx, sy, pivot = Offset.Zero)
    }, block)

private val glyphPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
    textAlign = android.graphics.Paint.Align.CENTER
    typeface = android.graphics.Typeface.DEFAULT_BOLD
}

/** A heavy glyph centred on `at`. */
fun DrawScope.glyph(text: String, at: Offset, size: Float, color: Color) = drawIntoCanvas {
    glyphPaint.textSize = size
    glyphPaint.color = android.graphics.Color.argb(
        (color.alpha * 255).toInt(), (color.red * 255).toInt(), (color.green * 255).toInt(), (color.blue * 255).toInt(),
    )
    it.nativeCanvas.drawText(text, at.x, at.y + size * 0.36f, glyphPaint)
}
