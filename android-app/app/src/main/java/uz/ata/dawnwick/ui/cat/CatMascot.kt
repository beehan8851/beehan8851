package uz.ata.dawnwick.ui.cat

import uz.ata.dawnwick.companion.Pet
import android.os.SystemClock
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatArt.drawCat

/** True when the person asked for less motion: animations off in the system settings. */
@Composable
fun reduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        android.provider.Settings.Global.getFloat(context.contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** Seconds that tick every frame while shown, or a still moment under reduced motion. */
@Composable
fun artClock(animated: Boolean = true): Double {
    val still = reduceMotion() || !animated
    var t by remember { mutableDoubleStateOf(0.6) }
    if (!still) {
        LaunchedEffect(Unit) {
            val start = withFrameNanos { it }
            val offset = (System.currentTimeMillis() % 100_000) / 1000.0
            while (true) withFrameNanos { t = offset + (it - start) / 1e9 }
        }
    }
    return t
}

/**
 * A stroke, as the drawing needs it: when it began, when the finger lifted, and
 * which side the finger is on. The drawing works out from the clock how far into it
 * the cat is, so the eyes close and open smoothly on every frame. Times are
 * `SystemClock.uptimeMillis`.
 */
data class CatPetting(
    val since: Long? = null,
    val released: Long? = null,
    /** Where the finger is across the cat, -1 (its left edge) to 1 (its right). */
    val lean: Float = 0f,
    /**
     * Which side the purr shows on: away from the hand, changing only once the hand
     * is well over the other side, so a finger near the middle does not flick it.
     */
    val purrSide: Float = 1f,
) {
    fun following(lean: Float) = copy(lean = lean, purrSide = if (lean > 0.3f) -1f else if (lean < -0.3f) 1f else purrSide)

    val isStroking get() = since != null && released == null

    /** 0 untouched, 1 eyes shut and leaning in. */
    fun amount(now: Long): Float {
        val s = since ?: return 0f
        fun ease(x: Double): Float { val c = x.coerceIn(0.0, 1.0); return (c * c * (3 - 2 * c)).toFloat() }
        val r = released ?: return ease((now - s) / 350.0)
        return ease((r - s) / 350.0) * (1 - ease((now - r) / 500.0))
    }
}

/** Set while the cat is in the air (`CatMotion`): it jumps with its eyes wide open. */
val LocalCatEyesWide = compositionLocalOf { false }

/** Set while someone strokes it (`TappableCat`). */
val LocalCatPetting = compositionLocalOf { CatPetting() }

/** What it has earned to wear, set once at the root from the best streak. */
val LocalCatDressing = staticCompositionLocalOf { CatDressing.NONE }

/** The tricks the cat knows: everything the best streak has taught it. */
val LocalCatBest = staticCompositionLocalOf { 0 }

fun dressingFor(best: Int) = when {
    best >= 100 -> CatDressing.MEDAL
    best >= 60 -> CatDressing.COLLAR
    else -> CatDressing.NONE
}

/**
 * The cat, breathing and blinking. It never stands alone: whatever it means is said
 * in words beside it, so screen readers skip it.
 */
@Composable
fun CatMascot(
    mood: CatMood,
    modifier: Modifier = Modifier,
    ground: CatGround = CatGround.LIGHT,
    animated: Boolean = true,
    eyesWide: Boolean = false,
    breath: Double? = null,
) {
    val t = artClock(animated)
    val wide = eyesWide || LocalCatEyesWide.current
    val petting = LocalCatPetting.current
    val dressing = LocalCatDressing.current
    val sp = currentCompanion()
    Canvas(modifier.aspectRatio(companionAspectRatio(sp, mood)).clearAndSetSemantics {}) {
        // Read every frame through `t`, so the stroke eases in and out smoothly.
        val petted = if (t >= 0) petting.amount(SystemClock.uptimeMillis()) else 0f
        if (sp == Pet.CAT) drawCat(mood, ground, t, wide, dressing, petted, petting.lean, petting.purrSide, breath)
        else with(CompanionArt) { drawCompanion(sp, mood, ground, t, wide, dressing, petted, petting.lean, petting.purrSide, breath) }
    }
}

/** Set inside the games: they are the cat's, whichever companion is chosen. */
val LocalForcedCompanion = androidx.compose.runtime.staticCompositionLocalOf<Pet?> { null }

/** Everything inside shows the cat. */
@Composable
fun CatOnly(content: @Composable () -> Unit) =
    androidx.compose.runtime.CompositionLocalProvider(LocalForcedCompanion provides Pet.CAT, content = content)

/** The companion drawn here: the cat in the games, the chosen one everywhere else. */
@Composable
fun currentCompanion(): Pet {
    LocalForcedCompanion.current?.let { return it }
    return LocalContext.current.graph.companion.collectAsState().value
}

fun companionDesignSize(sp: Pet, mood: CatMood) = if (sp == Pet.CAT) CatArt.designSize(mood) else CompanionArt.designSize(mood)
fun companionAspectRatio(sp: Pet, mood: CatMood) = companionDesignSize(sp, mood).let { it.width / it.height }

/** Every cat inside knows the tricks the best streak has taught it, and wears what it earned. */
@Composable
fun CatTricksProvider(best: Int? = null, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val stored = remember { context.graph.streak.load().bestStreak }
    val best = best ?: stored
    androidx.compose.runtime.CompositionLocalProvider(LocalCatBest provides best, LocalCatDressing provides dressingFor(best)) { content() }
}
