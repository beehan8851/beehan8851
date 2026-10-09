package uz.ata.dawnwick.ui.games

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.time.LocalDate
import uz.ata.dawnwick.R
import uz.ata.dawnwick.core.KeyValueStore
import uz.ata.dawnwick.games.CatNapDay
import uz.ata.dawnwick.games.CatNapRecord
import uz.ata.dawnwick.games.GameRecord
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatTricksProvider
import uz.ata.dawnwick.ui.components.CircleIconButton
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.DaylightTheme
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * The morning games, as Today and the Play tab list them: what each is called, what
 * it asks of you, its record, its picture and the screen it opens. Short games for
 * the first minutes of the day — never a mission, never in the way of an alarm.
 */
enum class MorningGame(val title: Int, val skill: Int) {
    CATCH(R.string.game_catch, R.string.skill_catch),
    LASER(R.string.game_laser, R.string.skill_laser),
    BOXES(R.string.game_boxes, R.string.skill_boxes),
    NAPS(R.string.game_naps, R.string.skill_naps);

    /** The record; for Cat Naps, the days in a row solved. */
    fun best(store: KeyValueStore): Int = when (this) {
        CATCH -> GameRecord.catch(store).best()
        LASER -> GameRecord.laser(store).best()
        BOXES -> GameRecord.boxes(store).best()
        NAPS -> CatNapRecord(store).streak(CatNapDay.number())
    }

    companion object {
        /** One game a day on Today, in turn, so the card is not always the same. */
        fun ofTheDay(date: LocalDate = LocalDate.now()) = entries[Math.floorMod(date.toEpochDay(), entries.size.toLong()).toInt()]
    }
}

/** One line on what it is, with the record in front once there is one. */
@Composable
fun gameDetail(game: MorningGame, best: Int): String {
    val context = LocalContext.current
    return when (game) {
        MorningGame.CATCH -> if (best > 0) stringResource(R.string.detail_catch_best, best) else stringResource(R.string.detail_catch)
        MorningGame.LASER -> if (best > 0) stringResource(R.string.detail_laser_best, best) else stringResource(R.string.detail_laser)
        MorningGame.BOXES -> if (best > 0) petString(R.string.detail_boxes_best, best) else petString(R.string.detail_boxes)
        MorningGame.NAPS -> {
            val top = CatNapRecord(context.graph.store).solves(CatNapDay.number()).maxByOrNull { it.key.ordinal }
            when {
                top != null -> stringResource(R.string.detail_naps_solved, levelName(top.key), napClock(top.value.seconds))
                best > 0 -> stringResource(R.string.detail_naps_streak, best)
                else -> stringResource(R.string.detail_naps)
            }
        }
    }
}

/** The picture on an ink card. */
@Composable
fun GamePoster(game: MorningGame, width: Dp) {
    Box(Modifier.width(width), contentAlignment = Alignment.Center) {
        when (game) {
            MorningGame.CATCH -> CatMascot(CatMood.RINGING, Modifier.width(width * 0.62f), CatGround.DARK)
            MorningGame.LASER -> LaserPoster(Modifier.width(width), room = false)
            MorningGame.BOXES -> BoxPoster(Modifier.width(width), ground = BoxGround.INK)
            MorningGame.NAPS -> CatNapPoster(Modifier.width(width * 0.6f))
        }
    }
}

/** A game's words for the companion on screen: "Catch the puppy" when the puppy is chosen. */
@Composable
fun petString(id: Int, vararg args: Any): String = stringResource(PetStrings.of(id, uz.ata.dawnwick.ui.cat.currentCompanion()), *args)

/**
 * Opens `game` full screen, the way every game is opened: over everything, always in
 * daylight, and back to where it was opened from when it closes.
 */
@Composable
fun GameHost(game: MorningGame, onClose: () -> Unit) = GameHostCat(game, onClose)

@Composable
private fun GameHostCat(game: MorningGame, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DarkStatusIcons()
        DaylightTheme {
            CatTricksProvider {
                Box(Modifier.fillMaxSize().background(Dawn.colors.background).safeDrawingPadding()) {
                    when (game) {
                        MorningGame.CATCH -> CatchGameScreen(onClose)
                        MorningGame.LASER -> LaserGameScreen(onClose)
                        MorningGame.BOXES -> BoxGameScreen(onClose)
                        MorningGame.NAPS -> CatNapScreen(onClose)
                    }
                }
            }
        }
    }
}

// MARK: - Pieces every game shares

/**
 * Debug builds only: `adb shell setprop debug.dawnwick.slowgames 1` slows every game
 * right down — a cat that sits for a minute, a five-minute round — so each can be
 * played through by hand or by a script on a slow emulator.
 */
fun slowGames(): Boolean = uz.ata.dawnwick.BuildConfig.DEBUG && runCatching {
    Class.forName("android.os.SystemProperties").getMethod("get", String::class.java).invoke(null, "debug.dawnwick.slowgames") == "1"
}.getOrDefault(false)

/** Light status-bar icons would vanish on the paper a game is always played on. */
@Composable
fun DarkStatusIcons() {
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.DisposableEffect(view) {
        val window = (view.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window
        if (window != null) {
            val controller = androidx.core.view.WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = true
            controller.isAppearanceLightNavigationBars = true
        }
        onDispose { }
    }
}

/** The clock games run on: every frame while `running`, milliseconds. */
@Composable
fun frameClock(running: Boolean): Long {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(running) {
        now = System.currentTimeMillis()
        while (running) withFrameMillis { now = System.currentTimeMillis() }
    }
    return now
}

/** The three screens of a game, cross-faded. */
@Composable
fun <T> GamePhases(phase: T, content: @Composable (T) -> Unit) {
    AnimatedContent(phase, transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(300)) }, label = "phase") { content(it) }
}

/** The close button on the left, something in the middle, something on the right. */
@Composable
fun GameTopBar(onClose: () -> Unit, trailing: @Composable () -> Unit = {}, center: @Composable () -> Unit = {}) {
    Box(Modifier.fillMaxWidth().padding(top = Spacing.xs), contentAlignment = Alignment.Center) {
        center()
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            CircleIconButton(Icons.Rounded.Close, stringResource(R.string.close), onClose)
            Spacer(Modifier.weight(1f))
            trailing()
        }
    }
}

/** A game's intro or its result: the picture over the words, the buttons at the foot. */
@Composable
fun GamePage(onClose: () -> Unit, spacing: Dp = Spacing.m, picture: @Composable () -> Unit, words: @Composable ColumnScope.() -> Unit) {
    BackHandler(onBack = onClose)
    Column(Modifier.fillMaxSize().padding(horizontal = Spacing.m)) {
        GameTopBar(onClose)
        // Scrolls when it has to; otherwise sits at the foot, buttons under the thumb.
        androidx.compose.foundation.layout.BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            Column(
                Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(bottom = Spacing.s),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(spacing, Alignment.Bottom),
            ) {
                picture()
                Column(Modifier.widthIn(max = 520.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(spacing)) {
                    words()
                }
            }
        }
    }
}

@Composable
fun GameTitle(text: String, size: Int = 34) =
    Text(text, style = DawnType.display(size), color = DawnColors.Ink, textAlign = TextAlign.Center)

@Composable
fun GameRules(text: String) =
    Text(text, style = DawnType.callout, color = Dawn.colors.textSecondary, textAlign = TextAlign.Center)

/** The yolk under a cat on paper: a white cat needs somewhere to stand. */
@Composable
fun YolkDisc(size: Dp, modifier: Modifier = Modifier) =
    Box(modifier.size(size).clip(CircleShape).background(DawnColors.Yolk))

/** The cat on its yolk disc, as the intros and results show it. */
@Composable
fun CatOnDisc(mood: CatMood, width: Dp, disc: Dp, modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        YolkDisc(disc, Modifier.padding(top = 20.dp))
        CatMascot(mood, Modifier.width(width), CatGround.LIGHT)
    }
}

@Composable
fun GameChip(text: String) {
    Box(
        Modifier.heightIn(min = 36.dp).clip(RoundedCornerShape(50)).background(DawnColors.Ink.copy(alpha = 0.08f)).padding(horizontal = Spacing.s),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = DawnType.headline.copy(fontSize = 15.sp), color = DawnColors.Ink) }
}

/** A quiet text button: Done, Today's puzzles. */
@Composable
fun QuietButton(text: String, modifier: Modifier = Modifier, trailing: @Composable () -> Unit = {}, onClick: () -> Unit) {
    Row(
        modifier.fillMaxWidth().defaultMinSize(minHeight = 44.dp).pressable(onClick = onClick),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, style = DawnType.body.copy(fontWeight = FontWeight.SemiBold), color = Dawn.colors.textSecondary)
        trailing()
    }
}

/** The score, large, at the top of the board. */
@Composable
fun ScoreText(score: Int) {
    val label = stringResource(R.string.game_score, score)
    AnimatedContent(score, transitionSpec = { fadeIn(tween(150)) togetherWith fadeOut(tween(150)) }, label = "score",
        modifier = Modifier.semantics { contentDescription = label }) {
        Text("$it", style = DawnType.display(34), color = DawnColors.Ink)
    }
}

/** Time left, a bar that empties; darker in the last five seconds. */
@Composable
fun TimerBar(left: Double, total: Double) {
    val label = stringResource(R.string.game_seconds_left, kotlin.math.ceil(left).toInt())
    Box(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50)).background(DawnColors.Ink.copy(alpha = 0.12f)).semantics { contentDescription = label }) {
        Box(Modifier.fillMaxWidth((left / total).toFloat().coerceIn(0f, 1f)).height(8.dp).clip(RoundedCornerShape(50))
            .background(if (left < 5) DawnColors.Ink else DawnColors.Ink.copy(alpha = 0.85f)))
    }
}

/** The line under the board: the combo, the run so far, or what to do. */
@Composable
fun HintLine(text: String, strong: Boolean, color: Color = if (strong) DawnColors.Ink else Dawn.colors.textSecondary) {
    AnimatedContent(text to color, transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(200)) }, label = "hint") { (t, c) ->
        Text(t, style = DawnType.headline, color = c, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().heightIn(min = 28.dp))
    }
}

/** "+1" or "+2", rising from where it was won and fading. Keyed by `index` so each plays once. */
@Composable
fun BoxScope.PointsPop(points: Int, index: Int, x: Dp, y: Dp, color: Color = DawnColors.Ink) {
    val rise = remember(index) { Animatable(0f) }
    LaunchedEffect(index) { rise.animateTo(1f, tween(600)) }
    Text(
        "+$points", style = DawnType.display(if (points > 1) 34 else 28), color = color,
        modifier = Modifier.align(Alignment.TopStart)
            .graphicsLayer {
                translationX = x.toPx() - size.width / 2
                translationY = y.toPx() - size.height / 2 - 46.dp.toPx() * rise.value
                alpha = 1 - rise.value
            }
            .clearAndSetSemantics {},
    )
}

/** The result: a word, the score set large, the record and run in chips, and the way on. */
@Composable
fun ScoreResult(
    onClose: () -> Unit,
    headline: String,
    score: Int,
    chips: List<String>,
    onAgain: () -> Unit,
    picture: @Composable () -> Unit,
) {
    GamePage(onClose, Spacing.s, picture) {
        GameTitle(headline, 28)
        val words = pluralStringResource(R.plurals.points, score, score)
        val (before, after) = words.split("$score", limit = 2).let { it[0].trim() to it.getOrElse(1) { "" }.trim() }
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.semantics(mergeDescendants = true) {}) {
            if (before.isNotEmpty()) Text(before, style = DawnType.title.copy(fontSize = 20.sp), color = Dawn.colors.textSecondary)
            Text("$score", style = DawnType.display(96), color = DawnColors.Ink)
            if (after.isNotEmpty()) Text(after, style = DawnType.title.copy(fontSize = 20.sp), color = Dawn.colors.textSecondary)
        }
        Row(Modifier.heightIn(min = 36.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.s)) { chips.forEach { GameChip(it) } }
        uz.ata.dawnwick.ui.components.InkButton(onAgain) { Text(stringResource(R.string.game_play_again)) }
        QuietButton(stringResource(R.string.done), onClick = onClose)
    }
}

// MARK: - Cards

/** The yolk play button on a game card. */
@Composable
fun PlayDisc(size: Dp = 40.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(DawnColors.Yolk), contentAlignment = Alignment.Center) {
        Icon(Icons.Rounded.PlayArrow, null, tint = DawnColors.Ink, modifier = Modifier.size(size * 0.6f))
    }
}

/** A game on an ink card, as Today shows the game of the day: the title and a line, the picture, the play button. */
@Composable
fun GameCard(game: MorningGame, best: Int, onOpen: () -> Unit) = GameCardCat(game, best, onOpen)

@Composable
private fun GameCardCat(game: MorningGame, best: Int, onOpen: () -> Unit) {
    val colors = Dawn.colors
    Row(
        Modifier.fillMaxWidth().pressable(onClick = onOpen).clip(RoundedCornerShape(Radius.l)).background(colors.tile).padding(Spacing.s).padding(start = Spacing.xxs),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
            Text(petString(game.title), style = DawnType.display(20), color = colors.onTile)
            Text(gameDetail(game, best), style = DawnType.footnote, color = DawnColors.NightTextSecondary)
        }
        GamePoster(game, 112.dp)
        PlayDisc()
    }
}

/**
 * The Play tab: the morning games, each on an ink card with its picture, what it
 * trains and its record.
 */
@Composable
fun PlayScreen() = PlayScreenCat()

@Composable
private fun PlayScreenCat() {
    val context = LocalContext.current
    val store = context.graph.store
    var playing by remember { androidx.compose.runtime.mutableStateOf<MorningGame?>(null) }
    var revision by remember { mutableLongStateOf(0) }
    val colors = Dawn.colors
    Column(Modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState()).padding(bottom = Spacing.l + uz.ata.dawnwick.ui.components.LocalNavBarSpace.current)) {
        Text(stringResource(R.string.tab_play), style = DawnType.display(34), color = colors.textPrimary,
            modifier = Modifier.padding(start = Spacing.s, top = Spacing.s))
        Column(Modifier.padding(horizontal = Spacing.s).padding(top = Spacing.xs), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            Text(stringResource(R.string.play_intro), style = DawnType.callout, color = colors.textSecondary, modifier = Modifier.padding(bottom = Spacing.xs))
            MorningGame.entries.forEach { game ->
                val best = remember(revision) { game.best(store) }
                Row(
                    Modifier.fillMaxWidth().pressable(onClick = { playing = game }).clip(RoundedCornerShape(Radius.xl)).background(colors.tile)
                        .padding(Spacing.s).padding(start = Spacing.xxs),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.s),
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
                        Text(stringResource(game.skill).uppercase(), style = DawnType.eyebrow, color = DawnColors.Yolk)
                        Text(petString(game.title), style = DawnType.display(21), color = colors.onTile)
                        Text(gameDetail(game, best), style = DawnType.footnote, color = DawnColors.NightTextSecondary)
                    }
                    // The picture, with the play button tucked into its corner.
                    Box {
                        Box(Modifier.padding(end = 22.dp, bottom = 14.dp)) { GamePoster(game, 112.dp) }
                        Box(Modifier.align(Alignment.BottomEnd)) { PlayDisc(36.dp) }
                    }
                }
            }
        }
    }
    playing?.let { game -> GameHost(game) { playing = null; revision++ } }
}

/** Dims a disabled control the way the app's buttons do. */
fun Modifier.dimmed(enabled: Boolean) = alpha(if (enabled) 1f else 0.35f)
