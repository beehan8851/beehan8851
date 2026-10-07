package uz.ata.dawnwick.ui.cat

import android.os.SystemClock
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics

// MARK: - Moves

/**
 * What the cat does when something happens to it. Every move is squash and stretch
 * on the whole drawing: it crouches, stretches as it leaves the ground, hangs at the
 * top and squashes again when it lands — what makes a drawing feel like it has weight.
 */
enum class CatMove(
    /** How high, as a share of the cat's own height. */
    val height: Float,
    val turns: Float = 0f,
    val tilt: Float = 0f,
    /** Seconds: getting ready, going up (and again coming down), hanging at the top. */
    val crouch: Double = 0.1,
    val air: Double = 0.24,
    val top: Double = 0.06,
) {
    /** A small hop: a tap, a jump in the game. */
    HOP(0.28f, air = 0.16),
    /** A big leap for a won morning. */
    LEAP(0.5f),
    /** A leap with a full turn at the top: a milestone. */
    FLIP(0.62f, turns = 360f, top = 0.16),
    /** The sleeping cat does not get up. It stirs, and settles again. */
    STIR(0f, tilt = 7f),
    /** Straight up with no crouch, then a shiver on landing: a fright. */
    STARTLE(0.34f, tilt = 3.5f, crouch = 0.02, air = 0.1, top = 0.12);

    val shiverDelay get() = if (this == STARTLE) crouch + air * 2 + top else 0.0
    val shiverBeat get() = if (this == STARTLE) 0.05 else 0.16
}

/** One keyframe track: segments of (seconds, target, kind) from a starting value. */
private class Track(val start: Float, val segments: List<Triple<Double, Float, Char>>) {
    val length = segments.sumOf { it.first }

    fun at(time: Double): Float {
        var t = time
        var from = start
        for ((d, to, kind) in segments) {
            if (t <= d && d > 0) {
                val x = (t / d).coerceIn(0.0, 1.0)
                val k = when (kind) {
                    'l' -> x
                    // A bouncy spring: overshoots and settles within its time.
                    's' -> 1 - exp(-5 * x) * cos(2.6 * PI * x)
                    else -> x * x * (3 - 2 * x)
                }
                return from + (to - from) * k.toFloat()
            }
            t -= d
            from = to
        }
        return from
    }
}

private class MoveTracks(move: CatMove) {
    val air = move.air
    val top = move.top
    val crouch = move.crouch
    val jumps = move != CatMove.STIR
    val stir = move == CatMove.STIR
    val startle = move == CatMove.STARTLE

    val lift = Track(0f, listOf(
        Triple(crouch, 0f, 'l'), Triple(air, if (jumps) 1f else 0f, 'c'), Triple(top, if (jumps) 1f else 0f, 'c'),
        Triple(air, 0f, 'c'), Triple(0.3, 0f, 'l'),
    ))
    val stretch = Track(1f, listOf(
        Triple(crouch, if (stir) 0.96f else if (startle) 1f else 0.82f, 'c'),
        Triple(air * 0.7, if (stir) 1.02f else if (startle) 1.16f else 1.12f, 'c'),
        Triple(air * 0.3 + top, 1f, 'c'),
        Triple(air * 0.8, if (stir) 1f else 1.05f, 'c'),
        Triple(air * 0.2, if (stir) 1f else 0.86f, 'c'),
        Triple(0.3, 1f, 's'),
    ))
    val spin = Track(0f, listOf(
        Triple(crouch + air * 0.6, 0f, 'l'), Triple(air * 0.4 + top + air * 0.4, move.turns, 'c'), Triple(0.3, move.turns, 'l'),
    ))
    val tilt = Track(0f, listOf(
        Triple(max(move.shiverDelay, 0.001), 0f, 'l'),
        Triple(move.shiverBeat * 0.9, move.tilt, 'c'), Triple(move.shiverBeat * 1.1, -move.tilt, 'c'),
        Triple(move.shiverBeat, move.tilt * 0.6f, 'c'), Triple(move.shiverBeat, -move.tilt * 0.4f, 'c'),
        Triple(0.3, 0f, 's'),
    ))
    val length = maxOf(lift.length, stretch.length, spin.length, tilt.length)
    /** When it is off the ground, and its eyes go wide. */
    val airborne = (crouch - 0.02)..(crouch + air * 2 + top - 0.02)
}

/**
 * Plays `move` every time `trigger` changes (not on the first composition, unless
 * `trigger` is already non-zero then). `height` is the cat's height, which sets how
 * far it jumps; `shadow` draws its shadow on the ground beneath. Under reduced
 * motion nothing moves.
 */
@Composable
fun CatMotion(move: CatMove, trigger: Int, height: Dp, modifier: Modifier = Modifier, shadow: Boolean = false, content: @Composable () -> Unit) {
    val still = reduceMotion()
    var lift by remember { mutableFloatStateOf(0f) }
    var stretch by remember { mutableFloatStateOf(1f) }
    var spin by remember { mutableFloatStateOf(0f) }
    var tilt by remember { mutableFloatStateOf(0f) }
    var airborne by remember { mutableStateOf(false) }
    LaunchedEffect(trigger) {
        if (trigger == 0 || still) return@LaunchedEffect
        val tracks = MoveTracks(move)
        val start = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            val t = (now - start) / 1e9
            lift = tracks.lift.at(t); stretch = tracks.stretch.at(t); spin = tracks.spin.at(t); tilt = tracks.tilt.at(t)
            airborne = tracks.jumps && t in tracks.airborne
            if (t >= tracks.length) break
        }
        lift = 0f; stretch = 1f; spin = 0f; tilt = 0f; airborne = false
    }
    val heightPx = with(LocalDensity.current) { height.toPx() }
    Box(
        modifier.drawBehind {
            if (shadow) {
                val w = size.width * 0.7f * (1 - 0.35f * lift)
                val h = heightPx * 0.07f
                drawOval(Color.Black.copy(alpha = 0.14f * (1 - 0.6f * lift)), Offset((size.width - w) / 2, size.height - h / 2 + heightPx * 0.03f), Size(w, h))
            }
        },
    ) {
        Box(
            Modifier.graphicsLayer {
                // Volume is kept: what it loses in height it gains in width.
                scaleY = stretch
                scaleX = 1 / max(stretch, 0.5f)
                rotationZ = spin + tilt
                transformOrigin = if (spin == 0f) TransformOrigin(0.5f, 1f) else TransformOrigin.Center
                translationY = -heightPx * move.height * lift
            },
        ) {
            CompositionLocalProvider(LocalCatEyesWide provides airborne) { content() }
        }
    }
}

// MARK: - Room for every mood

/** How long a fright shows before the cat is itself again. */
const val STARTLE_HOLD_MS = 1100L

/**
 * A sitting cat's space, whatever the mood. The startled cat stands side on and is
 * wider and taller: it spills over the sides and top at the same scale, feet on the
 * same ground, rather than shrinking or pushing the layout about.
 */
@Composable
fun CatStage(mood: CatMood, modifier: Modifier = Modifier, ground: CatGround = CatGround.LIGHT, animated: Boolean = true) {
    BoxWithConstraints(modifier.aspectRatio(CatArt.aspectRatio(CatMood.AWAKE)).clearAndSetSemantics {}, contentAlignment = Alignment.BottomCenter) {
        val spread = CatArt.designSize(mood).width / CatArt.designSize(CatMood.AWAKE).width
        val w = maxWidth * spread
        val h = w / CatArt.aspectRatio(mood)
        Box(Modifier.requiredSize(w, h).offset(y = 0.dp)) { CatMascot(mood, Modifier.fillMaxWidth(), ground, animated) }
    }
}

// MARK: - A cat that answers a tap

/**
 * The cat, tappable: it hops and gives a short mrrp. Tapped three times in quick
 * succession it takes fright. Asleep, it only stirs. What else it does it learns
 * from long streaks: it waves back, turns somersaults, leaps, throws off sparkles.
 *
 * Stroked — a finger drawn across it, or simply left resting on it — it shuts its
 * eyes, pushes its head into the hand and purrs until the finger lifts.
 */
@Composable
fun TappableCat(mood: CatMood, width: Dp, modifier: Modifier = Modifier, ground: CatGround = CatGround.LIGHT, cue: Int = 0) {
    val best = LocalCatBest.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    var taps by remember { mutableIntStateOf(0) }
    val recent = remember { mutableListOf<Long>() }
    var startled by remember { mutableStateOf(false) }
    var waving by remember { mutableStateOf(false) }
    var sparkles by remember { mutableIntStateOf(0) }
    var petting by remember { mutableStateOf(CatPetting()) }
    var resting by remember { mutableStateOf<Job?>(null) }
    val sleeping = mood == CatMood.SLEEPING
    val shown = if (sleeping) mood else if (startled) CatMood.STARTLED else if (waving) CatMood.RINGING else mood
    val height = width / CatArt.aspectRatio(if (sleeping) mood else CatMood.AWAKE)

    val move = when {
        sleeping -> CatMove.STIR
        startled -> CatMove.STARTLE
        taps > 0 && best >= 7 && taps % 4 == 0 -> CatMove.FLIP
        taps > 0 && best >= 14 && taps % 3 == 0 -> CatMove.LEAP
        cue > 0 && taps == 0 -> CatMove.LEAP
        else -> CatMove.HOP
    }

    LaunchedEffect(startled) { if (startled) { delay(STARTLE_HOLD_MS); startled = false } }
    LaunchedEffect(waving) { if (waving) { delay(900); waving = false } }

    fun beginStroke() {
        if (petting.isStroking || startled) return
        petting = CatPetting(since = SystemClock.uptimeMillis()).following(petting.lean)
        CatSounds.purrStart()
        haptics.purr()
    }
    fun endStroke() {
        petting = petting.copy(released = SystemClock.uptimeMillis())
        CatSounds.purrStop()
        haptics.stopPurr()
    }
    fun tapped() {
        val now = SystemClock.uptimeMillis()
        recent.removeAll { now - it >= 700 }
        recent += now
        if (!sleeping && !startled && recent.size >= 3) {
            recent.clear()
            startled = true
            haptics.perform(Haptic.RIGID)
        } else {
            haptics.perform(if (sleeping) Haptic.SOFT else Haptic.LIGHT)
            if (!sleeping && !startled) {
                CatSounds.mrrp()
                if (best >= 3) waving = true
                if (best >= 30) sparkles++
            }
        }
        taps++
    }

    Box(modifier.width(width), contentAlignment = Alignment.BottomCenter) {
        if (best >= 30) SparkleBurst(sparkles, ground, Modifier.requiredSize(width * 1.6f, height * 1.4f))
        CatMotion(move, taps + cue * 1000, height) {
            CompositionLocalProvider(LocalCatPetting provides petting) {
                val touch = Modifier.pointerInput(Unit) {
                    val strokeDistance = with(density) { 14.dp.toPx() }
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        var moved = 0f
                        resting = scope.launch { delay(500); beginStroke() }
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            moved = (change.position - down.position).getDistance()
                            if (!petting.isStroking && moved > strokeDistance) { resting?.cancel(); beginStroke() }
                            if (petting.isStroking) {
                                petting = petting.following((change.position.x / size.width.coerceAtLeast(1) * 2 - 1).coerceIn(-1f, 1f))
                                change.consume()
                            }
                        }
                        resting?.cancel()
                        resting = null
                        if (petting.isStroking) endStroke() else if (moved <= strokeDistance) tapped()
                    }
                }
                if (sleeping) CatMascot(shown, touch.width(width), ground)
                else CatStage(shown, touch.width(width), ground)
            }
        }
    }
    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { if (petting.isStroking) { CatSounds.purrStop(); haptics.stopPurr() } }
    }
}

// MARK: - Sparkles

/**
 * A few sparkles flung out from the cat on a tap: the 30-morning trick. Each burst
 * runs from its own start, so taps in quick succession overlap.
 */
@Composable
fun SparkleBurst(trigger: Int, ground: CatGround, modifier: Modifier = Modifier) {
    val still = reduceMotion()
    val bursts = remember { mutableStateListOf<Pair<Int, Long>>() }
    var now by remember { mutableLongStateOf(0L) }
    LaunchedEffect(trigger) {
        if (trigger == 0 || still) return@LaunchedEffect
        val start = SystemClock.uptimeMillis()
        bursts.removeAll { start - it.second >= 700 }
        bursts += trigger to start
        while (bursts.any { SystemClock.uptimeMillis() - it.second < 700 }) withFrameNanos { now = SystemClock.uptimeMillis() }
        now = SystemClock.uptimeMillis()
    }
    val rays = listOf(Triple(-150.0, 0.62f, 9f), Triple(-100.0, 0.58f, 12f), Triple(-55.0, 0.66f, 8f), Triple(-15.0, 0.56f, 10f), Triple(-125.0, 0.4f, 6f))
    val color = if (ground == CatGround.DARK) CatPalette.moon else CatPalette.ink
    Canvas(modifier.clearAndSetSemantics {}) {
        val center = Offset(size.width / 2, size.height * 0.42f)
        val start = size.width * 0.3f
        for ((id, at) in bursts) {
            val p = (now - at) / 700.0
            if (p < 0 || p >= 1) continue
            val out = (1 - (1 - p).pow(3)).toFloat()
            val fade = (1 - p * p).toFloat()
            rays.forEachIndexed { i, (angleDeg, reach, r) ->
                val angle = (angleDeg + (id % 3) * 9 + i) * PI / 180
                val d = start + (size.width * reach - start) * out
                val c = Offset(center.x + cos(angle).toFloat() * d, center.y + sin(angle).toFloat() * d)
                drawPath(Shapes.sparkle(c, r * density * (0.6f + 0.4f * out)), color.copy(alpha = fade))
            }
        }
    }
}
