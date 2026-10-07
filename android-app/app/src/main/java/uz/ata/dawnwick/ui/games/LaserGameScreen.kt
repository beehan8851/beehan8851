package uz.ata.dawnwick.ui.games

import androidx.activity.compose.BackHandler
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import uz.ata.dawnwick.R
import uz.ata.dawnwick.games.GameRecord
import uz.ata.dawnwick.games.LaserGame
import uz.ata.dawnwick.games.Pt
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatArt
import uz.ata.dawnwick.ui.cat.CatArt.drawStretch
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatMotion
import uz.ata.dawnwick.ui.cat.CatMove
import uz.ata.dawnwick.ui.cat.CatStage
import uz.ata.dawnwick.ui.cat.artClock
import uz.ata.dawnwick.ui.cat.reduceMotion
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

private val LaserRed = Color(0xFFF0402F)

/**
 * "Laser": a finger is the dot, the cat chases it. The board is a dark room, where a
 * laser dot shows and a white cat stands out; the screen around it is paper.
 */
@Composable
fun LaserGameScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val record = remember { GameRecord.laser(context.graph.store) }
    val haptics = rememberHaptics()
    val game = remember { LaserGame(slow = slowGames()) }
    var phase by remember { mutableStateOf(game.phase) }
    var best by remember { mutableIntStateOf(record.best()) }
    var newBest by remember { mutableStateOf(false) }

    fun start() {
        haptics.perform(Haptic.MEDIUM)
        newBest = false
        game.start(System.currentTimeMillis())
        phase = game.phase
    }

    val now = frameClock(phase == LaserGame.Phase.PLAYING)
    var lastCat by remember { mutableStateOf<LaserGame.Cat>(LaserGame.Cat.Waiting) }
    LaunchedEffect(now) {
        if (phase != LaserGame.Phase.PLAYING) return@LaunchedEffect
        game.tick(now)
        val cat = game.cat
        if (cat::class != lastCat::class) when {
            cat is LaserGame.Cat.Pouncing -> haptics.perform(Haptic.LIGHT)
            cat is LaserGame.Cat.Landed && cat.caught -> haptics.perform(Haptic.HEAVY)
            cat is LaserGame.Cat.Landed && lastCat is LaserGame.Cat.Pouncing && game.dot != null -> haptics.perform(Haptic.RIGID)
        }
        lastCat = cat
        if (game.phase == LaserGame.Phase.OVER) {
            newBest = record.submit(game.score)
            best = record.best()
            haptics.perform(Haptic.SUCCESS)
            phase = game.phase
        }
    }

    GamePhases(phase) { p ->
        when (p) {
            LaserGame.Phase.READY -> GamePage(onClose, picture = {
                LaserPoster(Modifier.widthIn(max = 320.dp).fillMaxWidth().padding(bottom = Spacing.s))
            }) {
                GameTitle(stringResource(R.string.game_laser))
                GameRules(stringResource(R.string.laser_rules))
                if (best > 0) Text(stringResource(R.string.game_best, best), style = DawnType.headline, color = DawnColors.Ink)
                InkButton(::start) { Text(stringResource(R.string.game_play)) }
            }
            LaserGame.Phase.PLAYING -> LaserBoard(game, now, onClose)
            LaserGame.Phase.OVER -> ScoreResult(
                onClose,
                stringResource(if (newBest) R.string.game_new_best else R.string.game_time_up),
                game.score,
                listOfNotNull(
                    if (best > 0 && !newBest) stringResource(R.string.game_best, best) else null,
                    if (game.bestCombo > 1) stringResource(R.string.game_longest_run, game.bestCombo) else null,
                ),
                ::start,
            ) {
                val mood = if (newBest) CatMood.PROUD else if (game.score >= 8) CatMood.AWAKE else CatMood.GRUMPY
                CatMotion(CatMove.FLIP, if (newBest) 1 else 0, 120.dp) { CatOnDisc(mood, 130.dp, 164.dp) }
            }
        }
    }
}

@Composable
private fun LaserBoard(game: LaserGame, now: Long, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    Column(Modifier.fillMaxSize().padding(horizontal = Spacing.m).padding(bottom = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        GameTopBar(onClose) { ScoreText(game.score) }
        TimerBar(game.remaining(now), game.roundLength)
        BoxWithConstraints(
            Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(Radius.xl)).background(DawnColors.Ink)
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        game.pointDot(Pt(down.position.x / density.toDouble(), down.position.y / density.toDouble()), System.currentTimeMillis())
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            if (change.positionChange() != Offset.Zero) {
                                game.pointDot(Pt(change.position.x / density.toDouble(), change.position.y / density.toDouble()), System.currentTimeMillis())
                                change.consume()
                            }
                        }
                        game.liftDot()
                    }
                },
        ) {
            LaunchedEffect(maxWidth, maxHeight) { game.setBoard(maxWidth.value.toDouble(), maxHeight.value.toDouble()) }
            androidx.compose.animation.AnimatedVisibility(game.dot == null && game.cat == LaserGame.Cat.Waiting, Modifier.align(Alignment.TopCenter).padding(top = Spacing.l), enter = fadeIn(), exit = fadeOut()) {
                Text(stringResource(R.string.laser_put_finger), style = DawnType.headline, color = DawnColors.NightTextSecondary)
            }
            game.lastDodge?.let { d -> PointsPop(d.points, d.index, d.point.x.dp, d.point.y.dp - 70.dp, DawnColors.Yolk) }
            LaserBoardCat(game, now)
        }
        HintLine(
            when {
                (game.cat as? LaserGame.Cat.Landed)?.caught == true -> stringResource(R.string.laser_got_it)
                game.isOnCombo -> stringResource(R.string.laser_combo)
                game.combo > 1 -> stringResource(R.string.game_in_a_row, game.combo)
                else -> stringResource(R.string.laser_hint)
            },
            strong = (game.cat as? LaserGame.Cat.Landed)?.caught == true || game.isOnCombo,
        )
    }
}

private val SideWidth = 150.dp
private val SideHeight = SideWidth * (CatArt.stretchDesignSize.height / CatArt.stretchDesignSize.width)

/**
 * The cat, and the dot. Side on, facing the dot: bounding after it, low and wriggling
 * before a spring, stretched out in the air, paws out where it lands. Sitting up when
 * there is no dot to chase.
 */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.LaserBoardCat(game: LaserGame, now: Long) {
    val still = reduceMotion()
    val t = now / 1000.0 % 100_000
    val (point, height) = game.catPosition(now)
    val caught = (game.cat as? LaserGame.Cat.Landed)?.caught == true
    val dot = game.dot
    if (caught && dot != null) LaserDot(Modifier.align(Alignment.TopStart).offset(dot.x.dp - 11.dp, dot.y.dp - 11.dp))
    Box(
        Modifier.align(Alignment.TopStart)
            .offset(point.x.dp - SideWidth / 2, (point.y - height * 70).dp - SideHeight / 2)
            .size(SideWidth, SideHeight)
            .clearAndSetSemantics {},
    ) {
        when (val c = game.cat) {
            LaserGame.Cat.Waiting -> {
                val w = 74.dp
                CatStage(CatMood.AWAKE, Modifier.width(w).align(Alignment.Center)
                    .offset(y = SideHeight / 2 - w / CatArt.aspectRatio(CatMood.AWAKE) / 2), CatGround.DARK)
            }
            LaserGame.Cat.Chasing -> {
                val stride = if (still) 0.5 else 0.5 + 0.5 * sin(t * 2 * PI * 3.4)
                SideCat(game.facing, stride.toFloat(), t, Modifier.offset(y = if (still) 0.dp else (-abs(sin(t * PI * 3.4)) * 6).dp))
            }
            is LaserGame.Cat.Crouching -> SideCat(game.facing, 0f, t, Modifier.graphicsLayer {
                scaleY = 0.93f
                rotationZ = if (still) 0f else (sin(t * 2 * PI * 6) * 1.6).toFloat()
                transformOrigin = TransformOrigin(if (game.facing < 0) 0f else 1f, 1f)
            })
            is LaserGame.Cat.Pouncing -> SideCat(game.facing, 1f, t, Modifier.graphicsLayer { rotationZ = (game.facing * height * 8).toFloat() })
            is LaserGame.Cat.Landed -> SideCat(game.facing, if (c.caught) 1f else 0.6f, t)
        }
    }
    if (!caught && dot != null) LaserDot(Modifier.align(Alignment.TopStart).offset(dot.x.dp - 11.dp, dot.y.dp - 11.dp))
}

@Composable
private fun SideCat(facing: Double, reach: Float, t: Double, modifier: Modifier = Modifier) {
    Canvas(modifier.size(SideWidth, SideHeight)) {
        // Drawn facing left.
        scale(if (facing < 0) 1f else -1f, 1f) { drawStretch(CatGround.DARK, t, reach, 0f, hunting = true) }
    }
}

/** A laser pointer's dot: flat red, the hot middle paler. On the dark board it needs no glow. */
@Composable
private fun LaserDot(modifier: Modifier = Modifier) {
    Canvas(modifier.size(22.dp)) {
        drawCircle(LaserRed)
        drawCircle(Color(0xFFFFB3A8), radius = 4.dp.toPx())
    }
}

/** The intro's picture, and the cards': the cat down low, eyes on the dot. */
@Composable
fun LaserPoster(modifier: Modifier = Modifier, room: Boolean = true) {
    val t = artClock()
    Row(
        modifier
            .then(if (room) Modifier.clip(RoundedCornerShape(Radius.xl)).background(DawnColors.Ink).padding(Spacing.m) else Modifier)
            .clearAndSetSemantics {},
        verticalAlignment = Alignment.Bottom,
    ) {
        Box(Modifier.weight(1f).padding(bottom = 8.dp), contentAlignment = Alignment.Center) { LaserDot() }
        Canvas(Modifier.weight(3f).aspectRatio(CatArt.stretchDesignSize.width / CatArt.stretchDesignSize.height)) {
            drawStretch(CatGround.DARK, t, 0f, 0f, hunting = true)
        }
    }
}
