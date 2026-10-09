package uz.ata.dawnwick.ui.games

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlin.math.min
import kotlin.math.roundToInt
import uz.ata.dawnwick.R
import uz.ata.dawnwick.games.BoxGame
import uz.ata.dawnwick.games.GameRecord
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatArt
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatSounds
import uz.ata.dawnwick.ui.cat.CatStage
import uz.ata.dawnwick.ui.cat.Shapes
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * "Which box?": watch the box with the cat in it while the boxes change places, then
 * tap it. On paper, the boxes ink, so the white cat and the yolk labels are what the
 * eye follows.
 */
@Composable
fun BoxGameScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val record = remember { GameRecord.boxes(context.graph.store) }
    val haptics = rememberHaptics()
    val game = remember { BoxGame(slow = slowGames()) }
    var phase by remember { mutableStateOf(game.phase) }
    var best by remember { mutableIntStateOf(record.best()) }
    var newBest by remember { mutableStateOf(false) }
    var revision by remember { mutableIntStateOf(0) }
    var lastSwap by remember { mutableIntStateOf(0) }

    fun start() {
        haptics.perform(Haptic.MEDIUM)
        newBest = false
        lastSwap = 0
        game.start(System.currentTimeMillis())
        phase = game.phase
    }

    val moving = phase == BoxGame.Phase.PLAYING && (game.step != BoxGame.Step.Guessing || revision < 0)
    val now = frameClock(moving)
    LaunchedEffect(now) {
        if (phase != BoxGame.Phase.PLAYING) return@LaunchedEffect
        game.tick(now)
        val swap = game.swapNumber(now)
        if (swap > 0 && swap != lastSwap) haptics.perform(Haptic.SOFT)
        lastSwap = swap
        revision++
        if (game.phase == BoxGame.Phase.OVER) {
            newBest = record.submit(game.score)
            best = record.best()
            haptics.perform(Haptic.SUCCESS)
            phase = game.phase
        }
    }

    GamePhases(phase) { p ->
        when (p) {
            BoxGame.Phase.READY -> GamePage(onClose, picture = {
                BoxPoster(Modifier.widthIn(max = 300.dp).fillMaxWidth().padding(bottom = Spacing.s))
            }) {
                GameTitle(stringResource(R.string.game_boxes))
                GameRules(petString(R.string.boxes_rules))
                if (best > 0) Text(stringResource(R.string.game_best, best), style = DawnType.headline, color = DawnColors.Ink)
                InkButton(::start) { Text(stringResource(R.string.game_play)) }
            }
            BoxGame.Phase.PLAYING -> {
                BackHandler(onBack = onClose)
                Column(Modifier.fillMaxSize().padding(horizontal = Spacing.m).padding(bottom = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                    val livesLabel = stringResource(R.string.boxes_tries_left, game.lives)
                    GameTopBar(onClose, trailing = {
                        Row(Modifier.semantics { contentDescription = livesLabel }, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            repeat(BoxGame.STARTING_LIVES) { i ->
                                Canvas(Modifier.size(18.dp)) {
                                    drawPath(Shapes.pawPrint(androidx.compose.ui.geometry.Rect(Offset.Zero, size)),
                                        if (i < game.lives) DawnColors.Ink else DawnColors.Ink.copy(alpha = 0.15f))
                                }
                            }
                        }
                    }) { ScoreText(game.score) }
                    BoxRow(game, System.currentTimeMillis().coerceAtLeast(now), Modifier.weight(1f).fillMaxWidth()) { box ->
                        val right = game.choose(box, System.currentTimeMillis()) ?: return@BoxRow
                        if (right) { haptics.perform(Haptic.SUCCESS); CatSounds.mrrp() } else haptics.perform(Haptic.RIGID)
                        revision++
                    }
                    val (hint, strong) = when (val s = game.step) {
                        is BoxGame.Step.Showing, is BoxGame.Step.Hiding -> petString(R.string.boxes_watch) to false
                        is BoxGame.Step.Shuffling -> stringResource(R.string.boxes_keep_eye) to false
                        BoxGame.Step.Guessing -> stringResource(R.string.game_boxes) to true
                        is BoxGame.Step.Revealing -> stringResource(if (game.lastGuessRight) R.string.boxes_found else R.string.boxes_wrong) to true
                    }
                    HintLine(hint, strong)
                }
            }
            BoxGame.Phase.OVER -> ScoreResult(
                onClose,
                stringResource(if (newBest) R.string.game_new_best else R.string.game_over),
                game.score,
                listOfNotNull(if (best > 0 && !newBest) stringResource(R.string.game_best, best) else null),
                ::start,
            ) {
                BoxPoster(Modifier.widthIn(max = 220.dp).fillMaxWidth(),
                    mood = if (newBest) CatMood.PROUD else if (game.score >= 6) CatMood.AWAKE else CatMood.RINGING)
            }
        }
    }
}

/** The boxes in their row, each where the script puts it at `now`. */
@Composable
private fun BoxRow(game: BoxGame, now: Long, modifier: Modifier, choose: (Int) -> Unit) {
    BoxWithConstraints(modifier) {
        val count = game.count
        val pitch = maxWidth / count
        val boxWidth = minOf(pitch * 0.72f / (BoxArt.BODY_WIDTH / BoxArt.DESIGN_W), 260.dp)
        val spots = game.layout(now)
        for (box in 0 until count) {
            val spot = spots[box]
            val label = stringResource(R.string.boxes_box, spot.place.roundToInt() + 1)
            Box(
                Modifier.align(Alignment.TopStart)
                    .offset(maxWidth * ((spot.place + 0.5) / count).toFloat() - boxWidth / 2, maxHeight * 0.5f + boxWidth * (spot.arc * 0.32).toFloat() - boxWidth * (BoxArt.DESIGN_H / BoxArt.DESIGN_W) / 2)
                    .zIndex(spot.arc.toFloat())
                    .scale(1 + 0.07f * spot.arc.toFloat())
                    .clickable(remember { MutableInteractionSource() }, indication = null) { choose(box) }
                    .semantics { contentDescription = label },
            ) {
                BoxDrawing(boxWidth, open = openAmount(game, box, now), cat = catShown(game, box), duck = duckAmount(game, box, now))
            }
        }
    }
}

private fun sinceReveal(game: BoxGame, until: Long, now: Long) =
    (if (game.lastGuessRight) BoxGame.FOUND_LENGTH else BoxGame.MISSED_LENGTH) - (until - now) / 1000.0

private fun openAmount(game: BoxGame, box: Int, now: Long): Float = when (val s = game.step) {
    is BoxGame.Step.Showing -> 1f
    // The cat ducks first, then the lids come down.
    is BoxGame.Step.Hiding -> (((s.until - now) / 1000.0 - 0.05) / 0.25).toFloat().coerceIn(0f, 1f)
    is BoxGame.Step.Shuffling, BoxGame.Step.Guessing -> 0f
    is BoxGame.Step.Revealing -> {
        val opened = box == s.chosen || (!game.lastGuessRight && box == game.catBox)
        if (!opened) 0f else {
            // On a miss the cat's own box opens a moment after the wrong one.
            val delay = if (box == s.chosen) 0.0 else 0.45
            ((sinceReveal(game, s.until, now) - delay) / 0.2).toFloat().coerceIn(0f, 1f)
        }
    }
}

private fun catShown(game: BoxGame, box: Int): CatMood? {
    if (box != game.catBox) return null
    return when (val s = game.step) {
        is BoxGame.Step.Showing, is BoxGame.Step.Hiding -> CatMood.AWAKE
        is BoxGame.Step.Revealing -> if (s.chosen == box) CatMood.PROUD else CatMood.RINGING
        else -> null
    }
}

/** 0 sitting up in the box, 1 down out of sight. */
private fun duckAmount(game: BoxGame, box: Int, now: Long): Float = when (val s = game.step) {
    is BoxGame.Step.Hiding -> ((BoxGame.HIDE_LENGTH - (s.until - now) / 1000.0) / 0.25).toFloat().coerceIn(0f, 1f)
    is BoxGame.Step.Revealing -> {
        val delay = (if (box == s.chosen) 0.0 else 0.45) + 0.12
        1 - ((sinceReveal(game, s.until, now) - delay) / 0.22).toFloat().coerceIn(0f, 1f)
    }
    else -> 0f
}

enum class BoxGround { PAPER, INK }

/**
 * The box the cat hides in: ink cardboard, the flaps a shade lighter, a strip of yolk
 * tape over the seam when it is shut and a yolk label with a paw on the front. Drawn
 * in two layers so the cat can sit between them. `open` 0…1 swings the flaps.
 */
object BoxArt {
    const val DESIGN_W = 168f
    const val DESIGN_H = 112f
    const val BODY_WIDTH = 104f
    const val BODY_BOTTOM = 108f
    /** Where the front wall's top edge is, as a share of the height: the cat's head shows above it. */
    const val RIM = 46f / 112f

    private fun wall(g: BoxGround) = Color(if (g == BoxGround.PAPER) 0xFF1E1C19 else 0xFF4A4640)
    private fun flap(g: BoxGround) = Color(if (g == BoxGround.PAPER) 0xFF34312C else 0xFF5E5952)
    private val inside = Color(0xFF0B0A09)
    private val yolk = Color(0xFFFFC629)
    private val ink = Color(0xFF1C1A17)

    fun DrawScope.drawBox(front: Boolean, open: Float, ground: BoxGround) {
        val k = min(size.width / DESIGN_W, size.height / DESIGN_H)
        val o = open.coerceIn(0f, 1f)
        withTransform({
            translate((size.width - DESIGN_W * k) / 2, (size.height - DESIGN_H * k) / 2)
            scale(k, k, Offset.Zero)
            translate(24f, 8f)
        }) {
            if (!front) {
                if (o <= 0f) return@withTransform
                drawRoundRect(flap(ground), Offset(18f, 38 - 22 * o), Size(84f, 22 * o), CornerRadius(3f))
                drawRect(inside.copy(alpha = o), Offset(10f, 30f), Size(100f, 9f))
                return@withTransform
            }
            drawRoundRect(wall(ground), Offset(8f, 38f), Size(104f, 62f), CornerRadius(7f))
            drawRect(inside.copy(alpha = 0.6f), Offset(8f, 38f), Size(104f, 3f))
            label(Offset(60f, 72f))
            val angle = -105 * o
            translate(8f, 38f) { rotate(angle, Offset.Zero) { drawRoundRect(flap(ground), Offset(0f, -9f), Size(52f, 9f), CornerRadius(2.5f)) } }
            translate(112f, 38f) { rotate(-angle, Offset.Zero) { drawRoundRect(flap(ground), Offset(-52f, -9f), Size(52f, 9f), CornerRadius(2.5f)) } }
            val taped = (1 - o * 4).coerceAtLeast(0f)
            if (taped > 0) {
                drawRect(yolk.copy(alpha = taped), Offset(53f, 29f), Size(14f, 9f))
                drawRect(yolk.copy(alpha = taped), Offset(53f, 38f), Size(14f, 9f))
            }
        }
    }

    private fun DrawScope.label(c: Offset) {
        drawRoundRect(yolk, Offset(c.x - 17, c.y - 12), Size(34f, 24f), CornerRadius(5f))
        drawOval(ink, Offset(c.x - 6, c.y - 1), Size(12f, 10f))
        for ((dx, dy) in listOf(-8.5f to -4f, -3f to -8.5f, 3f to -8.5f, 8.5f to -4f)) {
            drawOval(ink, Offset(c.x + dx - 2.6f, c.y + dy - 2.6f), Size(5.2f, 5.2f))
        }
    }
}

/**
 * One box, with the cat in it or not. The cat sits between the box's two layers, its
 * head over the rim; ducking, it sinks behind the front wall and never shows below
 * the box. Laid out as the box alone: the room above for the head spills over.
 */
@Composable
fun BoxDrawing(width: Dp, open: Float = 1f, cat: CatMood? = null, duck: Float = 0f, ground: BoxGround = BoxGround.PAPER) {
    val height = width * (BoxArt.DESIGN_H / BoxArt.DESIGN_W)
    val catWidth = width * (BoxArt.BODY_WIDTH / BoxArt.DESIGN_W) * 0.86f
    val catHeight = catWidth / uz.ata.dawnwick.ui.cat.companionAspectRatio(uz.ata.dawnwick.ui.cat.currentCompanion(), CatMood.AWAKE)
    val room = catHeight * 0.7f
    val rimY = height * BoxArt.RIM
    val bottom = height * (BoxArt.BODY_BOTTOM / BoxArt.DESIGN_H)
    Box(Modifier.requiredSize(width, height).clearAndSetSemantics {}) {
        Box(Modifier.requiredSize(width, room + height).offset(y = -room / 2)) {
            with(BoxArt) {
                Canvas(Modifier.offset(y = room).requiredSize(width, height)) { drawBox(false, open, ground) }
            }
            if (cat != null) {
                Box(Modifier.requiredSize(width, room + bottom - 3.dp).clipToBounds(), contentAlignment = Alignment.TopCenter) {
                    CatStage(cat, Modifier.offset(y = room + rimY - catHeight * 0.66f + catHeight * 0.75f * duck).requiredSize(catWidth, catHeight),
                        if (ground == BoxGround.PAPER) CatGround.LIGHT else CatGround.DARK)
                }
            }
            with(BoxArt) {
                Canvas(Modifier.offset(y = room).requiredSize(width, height)) { drawBox(true, open, ground) }
            }
        }
    }
}

/** The intro's picture, and the cards': three boxes, the cat in the middle one. */
@Composable
fun BoxPoster(modifier: Modifier = Modifier, mood: CatMood = CatMood.AWAKE, ground: BoxGround = BoxGround.PAPER) {
    BoxWithConstraints(modifier.aspectRatio(2f).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        val w = maxWidth / 2.2f
        Box(Modifier.offset(x = -w * 0.74f, y = 0.dp)) { BoxDrawing(w, open = 0f, ground = ground) }
        Box(Modifier.offset(x = w * 0.74f)) { BoxDrawing(w, open = 0f, ground = ground) }
        BoxDrawing(w, open = 1f, cat = mood, ground = ground)
    }
}
