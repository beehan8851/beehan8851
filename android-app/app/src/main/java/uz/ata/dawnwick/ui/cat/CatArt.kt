package uz.ata.dawnwick.ui.cat

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import uz.ata.dawnwick.ui.cat.Shapes.shifted

enum class CatMood { SLEEPING, AWAKE, PROUD, GRUMPY, RINGING, STARTLED, SAD, YAWNING }

/** What the cat is drawn on: decides the colour of the zzz, whiskers and marks. */
enum class CatGround { LIGHT, DARK }

enum class CatDressing { NONE, COLLAR, MEDAL }

object CatPalette {
    val fur = Color(0xFFFFFCF8)
    val furShade = Color(0xFFEDE5D8)
    val furDeep = Color(0xFFD9CDBB)
    val earInner = Color(0xFFF7A38E)
    val nose = Color(0xFFF08B76)
    val ink = Color(0xFF1C1A17)
    val blush = Color(0xFFF59A97)
    val moon = Color(0xFFFFC629)
    val moonLight = Color(0xFFFFE27F)
    val moonShade = Color(0xFFE9A400)
    val tear = Color(0xFF9FD3F5)

    fun mark(ground: CatGround) = if (ground == CatGround.DARK) Color.White else ink
    fun sparkle(ground: CatGround) = if (ground == CatGround.DARK) moon else ink
}

private fun Color.a(opacity: Double) = copy(alpha = alpha * opacity.toFloat().coerceIn(0f, 1f))
private fun Color.a(opacity: Float) = copy(alpha = alpha * opacity.coerceIn(0f, 1f))
private fun s(x: Double) = sin(x).toFloat()
private fun o(x: Number, y: Number) = Offset(x.toFloat(), y.toFloat())

/**
 * The cat from the app icon, drawn in code in a fixed design space scaled to fit.
 * Flat shapes, one shade per surface, no outlines. A port of the iOS `CatArt`.
 */
object CatArt {
    fun designSize(mood: CatMood) = when (mood) {
        CatMood.SLEEPING -> Size(240f, 180f)
        CatMood.STARTLED -> Size(250f, 240f)
        else -> Size(200f, 222f)
    }

    fun aspectRatio(mood: CatMood) = designSize(mood).let { it.width / it.height }

    private fun ease(x: Double): Double { val c = x.coerceIn(0.0, 1.0); return c * c * (3 - 2 * c) }

    /** How far into a yawn the yawning cat is: a slow open, a hold, a close, a rest. */
    fun yawn(t: Double): Float {
        val phase = t % 5.2
        return when {
            phase < 0.55 -> ease(phase / 0.55)
            phase < 1.7 -> 1.0
            phase < 2.3 -> 1 - ease((phase - 1.7) / 0.6)
            else -> 0.0
        }.toFloat()
    }

    fun DrawScope.drawCat(
        mood: CatMood,
        ground: CatGround = CatGround.DARK,
        t: Double = 0.6,
        eyesWide: Boolean = false,
        dressing: CatDressing = CatDressing.NONE,
        petted: Float = 0f,
        lean: Float = 0f,
        purrSide: Float = 1f,
        /** The breath from outside, -1 (out) to 1 (in), for a cat that breathes with a pacer. */
        breath: Double? = null,
    ) {
        val design = designSize(mood)
        val k = min(size.width / design.width, size.height / design.height)
        at((size.width - design.width * k) / 2, (size.height - design.height * k) / 2, sx = k) {
            when (mood) {
                CatMood.SLEEPING -> sleeping(ground, t, petted, lean, breath)
                CatMood.STARTLED -> startled(ground, t)
                else -> sitting(mood, ground, t, eyesWide, dressing, petted, lean, purrSide)
            }
        }
    }

    // MARK: Poses

    private fun DrawScope.sleeping(ground: CatGround, t: Double, petted: Float = 0f, lean: Float = 0f, paced: Double? = null) {
        val breath = paced?.let { (-it * 2.2).toFloat() } ?: s(t * 2 * PI / 4.4)
        for (i in 0 until 3) {
            val phase = (t / 3.6 + i / 3.0) % 1
            val rise = phase * 24
            val fade = sin(phase * PI)
            glyph("z", o(176 + i * 16, 40 - i * 13 - rise), 11f + i * 4,
                CatPalette.mark(ground).a((if (ground == CatGround.DARK) 0.8 else 0.5) * fade))
        }
        // Stroked, it nuzzles into the hand without waking.
        at(104f, 80 + breath * 1.2f, -7f + lean * petted * 5) { head(CatMood.SLEEPING, ground, t, petted = petted) }
        at(124f, 103f, -15f) { moon() }

        val tail = Path().apply { moveTo(184f, 95f); cubicTo(214f, 96f, 228f, 132f, 207f, 146f) }
        val sway = s(t * 2 * PI / 5.2) * 2
        line(tail.shifted(sway, 0f), CatPalette.furShade, 13f)
        line(tail.shifted(sway - 1.2f, -1f), CatPalette.fur, 9f)

        paw(o(66, 126 + breath * 0.8f), Size(35f, 24f), -22f)
        paw(o(156, 111 + breath * 0.8f), Size(36f, 25f), -12f)

        purr(o(22, 64), -1f, petted, t, ground)
    }

    private fun DrawScope.sitting(
        mood: CatMood, ground: CatGround, t: Double, eyesWide: Boolean, dressing: CatDressing,
        petted: Float = 0f, lean: Float = 0f, away: Float = 1f,
    ) {
        val breath = s(t * 2 * PI / 3.4)
        val ringing = mood == CatMood.RINGING

        // Tail, behind the body, swaying from its root.
        val sway = if (ringing) s(t * 2 * PI / 0.9) * 9 else s(t * 2 * PI / 2.8) * 5
        val tailPath = Path().apply { moveTo(0f, 0f); cubicTo(48f, 0f, 52f, -50f, 30f, -78f) }
        at(if (ringing) 54f else 146f, 200f) {
            val flip = if (ringing) -1f else 1f
            if (mood == CatMood.SAD) {
                at(0f, 0f, 40 + sway * 0.2f, sx = 0.8f * flip, sy = 0.8f) {
                    line(tailPath, CatPalette.furShade, 18f)
                    line(tailPath.shifted(-2f, -1f), CatPalette.fur, 13f)
                }
            } else {
                at(0f, 0f, sx = flip, sy = 1f) {
                    at(0f, 0f, sway) {
                        line(tailPath, CatPalette.furShade, 18f)
                        line(tailPath.shifted(-2f, -1f), CatPalette.fur, 13f)
                    }
                }
            }
        }

        val tap = abs(s(t * 2 * PI / 0.62))
        val pawCenter = o(174, 104 - tap * 8)
        if (ringing) {
            val arm = Path().apply { moveTo(138f, 160f); quadraticTo(172f, 150f, pawCenter.x - 2, pawCenter.y + 8) }
            line(arm, CatPalette.furShade, 22f)
            line(arm.shifted(-1.5f, -1f), CatPalette.fur, 17f)
        }

        val body = Shapes.squircle(o(100, 166 - breath * 0.6f), 57f, 46f, 2.3f, 0.13f)
        fill(body, CatPalette.fur)
        fill(Shapes.subtract(body, body.shifted(8f, -7f)), CatPalette.furShade)

        paw(o(83, 207), Size(29f, 17f), 0f)
        if (!ringing) paw(o(117, 207), Size(29f, 17f), 0f)

        if (dressing != CatDressing.NONE) {
            line(Path().apply { moveTo(62f, 146f); quadraticTo(100f, 174f, 138f, 146f) }, CatPalette.ink, 7f)
        }

        val yawnAmount = if (mood == CatMood.YAWNING) yawn(t) else 0f
        val (lift, tilt) = when (mood) {
            CatMood.PROUD -> -3f to -4f
            CatMood.SAD -> 6f to 4f
            CatMood.YAWNING -> -4 * yawnAmount to -6 * yawnAmount
            else -> 0f to 0f
        }
        val wobble = if (ringing) s(t * 2 * PI / 0.62) * 2.5f else 0f
        // Stroked, it pushes its head into the hand.
        at(100f + lean * petted * 3, 97 + lift - breath, tilt + wobble + lean * petted * 9) { head(mood, ground, t, eyesWide, petted) }

        if (dressing != CatDressing.NONE) charm(o(100, 165 - breath * 0.6f), dressing == CatDressing.MEDAL)

        // The purr, on the side away from the hand.
        purr(o(100 + away * 62, 158), away, petted, t, ground)

        if (ringing) {
            paw(pawCenter, Size(30f, 28f), -12f, pads = true)
            listOf(o(22, -18), o(27, -2)).forEachIndexed { i, off ->
                val start = pawCenter + off
                line(Path().apply { moveTo(start.x, start.y); lineTo(start.x + 9, start.y + if (i == 0) -6 else 1) },
                    CatPalette.sparkle(ground).a(0.35f + 0.65f * tap), 3.5f)
            }
        }
        if (mood == CatMood.PROUD) {
            fill(Shapes.sparkle(o(168, 46), 11f), CatPalette.sparkle(ground))
            fill(Shapes.sparkle(o(34, 72), 6.5f), CatPalette.sparkle(ground).a(0.85f))
        }
    }

    /** Side on, back arched into a hoop, fur on end, the whole cat trembling. */
    private fun DrawScope.startled(ground: CatGround, t: Double) {
        val shiver = s(t * 2 * PI * 9) * 0.9f
        fun bristle(i: Int) = s(t * 2 * PI * 4 + i * 2.1) * 1.5f
        at(shiver, 18f) {
            listOf(o(18, 72) to -150.0, o(34, 46) to -120.0, o(62, 34) to -92.0, o(92, 40) to -64.0).forEachIndexed { i, (from, angle) ->
                val a = angle * PI / 180
                val length = (if (i % 2 == 0) 14f else 11f) * (1 + 0.18f * s(t * 2 * PI * 3 + i * 1.3))
                line(Path().apply { moveTo(from.x, from.y); lineTo(from.x + cos(a).toFloat() * length, from.y + sin(a).toFloat() * length) },
                    CatPalette.mark(ground).a(if (ground == CatGround.DARK) 0.85 else 0.75), 4f)
            }

            val tailCurve = Cubic(o(196, 110), o(236, 98), o(206, 58), o(226 + shiver * 2, 20))
            var tail = Shapes.strokeOutline(tailCurve.path, 17f)
            for (i in 0 until 9) {
                val u = 0.2f + i * 0.085f
                for (side in listOf(-1f, 1f)) {
                    tail = Shapes.union(tail, tailCurve.flame(u + if (side > 0) 0.04f else 0f, side,
                        12 + ((i + if (side > 0) 1 else 0) % 3) * 2.5f + bristle(i) * 0.6f, 0.055f, 0.07f))
                }
            }
            tail = Shapes.union(tail, tailCurve.flame(0.99f, 1f, 9f, 0.04f, 0f, 0.6f))
            tail = Shapes.union(tail, tailCurve.flame(0.99f, -1f, 9f, 0.04f, 0f, 0.6f))
            fill(tail, CatPalette.furShade)
            fill(Shapes.intersect(tail.shifted(-2f, -1.5f), tail), CatPalette.fur)

            fun leg(top: Offset, topWidth: Float, foot: Offset): Path {
                val shape = Shapes.roundedPolygon(listOf(
                    o(top.x - topWidth / 2, top.y), o(top.x + topWidth / 2, top.y), o(foot.x + 8, foot.y), o(foot.x - 8, foot.y)), 7f)
                return Shapes.union(shape, Shapes.ellipse(foot.x - 14, foot.y - 5, 27f, 14f))
            }
            var farHind = Path().apply {
                moveTo(168f, 104f); cubicTo(170f, 140f, 171f, 176f, 173f, 202f); lineTo(188f, 202f)
                cubicTo(190f, 168f, 200f, 140f, 202f, 112f); close()
            }
            farHind = Shapes.union(farHind, Shapes.ellipse(166f, 197f, 27f, 14f))
            for (far in listOf(leg(o(96, 130), 26f, o(92, 202)), farHind)) {
                fill(far, CatPalette.furShade)
                fill(Shapes.subtract(far, far.shifted(4f, -4f)), CatPalette.furDeep)
            }

            val back = Cubic(o(60, 146), o(58, 18), o(204, 8), o(214, 128))
            var body = Path().apply {
                moveTo(back.p0.x, back.p0.y)
                cubicTo(back.c1.x, back.c1.y, back.c2.x, back.c2.y, back.p3.x, back.p3.y)
                cubicTo(222f, 142f, 212f, 158f, 196f, 158f)
                cubicTo(168f, 96f, 116f, 96f, 90f, 160f)
                cubicTo(74f, 170f, 58f, 162f, back.p0.x, back.p0.y)
                close()
            }
            val fringe = floatArrayOf(0f, -3f, 2.5f, -1.5f, 3.5f, -2.5f, 1f, -3.5f, 2f, -1f, 3f, -2f, 0.5f, -2.5f, 1.5f, -1f, 2f, -2f, 1f)
            fringe.forEachIndexed { i, jitter ->
                val u = 0.16f + i * 0.044f
                val envelope = sin(PI * min(1f, max(0f, (u - 0.1f) / 0.9f))).toFloat()
                body = Shapes.union(body, back.flame(u, 1f, 7 + 13 * envelope + jitter + bristle(i), 0.03f, 0.032f))
            }
            val hind = Path().apply {
                moveTo(176f, 126f); cubicTo(184f, 150f, 190f, 180f, 191f, 204f); lineTo(207f, 204f)
                cubicTo(211f, 178f, 222f, 152f, back.p3.x, back.p3.y); close()
            }
            val fore = Path().apply {
                moveTo(90f, 134f); cubicTo(84f, 160f, 79f, 182f, 78f, 204f); lineTo(62f, 204f)
                cubicTo(60f, 182f, 55f, 162f, 58f, 148f); close()
            }
            body = Shapes.union(Shapes.union(body, hind), fore)
            fill(body, CatPalette.fur)
            fill(Shapes.subtract(body, body.shifted(5f, -6f)), CatPalette.furShade)
            for (c in listOf(o(197, 208), o(67, 208))) {
                val paw = Shapes.roundedRect(c.x - 14, c.y - 7, 27f, 13f, 6.5f)
                fill(paw, CatPalette.fur)
                fill(Shapes.subtract(paw, paw.shifted(1.5f, -3.5f)), CatPalette.furShade)
            }
            for (x in listOf(62f, 69f, 192f, 199f)) line(Path().apply { moveTo(x, 214f); lineTo(x, 210f) }, CatPalette.furDeep, 1.6f)

            at(60f, 124f, -8f, 0.64f) { head(CatMood.STARTLED, ground, t) }
        }
    }

    // MARK: Stretch

    /**
     * The stretch's design space. The hind paws stay put at the right; the front
     * reaches left as `reach` goes to 1.
     */
    val stretchDesignSize = Size(364f, 200f)

    /**
     * Side on, facing left, head turned to us: forelegs flat out in front, chest down,
     * rump up, tail high. `reach` 0…1 is how far the front has gone; `yawn` 0…1 how
     * wide the mouth is. `hunting`: the same shape is a cat about to pounce, or
     * running, or in the air — eyes wide on its prey, no yawn, the tail twitching.
     */
    fun DrawScope.drawStretch(ground: CatGround, t: Double, reach: Float, yawn: Float, hunting: Boolean = false) {
        val design = stretchDesignSize
        val k = min(size.width / design.width, size.height / design.height)
        at((size.width - design.width * k) / 2, (size.height - design.height * k) / 2, sx = k) {
            at(20f, 0f) { stretch(ground, t, reach, yawn, hunting) }
        }
    }

    private fun DrawScope.stretch(ground: CatGround, t: Double, reach: Float, yawn: Float, hunting: Boolean) {
        val e = 60 * reach.coerceIn(0f, 1f)
        fun front(x: Float, y: Float, share: Float) = Offset(x - e * share, y)

        val shadowLeft = front(86f, 0f, 1f).x - 30
        fill(Shapes.ellipse(shadowLeft, 183f, 308 - shadowLeft, 12f), if (ground == CatGround.DARK) Color.Black.a(0.35) else CatPalette.ink.a(0.1))

        val sway = if (hunting) s(t * 2 * PI / 0.45) * 5 else s(t * 2 * PI / 2.6) * 3
        val tail = Path().apply {
            moveTo(290f, 82f)
            cubicTo(318f, 74f, 330f, 46f, 322 + sway, 26f)
            quadraticTo(316 + sway, 6f, 302 + sway * 1.4f, 14f)
        }
        line(tail, CatPalette.furShade, 17f, join = StrokeJoin.Round)
        line(tail.shifted(-2f, -1f), CatPalette.fur, 12f, join = StrokeJoin.Round)

        fun foreleg(dx: Float, dy: Float): Path {
            val elbow = front(184 + dx, 178 + dy, 0.42f)
            val wrist = front(86 + dx, 181 + dy, 1f)
            val floor = 188 + dy
            val leg = Path().apply {
                moveTo(wrist.x, wrist.y - 5)
                cubicTo(wrist.x + 44, wrist.y - 6, elbow.x - 44, elbow.y - 17, elbow.x - 6, elbow.y - 16)
                cubicTo(elbow.x + 8, elbow.y - 15, elbow.x + 12, floor - 8, elbow.x + 6, floor - 3)
                quadraticTo(elbow.x + 3, floor, elbow.x - 4, floor)
                lineTo(wrist.x, floor)
                close()
            }
            return Shapes.union(leg, Shapes.roundedRect(wrist.x - 24, 173 + dy, 36f, 16f, 8f))
        }
        fun hindleg(dx: Float, dy: Float) = Path().apply {
            moveTo(244 + dx, 120 + dy)
            cubicTo(258 + dx, 142 + dy, 266 + dx, 166 + dy, 268 + dx, 184 + dy)
            lineTo(290 + dx, 184 + dy)
            cubicTo(290 + dx, 172 + dy, 292 + dx, 160 + dy, 296 + dx, 150 + dy)
            cubicTo(304 + dx, 132 + dy, 316 + dx, 110 + dy, 300 + dx, 92 + dy)
            close()
        }
        fun hindPaw(dx: Float, dy: Float) = Shapes.roundedRect(262 + dx, 174 + dy, 34f, 15f, 7.5f)

        for (far in listOf(foreleg(-16f, -3f), Shapes.union(hindleg(-18f, -2f), hindPaw(-18f, -2f)))) {
            fill(far, CatPalette.furShade)
            fill(Shapes.subtract(far, far.shifted(4f, -4f)), CatPalette.furDeep)
        }

        val nape = front(150f, 120f, 0.6f)
        val chest = front(182f, 172f, 0.48f)
        val c1 = front(196f, 128f, 0.35f)
        val c2 = front(212f, 170f, 0.3f)
        val c3 = front(150f, 176f, 0.55f)
        val c4 = front(128f, 140f, 0.6f)
        var body = Path().apply {
            moveTo(nape.x, nape.y)
            cubicTo(c1.x, c1.y, 226f, 62f, 268f, 60f)
            cubicTo(288f, 58f, 300f, 72f, 300f, 92f)
            lineTo(248f, 136f)
            cubicTo(230f, 152f, c2.x, c2.y, chest.x, chest.y)
            cubicTo(c3.x, c3.y, c4.x, c4.y, nape.x, nape.y)
            close()
        }
        body = Shapes.union(body, hindleg(0f, 0f))
        fill(body, CatPalette.fur)
        fill(Shapes.subtract(body, body.shifted(5f, -6f)), CatPalette.furShade)

        for (part in listOf(foreleg(0f, 0f), hindPaw(0f, 0f))) {
            fill(part, CatPalette.fur)
            fill(Shapes.subtract(part, part.shifted(1.5f, -3.5f)), CatPalette.furShade)
        }
        val wrist = front(86f, 181f, 1f)
        for (x in listOf(wrist.x - 17, wrist.x - 10, 272f, 279f)) {
            line(Path().apply { moveTo(x, 189f); lineTo(x, 184.5f) }, CatPalette.furDeep, 1.6f)
        }

        val headCenter = front(118f, 132f, 0.72f)
        if (hunting) {
            at(headCenter.x, headCenter.y + 4, -3f, 0.62f) { head(CatMood.AWAKE, ground, t, eyesWide = true) }
        } else {
            at(headCenter.x, headCenter.y - yawn * 3, -5f - 5f * yawn, 0.62f) { head(CatMood.YAWNING, ground, t, yawnAmount = yawn) }
        }
    }

    // MARK: Head

    /**
     * `petted`: being stroked, whatever its mood the cat shuts its eyes, content, and
     * lets its ears go; a sleeping cat only lets its ears go.
     */
    private fun DrawScope.head(mood: CatMood, ground: CatGround, t: Double, eyesWide: Boolean = false, petted: Float = 0f, yawnAmount: Float? = null) {
        val open = if (mood == CatMood.YAWNING) yawnAmount ?: yawn(t) else 0f
        // The face it makes: its own until the eyes have closed, then content.
        val face = if (petted > 0.5f && !eyesWide && mood != CatMood.SLEEPING) CatMood.PROUD else mood
        val (earTilt, earDrop) = when (mood) {
            CatMood.GRUMPY -> 34f to 8f
            CatMood.SLEEPING -> 30f to 5f
            CatMood.RINGING -> 8f to -4f
            CatMood.STARTLED -> 24f to 0f
            CatMood.SAD -> 40f to 6f
            CatMood.YAWNING -> 15 + 14 * open to 3 * open
            else -> 15f to 0f
        }
        val twitchPhase = t % 6.5
        val twitch = if (twitchPhase < 0.28) s(twitchPhase / 0.28 * PI) * 9 else 0f
        val earsLetGo = petted * 9
        ear(o(-41, -38 + earDrop + petted * 2), -earTilt - earsLetGo)
        ear(o(41, -38 + earDrop + petted * 2), earTilt + earsLetGo + twitch)

        for (side in listOf(-1f, 1f)) {
            for ((dy, reach) in listOf(-2f to -7f, 6f to 2f)) {
                line(Path().apply { moveTo(side * 58, 18 + dy); quadraticTo(side * 76, 16 + dy, side * 92, 18 + dy + reach) },
                    CatPalette.mark(ground).a(if (ground == CatGround.DARK) 0.75 else 0.3), 1.6f)
            }
        }

        val head = Shapes.squircle(Offset.Zero, 72f, 55f, 2.45f, 0.07f)
        fill(head, CatPalette.fur)
        fill(Shapes.subtract(head, head.shifted(9f, -10f)), CatPalette.furShade)

        val blush = when { face == CatMood.PROUD || petted > 0.5f -> 0.55; face == CatMood.SAD -> 0.22; else -> 0.36 }
        for (x in listOf(-45f, 45f)) fill(Shapes.ellipse(x - 8, 17f, 16f, 8f), CatPalette.blush.a(blush))

        eyes(face, t, eyesWide, open, squint = min(1f, petted * 2))

        if (face == CatMood.SAD && !eyesWide) {
            val phase = (t % 4.2) / 4.2
            val run = min(1.0, phase * 1.6).toFloat()
            val fade = if (phase < 0.75) 1.0 else max(0.0, 1 - (phase - 0.75) / 0.2)
            val c = o(-33, 18 + run * 16)
            val drop = Path().apply {
                moveTo(c.x, c.y - 7)
                quadraticTo(c.x + 3.4f, c.y - 3, c.x + 4, c.y + 1)
                arcTo(Rect(o(c.x, c.y + 1), 4f), 0f, 180f, false)
                quadraticTo(c.x - 3.4f, c.y - 3, c.x, c.y - 7)
            }
            fill(drop, CatPalette.tear.a(fade))
            fill(Shapes.ellipse(c.x - 2, c.y - 1, 1.8f, 2.4f), Color.White.a(0.8 * fade))
        }

        fill(Shapes.roundedPolygon(listOf(o(-5.5, 17.5), o(5.5, 17.5), o(0, 24)), 2.2f), CatPalette.nose)

        fun mouth(p: Path) = line(p, CatPalette.ink, 2.1f, join = StrokeJoin.Round)
        fun smile() = Path().apply { moveTo(-7f, 26.5f); quadraticTo(-3.6f, 32f, 0f, 25.5f); quadraticTo(3.6f, 32f, 7f, 26.5f) }
        when (mood) {
            CatMood.RINGING -> {
                val h = 5.5f + abs(s(t * 2 * PI / 0.62)) * 2.5f
                fill(Shapes.roundedRect(-6f, 26f, 12f, h, 5f), CatPalette.ink)
                fill(Shapes.ellipse(-3.5f, 26 + h - 4, 7f, 4f), CatPalette.nose)
            }
            CatMood.STARTLED -> {
                fill(Shapes.roundedRect(-10f, 27f, 20f, 13f, 6.5f), CatPalette.ink)
                fill(Shapes.ellipse(-5f, 34.5f, 10f, 5f), CatPalette.nose)
                for (x in listOf(-5.6f, 5.6f)) fill(Shapes.roundedPolygon(listOf(o(x - 2.6f, 27), o(x + 2.6f, 27), o(x, 32.5)), 0.6f), Color.White)
            }
            CatMood.SAD -> mouth(Path().apply { moveTo(-7f, 33f); quadraticTo(0f, 26f, 7f, 33f) })
            CatMood.YAWNING -> if (open > 0.08f) {
                val w = 10 + 10 * open
                val h = 4 + 20 * open
                fill(Shapes.ellipse(-w / 2, 25f, w, h), CatPalette.ink)
                fill(Shapes.ellipse(-w * 0.32f, 25 + h - h * 0.42f, w * 0.64f, h * 0.36f), CatPalette.nose)
            } else mouth(smile())
            CatMood.GRUMPY -> mouth(Path().apply { moveTo(-6f, 31f); quadraticTo(0f, 27.5f, 6f, 31f) })
            else -> mouth(smile())
        }
    }

    private fun DrawScope.ear(base: Offset, tilt: Float) = at(base.x, base.y, tilt) {
        fill(Shapes.roundedPolygon(listOf(o(-26, 12), o(26, 12), o(2, -40)), 9f), CatPalette.fur)
        fill(Shapes.roundedPolygon(listOf(o(-14, 9), o(15, 9), o(2, -24)), 5f), CatPalette.earInner)
    }

    private fun lid(e: Offset, left: Float, right: Float, top: Float) = Shapes.subtract(
        Shapes.rect(e.x - 12, e.y - 20, 24f, 40f),
        Shapes.roundedPolygon(listOf(o(e.x - 14, e.y - 20), o(e.x + 14, e.y - 20), o(e.x + 14, e.y + top + right), o(e.x - 14, e.y + top + left)), 0.1f),
    )

    internal fun DrawScope.eyes(mood: CatMood, t: Double, wide: Boolean, squeeze: Float, squint: Float = 0f) {
        val eyes = listOf(o(-27, 7), o(27, 7))
        if (wide) {
            for (e in eyes) {
                fill(Shapes.ellipse(e.x - 8, e.y - 10, 16f, 20f), CatPalette.ink)
                fill(Shapes.ellipse(e.x - 0.4f, e.y - 8.4f, 7.2f, 7.2f), Color.White)
                fill(Shapes.ellipse(e.x - 4.4f, e.y + 2.6f, 3f, 3f), Color.White.a(0.85))
            }
            return
        }
        when (mood) {
            CatMood.SLEEPING -> for (e in eyes) fill(Shapes.sliver(o(e.x, e.y + 1), 12.5f, 7f, 4.4f), CatPalette.ink)
            CatMood.YAWNING -> for (e in eyes) fill(Shapes.sliver(o(e.x, e.y + 2 + squeeze), 12 - squeeze, 6 - 2.5f * squeeze, 4.2f), CatPalette.ink)
            CatMood.SAD -> eyes.forEachIndexed { i, e ->
                val left = if (i == 0) 3.5f else -2.5f
                val right = if (i == 0) -2.5f else 3.5f
                fill(Shapes.intersect(Shapes.ellipse(e.x - 7.5f, e.y - 8, 15f, 17f), lid(e, left, right, -9f)), CatPalette.ink)
                fill(Shapes.ellipse(e.x + 0.6f, e.y - 3.4f, 4.8f, 4.8f), Color.White)
                fill(Shapes.ellipse(e.x - 4.6f, e.y + 2.4f, 3.2f, 3.2f), Color.White.a(0.85))
                val toNose = if (i == 0) 1f else -1f
                line(Path().apply { moveTo(e.x - toNose * 8, e.y - 13); quadraticTo(e.x, e.y - 14, e.x + toNose * 7, e.y - 19) }, CatPalette.ink, 2.4f)
            }
            CatMood.PROUD -> for (e in eyes) fill(Shapes.sliver(o(e.x, e.y + 6), 11.5f, -7.5f, 4.4f), CatPalette.ink)
            CatMood.STARTLED -> for (e in eyes) {
                fill(Shapes.ellipse(e.x - 10.5f, e.y - 11, 21f, 22f), CatPalette.ink)
                fill(Shapes.ellipse(e.x + 1.4f, e.y - 6.6f, 5.6f, 5.6f), Color.White)
                line(Path().apply { moveTo(e.x - 8, e.y - 17); quadraticTo(e.x, e.y - 24, e.x + 8, e.y - 17) }, CatPalette.ink, 2.6f)
            }
            else -> {
                val big = mood == CatMood.RINGING
                val w = if (big) 15f else 13f
                val h = if (big) 18f else 16f
                val blinkPhase = t % 4.7
                val blinking = if (!big && blinkPhase < 0.16) (0.12 + 0.88 * abs(blinkPhase / 0.08 - 1)).toFloat() else 1f
                val blink = min(blinking, max(0.12f, 1 - squint * 0.88f))
                eyes.forEachIndexed { i, e ->
                    var eye = Shapes.ellipse(e.x - w / 2, e.y - h / 2 * blink, w, h * blink)
                    if (mood == CatMood.GRUMPY) eye = Shapes.intersect(eye, lid(e, if (i == 0) -1.5f else 2.5f, if (i == 0) 2.5f else -1.5f, 0f))
                    fill(eye, CatPalette.ink)
                    if (blink > 0.6f) {
                        val hx = e.x + if (big) 2.8f else 2.4f
                        val hy = e.y - if (mood == CatMood.GRUMPY) -1.5f else if (big) 4.2f else 3.6f
                        fill(Shapes.circle(o(hx, hy), if (big) 3.2f else 2.7f), Color.White)
                        if (mood != CatMood.GRUMPY) fill(Shapes.ellipse(e.x - 3.8f, e.y + 2.2f, 2.6f, 2.6f), Color.White.a(0.8))
                    }
                }
            }
        }
    }

    // MARK: Parts

    /**
     * Two short arcs beside the cat, opening away from it, that swell with each breath
     * of the purr: out for a second, a pause, in for less and softer — the same breath
     * as the sound, so with the sound off the purr still shows.
     */
    internal fun DrawScope.purr(p: Offset, side: Float, strength: Float, t: Double, ground: CatGround) {
        if (strength <= 0.02f) return
        val b = t % 2.0
        val breath = when {
            b < 1.05 -> sin(PI * b / 1.05)
            b >= 1.17 && b < 1.89 -> 0.55 * sin(PI * (b - 1.17) / 0.72)
            else -> 0.0
        }
        val alpha = strength * (0.3 + 0.7 * breath)
        val middle = if (side < 0) 180f else 0f
        listOf(8f, 15f).forEachIndexed { i, radius ->
            val r = radius + breath.toFloat() * 1.5f
            drawArc(
                CatPalette.mark(ground).a(alpha * if (i == 0) 0.85 else 0.55),
                startAngle = middle - 36, sweepAngle = 72f, useCenter = false,
                topLeft = Offset(p.x - r, p.y - r), size = Size(r * 2, r * 2),
                style = androidx.compose.ui.graphics.drawscope.Stroke(3.2f, cap = androidx.compose.ui.graphics.StrokeCap.Round),
            )
        }
    }

    /** A four-pointed sparkle, for the 30-morning trick. */
    fun DrawScope.sparkle(center: Offset, radius: Float, color: Color) = drawPath(Shapes.sparkle(center, radius), color)

    private fun DrawScope.paw(center: Offset, size: Size, angle: Float, pads: Boolean = false) = at(center.x, center.y, angle) {
        val shape = Path().apply { addOval(Rect(Offset(-size.width / 2, -size.height / 2), size)) }
        fill(shape, CatPalette.fur)
        fill(Shapes.subtract(shape, shape.shifted(0f, -4f)), CatPalette.furShade)
        if (pads) {
            fill(Shapes.ellipse(-6f, -1f, 12f, 9f), CatPalette.earInner)
            for (x in listOf(-9f, 0f, 9f)) fill(Shapes.ellipse(x - 3, -9 - if (x == 0f) 2f else 0f, 6f, 6f), CatPalette.earInner)
        } else {
            for (x in listOf(-size.width * 0.14f, size.width * 0.14f)) {
                line(Path().apply { moveTo(x, size.height * 0.5f - 1); lineTo(x, size.height * 0.5f - 6) }, CatPalette.furDeep, 1.6f)
            }
        }
    }

    internal fun DrawScope.charm(c: Offset, medal: Boolean) {
        if (medal) {
            fill(Shapes.ellipse(c.x - 12, c.y - 10, 24f, 24f), CatPalette.moonShade)
            fill(Shapes.ellipse(c.x - 9.5f, c.y - 7.5f, 19f, 19f), CatPalette.moon)
            fill(Shapes.ellipse(c.x - 3.6f, c.y + 1.2f, 7.2f, 6f), CatPalette.moonShade)
            for ((dx, dy) in listOf(-5.2f to -1.6f, -1.9f to -4.6f, 1.9f to -4.6f, 5.2f to -1.6f)) {
                fill(Shapes.ellipse(c.x + dx - 1.6f, c.y + dy - 1.6f, 3.2f, 3.2f), CatPalette.moonShade)
            }
        } else {
            val bell = Shapes.ellipse(c.x - 8, c.y - 6, 16f, 16f)
            fill(bell, CatPalette.moon)
            fill(Shapes.subtract(bell, bell.shifted(0f, -4f)), CatPalette.moonShade)
            line(Path().apply { moveTo(c.x - 4, c.y + 4); lineTo(c.x + 4, c.y + 4) }, CatPalette.ink, 1.8f)
        }
    }

    /** The crescent the cat sleeps on; it never changes, so it is made once. */
    private val moonShape: Path by lazy { Shapes.dilate(Shapes.sliver(Offset.Zero, 88f, 62f, 42f), 6f) }

    internal fun DrawScope.moon() {
        fill(moonShape, CatPalette.moon)
        fill(Shapes.subtract(moonShape, moonShape.shifted(0f, 8f)), CatPalette.moonLight)
        fill(Shapes.subtract(moonShape, moonShape.shifted(-5f, -10f)), CatPalette.moonShade)
    }
}
