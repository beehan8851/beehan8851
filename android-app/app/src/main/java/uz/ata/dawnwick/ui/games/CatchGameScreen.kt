package uz.ata.dawnwick.ui.games

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.activity.compose.BackHandler
import kotlin.math.abs
import kotlin.math.sin
import uz.ata.dawnwick.R
import uz.ata.dawnwick.games.CatchGame
import uz.ata.dawnwick.games.GameRecord
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatArt
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatMotion
import uz.ata.dawnwick.ui.cat.CatMove
import uz.ata.dawnwick.ui.cat.CatStage
import uz.ata.dawnwick.ui.cat.reduceMotion
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * "Catch the cat": a short game for the first minutes of the day, when the hands and
 * eyes are still catching up. On paper, with yolk only where the eye should go: the
 * disc under the cat, the button.
 */
@Composable
fun CatchGameScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val record = remember { GameRecord.catch(context.graph.store) }
    val haptics = rememberHaptics()
    val game = remember { CatchGame(slow = slowGames()) }
    var phase by remember { mutableStateOf(game.phase) }
    var best by remember { mutableIntStateOf(record.best()) }
    var newBest by remember { mutableStateOf(false) }
    // Every tap moves the game on; the screen reads this to know it did.
    var revision by remember { mutableIntStateOf(0) }

    fun start() {
        haptics.perform(Haptic.MEDIUM)
        newBest = false
        game.start(System.currentTimeMillis())
        phase = game.phase
    }

    val now = frameClock(phase == CatchGame.Phase.PLAYING)
    LaunchedEffect(now) {
        if (phase != CatchGame.Phase.PLAYING) return@LaunchedEffect
        game.tick(now)
        if (game.phase == CatchGame.Phase.OVER) {
            newBest = record.submit(game.score)
            best = record.best()
            haptics.perform(Haptic.SUCCESS)
            phase = game.phase
        }
    }

    GamePhases(phase) { p ->
        when (p) {
            CatchGame.Phase.READY -> GamePage(onClose, picture = {
                CatOnDisc(CatMood.RINGING, 150.dp, 190.dp, Modifier.padding(bottom = Spacing.s))
            }) {
                GameTitle(stringResource(R.string.game_catch))
                GameRules(stringResource(R.string.catch_rules))
                if (best > 0) Text(stringResource(R.string.game_best, best), style = DawnType.headline, color = uz.ata.dawnwick.ui.theme.DawnColors.Ink)
                InkButton(::start) { Text(stringResource(R.string.game_play)) }
            }
            CatchGame.Phase.PLAYING -> CatchBoard(game, now, revision, onClose) { revision++ }
            CatchGame.Phase.OVER -> ScoreResult(
                onClose,
                stringResource(if (newBest) R.string.game_new_best else R.string.game_time_up),
                game.score,
                listOfNotNull(
                    if (best > 0 && !newBest) stringResource(R.string.game_best, best) else null,
                    if (game.bestCombo > 1) stringResource(R.string.game_longest_run, game.bestCombo) else null,
                ),
                ::start,
            ) {
                val mood = if (newBest) CatMood.PROUD else if (game.score >= 10) CatMood.AWAKE else CatMood.GRUMPY
                CatMotion(CatMove.FLIP, if (newBest) 1 else 0, 120.dp) { CatOnDisc(mood, 130.dp, 164.dp) }
            }
        }
    }
}

@Composable
private fun CatchBoard(game: CatchGame, now: Long, revision: Int, onClose: () -> Unit, changed: () -> Unit) {
    BackHandler(onBack = onClose)
    val haptics = rememberHaptics()
    val still = reduceMotion()
    val catLabel = stringResource(R.string.game_catch)
    Column(Modifier.fillMaxSize().padding(horizontal = Spacing.m).padding(bottom = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
        GameTopBar(onClose) { ScoreText(game.score) }
        TimerBar(game.remaining(now), game.roundLength)
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val density = LocalDensity.current
            val boardW = maxWidth
            val boardH = maxHeight
            val catWidth = 92.dp
            val catHeight = catWidth / CatArt.aspectRatio(CatMood.AWAKE)
            // The cat's hit area: itself and a little more, as a finger is not a pin.
            val hitW = catWidth + 28.dp
            val hitH = catHeight + 28.dp
            val cx by animateDpAsState(maxWidth * game.position.x.toFloat(), if (still) spring(stiffness = 1e5f) else spring(0.72f, 584f), label = "x")
            val cy by animateDpAsState(maxHeight * game.position.y.toFloat(), if (still) spring(stiffness = 1e5f) else spring(0.72f, 584f), label = "y")
            Box(
                Modifier.fillMaxSize().pointerInput(Unit) {
                    detectTapGestures { tap ->
                        val t = System.currentTimeMillis()
                        val x = with(density) { (maxWidth * game.position.x.toFloat()).toPx() }
                        val y = with(density) { (maxHeight * game.position.y.toFloat()).toPx() }
                        if (abs(tap.x - x) <= hitW.toPx() / 2 && abs(tap.y - y) <= hitH.toPx() / 2) {
                            val points = game.catchCat(t)
                            if (points > 0) haptics.perform(if (points > 1) Haptic.HEAVY else Haptic.MEDIUM)
                        } else {
                            // A tap on the empty board is a miss: the combo goes, and the cat bolts.
                            game.miss(t)
                            haptics.perform(Haptic.RIGID)
                        }
                        changed()
                    }
                },
            ) {
                game.lastCatch?.let { c ->
                    PointsPop(c.points, c.index, boardW * c.point.x.toFloat(), boardH * c.point.y.toFloat() - 40.dp)
                }
                val startled = game.isStartled(now)
                val left = game.jumpsAt?.let { (it - now) / 1000.0 } ?: 1.0
                val restless = !still && left < 0.35
                val mood = if (startled) CatMood.STARTLED else if (game.isOnCombo) CatMood.PROUD else CatMood.AWAKE
                val move = if (startled) CatMove.STARTLE else if (game.combo == CatchGame.COMBO_THRESHOLD) CatMove.FLIP else CatMove.HOP
                Box(
                    Modifier.offset(cx - hitW / 2, cy - hitH / 2).size(hitW, hitH)
                        .semantics {
                            contentDescription = catLabel
                            onClick { game.catchCat(System.currentTimeMillis()); changed(); true }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    YolkDisc(104.dp, Modifier.offset(y = 6.dp))
                    CatMotion(move, game.jumps, 80.dp) {
                        CatStage(mood, Modifier.width(catWidth).rotate(if (restless) (sin(now / 1000.0 * 60) * 7).toFloat() else 0f), CatGround.LIGHT, animated = startled)
                    }
                }
            }
        }
        HintLine(
            when {
                game.isOnCombo -> stringResource(R.string.catch_combo)
                game.combo > 1 -> stringResource(R.string.game_in_a_row, game.combo)
                else -> stringResource(R.string.catch_hint)
            },
            strong = game.isOnCombo,
        )
        // Read so a tap redraws at once, not on the next frame.
        if (revision < 0) Text("")
    }
}
