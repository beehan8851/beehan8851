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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import uz.ata.dawnwick.companion.Pet
import uz.ata.dawnwick.ui.cat.CatArt.charm
import uz.ata.dawnwick.ui.cat.CatArt.eyes
import uz.ata.dawnwick.ui.cat.CatArt.moon
import uz.ata.dawnwick.ui.cat.CatArt.purr
import uz.ata.dawnwick.ui.cat.Shapes.shifted

/**
 * The companions other than the cat, drawn the way the cat is: flat shapes, one shade
 * per surface, no outlines, in the cat's design space so every screen fits them the same.
 * They share the cat's eyes and moods; what makes each one itself — ears, beak, wool,
 * feathers, feet — is here. The cat itself stays in [CatArt], untouched.
 */
private class Look(
    val fur: Color, val shade: Color, val deep: Color,
    val accent: Color, val nose: Color, val blush: Color = CatPalette.blush,
    val belly: Color? = null,
)

private fun look(sp: Pet) = when (sp) {
    Pet.PUPPY -> Look(Color(0xFFFBF1E4), Color(0xFFEBD8BF), Color(0xFFD6BD9B), accent = Color(0xFFA9714B), nose = Color(0xFF3A2A22))
    Pet.LAMB -> Look(Color(0xFFFFFDF9), Color(0xFFEEE7DC), Color(0xFFDCD2C3), accent = Color(0xFFF6D9C6), nose = Color(0xFF9A7468))
    Pet.HAMSTER -> Look(Color(0xFFF4B977), Color(0xFFE29F5A), Color(0xFFCC8A48), accent = Color(0xFFF7A38E), nose = Color(0xFFF08B76), belly = Color(0xFFFFF8EE))
    Pet.CHICK -> Look(Color(0xFFFFE06A), Color(0xFFF5C93F), Color(0xFFE2B12A), accent = Color(0xFFFF9F2E), nose = Color(0xFFFF9F2E))
    Pet.CANARY -> Look(Color(0xFFFFD43B), Color(0xFFF0BC1E), Color(0xFFD9A514), accent = Color(0xFFE9A400), nose = Color(0xFFF2994A), belly = Color(0xFFFFE98A))
    Pet.OWL -> Look(Color(0xFFC79A6B), Color(0xFFB0835A), Color(0xFF94694A), accent = Color(0xFFFFF2DE), nose = Color(0xFFE9A400), belly = Color(0xFFF3DFC3))
    Pet.CAT -> Look(CatPalette.fur, CatPalette.furShade, CatPalette.furDeep, CatPalette.earInner, CatPalette.nose)
}

private fun Color.a(opacity: Double) = copy(alpha = alpha * opacity.toFloat().coerceIn(0f, 1f))
private fun Color.a(opacity: Float) = copy(alpha = alpha * opacity.coerceIn(0f, 1f))
private fun s(x: Double) = sin(x).toFloat()
private fun o(x: Number, y: Number) = Offset(x.toFloat(), y.toFloat())

object CompanionArt {
    /** Every companion but the cat sits for its fright too, so only sleep changes the frame. */
    fun designSize(mood: CatMood) = if (mood == CatMood.SLEEPING) Size(240f, 180f) else Size(200f, 222f)

    fun aspectRatio(mood: CatMood) = designSize(mood).let { it.width / it.height }

    fun DrawScope.drawCompanion(
        sp: Pet,
        mood: CatMood,
        ground: CatGround = CatGround.DARK,
        t: Double = 0.6,
        eyesWide: Boolean = false,
        dressing: CatDressing = CatDressing.NONE,
        petted: Float = 0f,
        lean: Float = 0f,
        purrSide: Float = 1f,
        breath: Double? = null,
    ) {
        val design = designSize(mood)
        val k = min(size.width / design.width, size.height / design.height)
        at((size.width - design.width * k) / 2, (size.height - design.height * k) / 2, sx = k) {
            if (mood == CatMood.SLEEPING) sleeping(sp, ground, t, petted, lean, breath)
            else sitting(sp, mood, ground, t, eyesWide, dressing, petted, lean, purrSide)
        }
    }

    // MARK: Poses

    private fun DrawScope.sleeping(sp: Pet, ground: CatGround, t: Double, petted: Float, lean: Float, paced: Double?) {
        val l = look(sp)
        val breath = paced?.let { (-it * 2.2).toFloat() } ?: s(t * 2 * PI / 4.4)
        for (i in 0 until 3) {
            val phase = (t / 3.6 + i / 3.0) % 1
            val fade = sin(phase * PI)
            glyph("z", o(176 + i * 16, 40 - i * 13 - phase * 24), 11f + i * 4,
                CatPalette.mark(ground).a((if (ground == CatGround.DARK) 0.8 else 0.5) * fade))
        }
        // Tail first, so the moon and the head lie over it.
        at(196f, 100f, 20f) { tail(sp, l, t, 0.8f) }
        at(104f, 80 + breath * 1.2f, -7f + lean * petted * 5) { head(sp, l, CatMood.SLEEPING, ground, t, petted = petted) }
        at(124f, 103f, -15f) { moon() }
        foot(sp, l, o(66, 126 + breath * 0.8f), Size(35f, 24f), -22f)
        foot(sp, l, o(156, 111 + breath * 0.8f), Size(36f, 25f), -12f)
        purr(o(22, 64), -1f, petted, t, ground)
    }

    private fun DrawScope.sitting(
        sp: Pet, mood: CatMood, ground: CatGround, t: Double, eyesWide: Boolean, dressing: CatDressing,
        petted: Float, lean: Float, away: Float,
    ) {
        val l = look(sp)
        val breath = s(t * 2 * PI / 3.4)
        val ringing = mood == CatMood.RINGING
        val startled = mood == CatMood.STARTLED
        // A fright is a shiver here: only the cat arches its back.
        val shiver = if (startled) s(t * 2 * PI * 9) * 1.2f else 0f

        at(shiver, 0f) {
            at(if (sp.isBird) 100f else 148f, if (sp.isBird) 196f else 194f) { tail(sp, l, t, if (ringing) 1.6f else 1f) }

            val tap = abs(s(t * 2 * PI / 0.62))
            val pawCenter = o(174, 104 - tap * 8)
            if (ringing) {
                val arm = Path().apply { moveTo(138f, 160f); quadraticTo(172f, 150f, pawCenter.x - 2, pawCenter.y + 8) }
                line(arm, l.shade, 22f)
                line(arm.shifted(-1.5f, -1f), l.fur, 17f)
            }

            body(sp, l, o(100, 166 - breath * 0.6f))

            foot(sp, l, o(83, 207), Size(29f, 17f), 0f)
            if (!ringing || sp.isBird) foot(sp, l, o(117, 207), Size(29f, 17f), 0f)

            if (dressing != CatDressing.NONE) {
                line(Path().apply { moveTo(62f, 146f); quadraticTo(100f, 174f, 138f, 146f) }, CatPalette.ink, 7f)
            }

            val open = if (mood == CatMood.YAWNING) CatArt.yawn(t) else 0f
            val (lift, tilt) = when (mood) {
                CatMood.PROUD -> -3f to -4f
                CatMood.SAD -> 6f to 4f
                CatMood.YAWNING -> -4 * open to -6 * open
                else -> 0f to 0f
            }
            val wobble = if (ringing) s(t * 2 * PI / 0.62) * 2.5f else 0f
            at(100f + lean * petted * 3, 97 + lift - breath, tilt + wobble + lean * petted * 9) { head(sp, l, mood, ground, t, eyesWide, petted) }

            if (dressing != CatDressing.NONE) charm(o(100, 165 - breath * 0.6f), dressing == CatDressing.MEDAL)
            purr(o(100 + away * 62, 158), away, petted, t, ground)

            if (ringing) {
                foot(sp, l, pawCenter, Size(30f, 28f), -12f, raised = true)
                listOf(o(22, -18), o(27, -2)).forEachIndexed { i, off ->
                    val start = pawCenter + off
                    line(Path().apply { moveTo(start.x, start.y); lineTo(start.x + 9, start.y + if (i == 0) -6 else 1) },
                        CatPalette.sparkle(ground).a(0.35f + 0.65f * tap), 3.5f)
                }
            }
            if (startled) {
                // Fright lines over the head, trembling.
                for ((i, a) in listOf(-62.0, -90.0, -118.0).withIndex()) {
                    val r = a * PI / 180
                    val c = o(100 + kotlin.math.cos(r) * 82, 92 + sin(r) * 82)
                    val len = 13f + 2 * s(t * 2 * PI * 3 + i)
                    line(Path().apply { moveTo(c.x, c.y); lineTo(c.x + kotlin.math.cos(r).toFloat() * len, c.y + sin(r).toFloat() * len) },
                        CatPalette.mark(ground).a(if (ground == CatGround.DARK) 0.85 else 0.75), 4f)
                }
            }
            if (mood == CatMood.PROUD) {
                fill(Shapes.sparkle(o(168, 46), 11f), CatPalette.sparkle(ground))
                fill(Shapes.sparkle(o(34, 72), 6.5f), CatPalette.sparkle(ground).a(0.85f))
            }
        }
    }

    // MARK: Body

    private fun DrawScope.body(sp: Pet, l: Look, c: Offset) {
        val shape = when (sp) {
            Pet.LAMB -> woolly(Shapes.squircle(c, 57f, 46f, 2.3f, 0.13f), c, 57f, 46f)
            else -> Shapes.squircle(c, if (sp.isBird) 54f else 57f, if (sp.isBird) 50f else 46f, 2.3f, 0.13f)
        }
        fill(shape, l.fur)
        fill(Shapes.subtract(shape, shape.shifted(8f, -7f)), l.shade)
        l.belly?.let { fill(Shapes.ellipse(c.x - 30, c.y - 24, 60f, 52f), it) }
        when (sp) {
            Pet.OWL -> for ((x, y) in listOf(-12f to -10f, 12f to -10f, 0f to 4f, -16f to 14f, 16f to 14f)) {
                line(Path().apply { moveTo(c.x + x - 5, c.y + y); quadraticTo(c.x + x, c.y + y + 5, c.x + x + 5, c.y + y) }, l.deep, 2.2f)
            }
            Pet.CHICK, Pet.CANARY, Pet.OWL -> Unit
            else -> Unit
        }
        if (sp.isBird) {
            // Folded wings on both sides.
            for (side in listOf(-1f, 1f)) at(c.x + side * 50, c.y - 2, side * 14f) {
                val wing = Shapes.ellipse(-11f, -24f, 22f, 46f)
                fill(wing, l.shade)
                if (sp == Pet.CANARY) {
                    fill(Shapes.intersect(wing, Shapes.rect(-12f, 8f, 24f, 16f)), l.deep)
                    line(Path().apply { moveTo(-8f, -2f); quadraticTo(0f, 4f, 8f, -2f) }, l.deep, 2.4f)
                }
            }
        }
    }

    /** A soft cloud of wool around a shape: bumps along its edge. */
    private fun woolly(base: Path, c: Offset, a: Float, b: Float): Path {
        var p = base
        val n = 14
        for (i in 0 until n) {
            val ang = 2 * PI * i / n
            val x = c.x + (a - 6) * kotlin.math.cos(ang).toFloat()
            val y = c.y + (b - 6) * sin(ang).toFloat()
            p = Shapes.union(p, Shapes.circle(o(x, y), 13f))
        }
        return p
    }

    // MARK: Tail

    private fun DrawScope.tail(sp: Pet, l: Look, t: Double, liveliness: Float) {
        when (sp) {
            Pet.PUPPY -> {
                // A short tail that wags, faster when it is excited.
                val wag = s(t * 2 * PI / (0.7 / liveliness)) * 22 * liveliness
                at(0f, 0f, -40f + wag) {
                    val p = Path().apply { moveTo(0f, 0f); quadraticTo(20f, -6f, 30f, -26f) }
                    line(p, l.shade, 15f); line(p.shifted(-1.5f, -1f), l.fur, 10f)
                }
            }
            Pet.LAMB -> {
                fill(Shapes.circle(o(4, -14), 15f), l.shade); fill(Shapes.circle(o(2, -16), 12f), l.fur)
            }
            Pet.HAMSTER -> Unit
            Pet.CANARY -> if (liveliness >= 1f) {
                // A perching bird's long tail, out to the side and swaying.
                val sway = s(t * 2 * PI / 2.4) * 5 * liveliness
                at(30f, -26f, -58f + sway) {
                    for ((i, a) in listOf(-12f, 0f, 12f).withIndex()) at(0f, 0f, a) {
                        fill(Shapes.roundedRect(-8f, 0f, 16f, 56f - abs(a) * 0.6f, 8f), if (i == 1) l.deep else l.shade)
                    }
                }
            } else {
                for (a in listOf(-20f, 20f)) at(0f, 0f, a) { fill(Shapes.ellipse(-8f, 0f, 16f, 34f), l.shade) }
            }
            else -> {
                // Tail feathers fanned behind a bird, peeking out at the bottom.
                val sway = s(t * 2 * PI / 2.4) * 4 * liveliness
                for ((i, a) in listOf(-26f, 0f, 26f).withIndex()) at(0f, 0f, a + sway) {
                    val f = Shapes.ellipse(-8f, 0f, 16f, if (sp == Pet.CANARY) 40f else 30f)
                    fill(f, if (i == 1) l.deep else l.shade)
                }
            }
        }
    }

    // MARK: Feet

    private fun DrawScope.foot(sp: Pet, l: Look, center: Offset, size: Size, angle: Float, raised: Boolean = false) = at(center.x, center.y, angle) {
        if (sp.isBird) {
            if (raised) {
                // A raised wing, waving.
                val wing = Shapes.ellipse(-12f, -20f, 24f, 40f)
                fill(wing, l.shade); fill(Shapes.subtract(wing, wing.shifted(0f, -5f)), l.deep)
            } else {
                for (dx in listOf(-7f, 0f, 7f)) fill(Shapes.roundedRect(dx - 3, -4f, 6f, 13f, 3f), l.nose)
            }
            return@at
        }
        val shape = Path().apply { addOval(Rect(Offset(-size.width / 2, -size.height / 2), size)) }
        val fur = if (sp == Pet.LAMB) l.nose.copy(alpha = 0.9f) else l.fur
        fill(shape, fur)
        if (sp != Pet.LAMB) fill(Shapes.subtract(shape, shape.shifted(0f, -4f)), l.shade)
        if (raised && sp != Pet.LAMB) {
            fill(Shapes.ellipse(-6f, -1f, 12f, 9f), l.accent)
            for (x in listOf(-9f, 0f, 9f)) fill(Shapes.ellipse(x - 3, -9 - if (x == 0f) 2f else 0f, 6f, 6f), l.accent)
        }
    }

    // MARK: Head

    private fun DrawScope.head(sp: Pet, l: Look, mood: CatMood, ground: CatGround, t: Double, eyesWide: Boolean = false, petted: Float = 0f) {
        val open = if (mood == CatMood.YAWNING) CatArt.yawn(t) else 0f
        val face = if (petted > 0.5f && !eyesWide && mood != CatMood.SLEEPING) CatMood.PROUD else mood
        val droop = when (mood) { CatMood.SAD -> 1f; CatMood.GRUMPY -> 0.6f; CatMood.SLEEPING -> 0.7f; else -> 0f } + petted * 0.5f

        // Behind the head.
        when (sp) {
            Pet.HAMSTER -> for (x in listOf(-44f, 44f)) {
                fill(Shapes.circle(o(x, -42 + droop * 3), 16f), l.fur)
                fill(Shapes.circle(o(x, -41 + droop * 3), 9f), l.accent)
            }
            Pet.OWL -> for (side in listOf(-1f, 1f)) at(side * 48, -44f, side * (24f + droop * 18)) {
                fill(Shapes.roundedPolygon(listOf(o(-14, 10), o(14, 10), o(4, -22)), 5f), l.shade)
            }
            Pet.LAMB -> for (side in listOf(-1f, 1f)) at(side * 74, -10 + droop * 6, side * (18f + droop * 30)) {
                fill(Shapes.ellipse(-24f, -11f, 48f, 22f), l.deep)
                fill(Shapes.ellipse(-16f, -6f, 32f, 12f), l.accent)
            }
            else -> Unit
        }

        if (sp == Pet.HAMSTER) whiskers(ground)

        val headShape = Shapes.squircle(Offset.Zero, if (sp.isBird) 68f else 72f, if (sp.isBird) 58f else 55f, 2.45f, 0.07f)
        fill(headShape, l.fur)
        fill(Shapes.subtract(headShape, headShape.shifted(9f, -10f)), l.shade)

        when (sp) {
            Pet.HAMSTER -> for (x in listOf(-1f, 1f)) fill(Shapes.ellipse(x * 30 - 26, 2f, 52f, 40f), l.belly!!)
            Pet.OWL -> for (x in listOf(-27f, 27f)) fill(Shapes.circle(o(x, 7), 22f), l.accent)
            Pet.LAMB -> {
                // A wool cap over the forehead.
                var cap = Shapes.circle(o(0, -44), 20f)
                for (x in listOf(-34f, -18f, 18f, 34f)) cap = Shapes.union(cap, Shapes.circle(o(x, -38 + abs(x) * 0.12f), 16f))
                fill(cap, Color.White); fill(Shapes.subtract(cap, cap.shifted(4f, -5f)), l.shade)
            }
            Pet.CHICK -> for ((i, a) in listOf(-22f, 0f, 22f).withIndex()) at(0f, -52f, a) {
                line(Path().apply { moveTo(0f, 0f); quadraticTo(4f, -10f, 0f, -16f - (i % 2) * 3) }, l.deep, 3.2f)
            }
            Pet.CANARY -> for ((i, a) in listOf(-26f, -4f, 18f).withIndex()) at(2f, -48f, a) {
                fill(Shapes.ellipse(-5f, -30f + (i % 2) * 6, 10f, 32f), l.deep)
            }
            else -> Unit
        }

        if (sp == Pet.PUPPY) {
            // A brown patch over one eye.
            fill(Shapes.ellipse(9f, -12f, 34f, 30f), l.accent.a(0.85))
        }

        if (!sp.isBird) {
            val blush = when { face == CatMood.PROUD || petted > 0.5f -> 0.55; face == CatMood.SAD -> 0.22; else -> 0.36 }
            for (x in listOf(-45f, 45f)) fill(Shapes.ellipse(x - 8, 17f, 16f, 8f), l.blush.a(blush))
        } else if (sp != Pet.OWL) {
            for (x in listOf(-44f, 44f)) fill(Shapes.ellipse(x - 8, 15f, 16f, 8f), l.blush.a(0.45))
        }

        eyes(face, t, eyesWide, open, squint = min(1f, petted * 2))
        if (face == CatMood.SAD && !eyesWide) tear(t)

        if (sp == Pet.PUPPY) {
            // Floppy ears, in front, swinging a little.
            val swing = s(t * 2 * PI / 3.1) * 3
            for (side in listOf(-1f, 1f)) at(side * 54, -44f, side * (6f + droop * 10 + swing)) {
                // A soft teardrop hanging close along the side of the head; the left is the right's mirror.
                val ear = Shapes.roundedPolygon(listOf(o(-10 * side, 0), o(14 * side, -2), o(24 * side, 46), o(4 * side, 60), o(-6 * side, 44)), 13f)
                fill(ear, l.accent); fill(Shapes.subtract(ear, ear.shifted(side * 4, -4f)), l.accent.copy(red = l.accent.red * 0.86f, green = l.accent.green * 0.86f, blue = l.accent.blue * 0.86f))
            }
        }

        if (sp.isBird) beak(l, mood, t, open) else muzzle(sp, l, mood, t, open)
    }

    private fun DrawScope.whiskers(ground: CatGround) {
        for (side in listOf(-1f, 1f)) for ((dy, reach) in listOf(-2f to -7f, 6f to 2f)) {
            line(Path().apply { moveTo(side * 58, 18 + dy); quadraticTo(side * 76, 16 + dy, side * 92, 18 + dy + reach) },
                CatPalette.mark(ground).a(if (ground == CatGround.DARK) 0.75 else 0.3), 1.6f)
        }
    }

    private fun DrawScope.tear(t: Double) {
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
    }

    /** Nose and mouth, the cat's moods in another face. */
    private fun DrawScope.muzzle(sp: Pet, l: Look, mood: CatMood, t: Double, open: Float) {
        when (sp) {
            Pet.PUPPY -> fill(Shapes.roundedRect(-8f, 13f, 16f, 11f, 5.5f), l.nose)
            Pet.LAMB -> fill(Shapes.roundedPolygon(listOf(o(-6, 17), o(6, 17), o(0, 23)), 2.5f), l.nose)
            else -> fill(Shapes.roundedPolygon(listOf(o(-5.5, 17.5), o(5.5, 17.5), o(0, 24)), 2.2f), l.nose)
        }
        fun mouth(p: Path) = line(p, CatPalette.ink, 2.1f, join = StrokeJoin.Round)
        fun smile() = Path().apply { moveTo(-7f, 26.5f); quadraticTo(-3.6f, 32f, 0f, 25.5f); quadraticTo(3.6f, 32f, 7f, 26.5f) }
        when (mood) {
            CatMood.RINGING -> {
                val h = 5.5f + abs(s(t * 2 * PI / 0.62)) * 2.5f
                fill(Shapes.roundedRect(-6f, 26f, 12f, h, 5f), CatPalette.ink)
                fill(Shapes.ellipse(-3.5f, 26 + h - 4, 7f, 4f), CatPalette.nose)
            }
            CatMood.STARTLED -> {
                fill(Shapes.roundedRect(-8f, 27f, 16f, 11f, 5.5f), CatPalette.ink)
                fill(Shapes.ellipse(-4f, 33f, 8f, 4f), CatPalette.nose)
            }
            CatMood.SAD -> mouth(Path().apply { moveTo(-7f, 33f); quadraticTo(0f, 26f, 7f, 33f) })
            CatMood.GRUMPY -> mouth(Path().apply { moveTo(-6f, 31f); quadraticTo(0f, 27.5f, 6f, 31f) })
            CatMood.YAWNING -> if (open > 0.08f) {
                val w = 10 + 10 * open
                val h = 4 + 20 * open
                fill(Shapes.ellipse(-w / 2, 25f, w, h), CatPalette.ink)
                fill(Shapes.ellipse(-w * 0.32f, 25 + h - h * 0.42f, w * 0.64f, h * 0.36f), CatPalette.nose)
            } else mouth(smile())
            else -> {
                mouth(smile())
                if (sp == Pet.PUPPY && mood == CatMood.PROUD) fill(Shapes.roundedRect(-4f, 29f, 8f, 8f, 4f), CatPalette.nose)
            }
        }
        if (sp == Pet.HAMSTER && mood != CatMood.YAWNING && mood != CatMood.RINGING && mood != CatMood.STARTLED) {
            fill(Shapes.roundedRect(-3.5f, 29f, 7f, 6f, 1.5f), Color.White)
        }
    }

    /** A small beak, closed, or open for a call, a fright or a yawn. */
    private fun DrawScope.beak(l: Look, mood: CatMood, t: Double, open: Float) {
        val gap = when (mood) {
            CatMood.RINGING -> 4f + abs(s(t * 2 * PI / 0.62)) * 4
            CatMood.STARTLED -> 7f
            CatMood.YAWNING -> 10 * open
            else -> 0f
        }
        val upper = Shapes.roundedPolygon(listOf(o(-9, 14), o(9, 14), o(0, 25)), 3f)
        if (gap > 0.5f) {
            fill(Shapes.ellipse(-6f, 18f, 12f, 6 + gap), CatPalette.ink)
            fill(Shapes.roundedPolygon(listOf(o(-7, 20 + gap), o(7, 20 + gap), o(0, 27 + gap)), 2.5f), l.nose.a(0.9))
        }
        fill(upper, l.nose)
        if (mood == CatMood.SAD || mood == CatMood.GRUMPY) {
            line(Path().apply { moveTo(-5f, 30f); quadraticTo(0f, 27f, 5f, 30f) }, CatPalette.ink.a(0.5), 1.6f)
        }
    }
}
