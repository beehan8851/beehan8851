package uz.ata.dawnwick.ui.games

import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.rounded.AllInclusive
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CleaningServices
import androidx.compose.material.icons.rounded.Lightbulb
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.sin
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uz.ata.dawnwick.R
import uz.ata.dawnwick.games.CatNapDay
import uz.ata.dawnwick.games.CatNapGame
import uz.ata.dawnwick.games.CatNapLevel
import uz.ata.dawnwick.games.CatNapRecord
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatSounds
import uz.ata.dawnwick.ui.cat.Shapes
import uz.ata.dawnwick.ui.cat.at
import uz.ata.dawnwick.ui.cat.glyph
import uz.ata.dawnwick.ui.cat.reduceMotion
import uz.ata.dawnwick.ui.components.CircleIconButton
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.components.SoftButton
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnTheme
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/** 1:42, or 1:02:09 for a long one. */
fun napClock(seconds: Int): String =
    if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60) else "%d:%02d".format(seconds / 60, seconds % 60)

@Composable
fun levelName(level: CatNapLevel): String = stringArrayResource(R.array.difficulty)[level.ordinal]

private enum class NapScreen { INTRO, BOARD, SOLVED }

/**
 * Cat Naps: today's puzzles, three a day like a newspaper's — easy, medium and hard.
 * Put a cat to sleep on every cushion — one to a row, a column and a cushion, none
 * touching. A tap rules a cell out, a second puts a cat on it, a third clears it; a
 * finger drawn across the board rules out a run of cells. Each result offers the next
 * level up.
 */
@Composable
fun CatNapScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val record = remember { CatNapRecord(graph.store) }
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val still = reduceMotion()
    val premium = graph.isPremium
    val unlimitedOpen = premium

    val today = remember { CatNapDay.number() }
    var number by remember { mutableIntStateOf(today) }
    var level by remember { mutableStateOf(record.lastLevel()) }
    var unlimitedSeed by remember { mutableStateOf<ULong?>(null) }
    var autoStart by remember { mutableStateOf(false) }
    var game by remember { mutableStateOf<CatNapGame?>(null) }
    var screen by remember { mutableStateOf(NapScreen.INTRO) }
    var solve by remember { mutableStateOf<CatNapRecord.Solve?>(null) }
    var solvedLevels by remember { mutableStateOf<Map<CatNapLevel, CatNapRecord.Solve>>(emptyMap()) }
    var stats by remember { mutableStateOf(CatNapRecord.UnlimitedStats()) }
    var newBest by remember { mutableStateOf(false) }
    var archive by remember { mutableStateOf(false) }
    var solvedAt by remember { mutableStateOf<Long?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    val isUnlimited = unlimitedSeed != null
    val isToday = number == today
    val streak = remember(revision, screen) { record.streak(today) }

    fun save(g: CatNapGame) {
        if (g.solved) return
        val now = System.currentTimeMillis()
        if (g.isUntouched && g.elapsed(now) < 1) record.forget(g.number, g.level) else record.save(g.progress(now))
    }
    fun pause(g: CatNapGame) { g.pause(System.currentTimeMillis()); save(g) }

    fun start() {
        val g = game ?: return
        haptics.perform(Haptic.MEDIUM)
        newBest = false
        solvedAt = null
        // Again from the start, on a fresh board.
        val playing = if (g.solved) CatNapGame(number, level, g.puzzle).also { game = it } else g
        playing.resume(System.currentTimeMillis())
        screen = NapScreen.BOARD
        revision++
    }

    // A big board takes a moment to make: off the main thread.
    LaunchedEffect(number, level, unlimitedSeed) {
        val n = number; val l = level; val seed = unlimitedSeed
        game = null
        solvedLevels = if (seed == null) record.solves(n) else emptyMap()
        solve = solvedLevels[l]
        stats = record.stats(l)
        val puzzle = withContext(Dispatchers.Default) { seed?.let { CatNapDay.puzzle(it, l) } ?: CatNapDay.puzzle(n, l) }
        game = CatNapGame(n, l, puzzle, record.progress(n, l))
        if (autoStart) { autoStart = false; start() }
    }

    fun open(picked: Int, to: CatNapLevel? = null, play: Boolean = false) {
        game?.let { if (screen == NapScreen.BOARD) pause(it) }
        unlimitedSeed = null
        number = picked
        if (to != null) level = to
        autoStart = play
        screen = NapScreen.INTRO
    }

    fun seedFor(l: CatNapLevel, fresh: Boolean): ULong? {
        if (!fresh) record.unlimitedSeed(l)?.let { return it }
        if (unlimitedOpen) return record.newUnlimitedSeed(l)
        if (record.freeTriesLeft() > 0) { record.useFreeTry(); return record.newUnlimitedSeed(l) }
        android.widget.Toast.makeText(context, R.string.premium_soon, android.widget.Toast.LENGTH_LONG).show()
        return null
    }

    fun openUnlimited(fresh: Boolean, play: Boolean = false) {
        val seed = seedFor(level, fresh) ?: return
        game?.let { if (screen == NapScreen.BOARD) pause(it) }
        number = CatNapDay.UNLIMITED
        unlimitedSeed = seed
        autoStart = play
        screen = NapScreen.INTRO
    }

    fun finish(g: CatNapGame) {
        val now = System.currentTimeMillis()
        solvedAt = now
        val seconds = max(1, Math.round(g.elapsed(now)).toInt())
        record.setLastLevel(level)
        if (isUnlimited) {
            newBest = record.submitUnlimited(level, seconds) && stats.solved > 0
            stats = record.stats(level)
        } else {
            newBest = record.submit(number, level, seconds, g.hints, isToday)
            solvedLevels = record.solves(number)
            record.forget(number, level)
        }
        solve = CatNapRecord.Solve(seconds, g.hints, isToday)
        haptics.perform(Haptic.SUCCESS)
        CatSounds.mrrp()
        scope.launch {
            delay(if (still) 800 else 2200)
            if (screen == NapScreen.BOARD) screen = NapScreen.SOLVED
        }
    }

    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) { game?.let { if (screen == NapScreen.BOARD) pause(it) } }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { game?.let { if (screen == NapScreen.BOARD) it.resume(System.currentTimeMillis()) } }
    val close = { game?.let { if (screen == NapScreen.BOARD) pause(it) }; onClose() }

    GamePhases(screen) { s ->
        when (s) {
            NapScreen.INTRO -> GamePage(close, picture = {
                CatNapPoster(Modifier.widthIn(max = 190.dp).fillMaxWidth().padding(bottom = Spacing.xs))
            }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
                    Text(
                        if (isUnlimited) stringResource(R.string.naps_unlimited_eyebrow).uppercase() else puzzleLine(number),
                        style = DawnType.eyebrow, color = Dawn.colors.textSecondary, textAlign = TextAlign.Center,
                    )
                    GameTitle(stringResource(R.string.game_naps))
                }
                GameRules(stringResource(R.string.naps_rules))
                LevelPicker(level, solvedLevels) { option ->
                    if (option == level) return@LevelPicker
                    if (isUnlimited) unlimitedSeed = seedFor(option, false) ?: return@LevelPicker
                    haptics.perform(Haptic.SELECTION)
                    level = option
                    record.setLastLevel(option)
                }
                Box(Modifier.heightIn(min = 36.dp)) {
                    val current = solve
                    when {
                        isUnlimited && !unlimitedOpen -> GameChip(stringResource(R.string.naps_free_tries, record.freeTriesLeft()))
                        isUnlimited -> stats.bestSeconds?.let { GameChip(stringResource(R.string.naps_best_solved, napClock(it), stats.solved)) }
                        current != null -> GameChip(stringResource(R.string.naps_solved_in, napClock(current.seconds)))
                        isToday && streak > 0 -> GameChip(stringResource(R.string.naps_streak, streak))
                    }
                }
                val g = game
                InkButton(::start, enabled = g != null) {
                    if (g == null) CircularProgressIndicator(color = DawnColors.Yolk, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                    else Text(stringResource(when {
                        solve != null -> R.string.game_play_again
                        !g.isUntouched -> R.string.naps_carry_on
                        else -> R.string.game_play
                    }))
                }
                Row {
                    if (isUnlimited) QuietButton(stringResource(R.string.naps_today), Modifier.weight(1f)) { open(today) }
                    else {
                        QuietButton(stringResource(R.string.naps_past), Modifier.weight(1f)) { archive = true }
                        QuietButton(stringResource(R.string.naps_unlimited), Modifier.weight(1f), trailing = { UnlimitedBadge(unlimitedOpen, record) }) { openUnlimited(false) }
                    }
                }
            }
            NapScreen.BOARD -> game?.let { g ->
                NapBoard(g, isUnlimited, number, level, solvedAt, revision, premium, close, onChanged = {
                    revision++
                    save(g)
                    if (g.solved && solvedAt == null) finish(g)
                })
            }
            NapScreen.SOLVED -> SolvedPage(
                close, newBest, solve?.seconds ?: 0, game?.hints ?: 0, isUnlimited, stats.solved, isToday, streak, level,
                unlimitedOpen, record,
                onNextLevel = { next -> open(number, next, play = true) },
                onUnlimited = { openUnlimited(true, play = true) },
                onToday = { open(today) },
                onArchive = { archive = true },
                onShare = {
                    val lines = mutableListOf(context.getString(R.string.naps_share_text, number, context.resources.getStringArray(R.array.difficulty)[level.ordinal], napClock(solve?.seconds ?: 0)))
                    if ((game?.hints ?: 0) == 0) lines += context.getString(R.string.naps_no_hints)
                    lines += "😴".repeat(game?.size ?: 0)
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, lines.joinToString("\n")), null))
                },
            )
        }
    }
    if (archive) NapArchive(today, record, onClose = { archive = false }) { picked -> archive = false; open(picked) }
}

@Composable
private fun puzzleLine(number: Int): String {
    val day = CatNapDay.date(number).format(DateTimeFormatter.ofPattern("EEEE, d MMM", Locale.getDefault()))
    return stringResource(R.string.naps_puzzle_line, number, day).uppercase()
}

@Composable
private fun UnlimitedBadge(open: Boolean, record: CatNapRecord) {
    if (open) return
    val left = record.freeTriesLeft()
    Spacer(Modifier.width(6.dp))
    if (left > 0) Text(stringResource(R.string.naps_n_free, left), style = DawnType.footnote.copy(fontWeight = FontWeight.Black), color = DawnColors.Ink,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(DawnColors.Yolk).padding(horizontal = 7.dp, vertical = 2.dp))
}

/** Easy, medium, hard: the board's size under each, a tick on those solved. */
@Composable
private fun LevelPicker(level: CatNapLevel, solved: Map<CatNapLevel, CatNapRecord.Solve>, pick: (CatNapLevel) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        CatNapLevel.entries.forEach { option ->
            val chosen = option == level
            val fg = if (chosen) DawnColors.Yolk else DawnColors.Ink
            Column(
                Modifier.weight(1f).heightIn(min = 52.dp).pressable { pick(option) }.clip(RoundedCornerShape(Radius.m))
                    .background(if (chosen) DawnColors.Ink else DawnColors.Ink.copy(alpha = 0.07f)).padding(vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(levelName(option), style = DawnType.headline.copy(fontSize = 15.sp, fontWeight = FontWeight.Black), color = fg)
                    if (solved[option] != null) Icon(Icons.Rounded.Check, null, tint = fg, modifier = Modifier.padding(start = 4.dp).size(14.dp))
                }
                Text("${option.size} × ${option.size}", style = DawnType.footnote.copy(fontWeight = FontWeight.SemiBold), color = fg.copy(alpha = 0.7f))
            }
        }
    }
}

@Composable
private fun NapBoard(
    game: CatNapGame, unlimited: Boolean, number: Int, level: CatNapLevel, solvedAt: Long?, revision: Int, premium: Boolean,
    onClose: () -> Unit, onChanged: () -> Unit,
) {
    BackHandler(onBack = onClose)
    val haptics = rememberHaptics()
    // The clock ticks once a second; the cats breathe every frame.
    val now = frameClock(true)
    Column(Modifier.fillMaxSize().padding(horizontal = Spacing.s).padding(bottom = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.s),
        horizontalAlignment = Alignment.CenterHorizontally) {
        GameTopBar(onClose, trailing = {
            CircleIconButton(Icons.AutoMirrored.Rounded.Undo, stringResource(R.string.naps_undo), {
                haptics.perform(Haptic.SELECTION); game.undo(); onChanged()
            }, enabled = game.canUndo)
        }) {
            Text(napClock(game.elapsed(now).toInt()), style = DawnType.display(28), color = DawnColors.Ink, modifier = Modifier.clearAndSetSemantics {})
        }
        Text(
            if (unlimited) stringResource(R.string.naps_unlimited_line, levelName(level), level.size)
            else stringResource(R.string.naps_board_line, number, levelName(level), level.size),
            style = DawnType.eyebrow, color = Dawn.colors.textSecondary,
        )
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            val side = minOf(maxWidth, maxHeight, 560.dp)
            NapGrid(game, now, solvedAt, revision, Modifier.size(side), haptics, onChanged)
        }
        // What the board says, without a word more than it needs.
        val (line, color) = when {
            game.solved -> stringResource(R.string.naps_all_asleep) to DawnColors.Ink
            game.clashing.isNotEmpty() -> stringResource(R.string.naps_too_close) to NapArt.clash
            game.catCount == 0 -> stringResource(R.string.naps_tip) to Dawn.colors.textSecondary
            else -> stringResource(R.string.naps_count, game.catCount, game.size) to Dawn.colors.textSecondary
        }
        HintLine(line, strong = false, color = color)
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.s)) {
            SoftButton({ haptics.perform(Haptic.LIGHT); game.clear(); onChanged() }, Modifier.weight(1f), enabled = !game.isUntouched && !game.solved) {
                ButtonLabel(stringResource(R.string.clear), Icons.Rounded.CleaningServices)
            }
            SoftButton({
                if (!premium) return@SoftButton
                haptics.perform(Haptic.MEDIUM); game.hint(System.currentTimeMillis()); onChanged()
            }, Modifier.weight(1f), enabled = !game.solved) {
                ButtonLabel(stringResource(R.string.naps_hint), Icons.Rounded.Lightbulb)
            }
        }
    }
}

/**
 * The board, drawn, and one gesture for taps and strokes: a finger that lifts on the
 * cell it came down on is a tap; one that moves on paints every cell it crosses the
 * way the first one went — ruled out, or cleared.
 */
@Composable
private fun NapGrid(
    game: CatNapGame, now: Long, solvedAt: Long?, revision: Int, modifier: Modifier,
    haptics: uz.ata.dawnwick.ui.haptics.Haptics, onChanged: () -> Unit,
) {
    val still = reduceMotion()
    Canvas(
        modifier.pointerInput(game) {
            val n = game.size
            fun index(o: Offset): Int? {
                val cell = size.width / n.toFloat()
                val column = (o.x / cell).toInt()
                val row = (o.y / cell).toInt()
                return if (o.x < 0 || o.y < 0 || row >= n || column >= n) null else row * n + column
            }
            awaitEachGesture {
                val down = awaitFirstDown()
                val start = index(down.position) ?: return@awaitEachGesture
                var paint: CatNapGame.Cell? = null
                var painting = false
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) break
                    val at = index(change.position) ?: continue
                    if (!painting) {
                        if (at == start) continue
                        painting = true
                        paint = when (game.cells[start]) {
                            CatNapGame.Cell.EMPTY -> CatNapGame.Cell.MARK
                            CatNapGame.Cell.MARK -> CatNapGame.Cell.EMPTY
                            CatNapGame.Cell.CAT -> null
                        }
                        paint?.let { game.beginStroke(); game.paint(start, it, System.currentTimeMillis()); onChanged() }
                    }
                    val p = paint
                    if (p != null && game.cells[at] != p && game.cells[at] != CatNapGame.Cell.CAT) {
                        game.paint(at, p, System.currentTimeMillis())
                        haptics.perform(Haptic.SELECTION)
                        onChanged()
                    }
                    change.consume()
                }
                if (!painting) {
                    val hadClash = game.clashing.isNotEmpty()
                    val placed = game.tap(start, System.currentTimeMillis())
                    haptics.perform(when {
                        placed == CatNapGame.Cell.CAT && !hadClash && game.clashing.isNotEmpty() -> Haptic.RIGID
                        placed == CatNapGame.Cell.CAT -> Haptic.SOFT
                        else -> Haptic.SELECTION
                    })
                    onChanged()
                }
            }
        },
    ) {
        if (revision < 0) return@Canvas
        val n = game.size
        val cell = size.width / n
        val marks = game.cells.indices.filter { game.cells[it] == CatNapGame.Cell.MARK }.toSet()
        with(NapArt) { drawBoard(n, game.puzzle.regions, cell, game.clashing, marks, max(2.5f, cell / 15)) }
        val t = now / 1000.0 % 100_000
        game.cells.forEachIndexed { index, value ->
            if (value != CatNapGame.Cell.CAT) return@forEachIndexed
            val rect = Rect(index % n * cell, index / n * cell, (index % n + 1) * cell, (index / n + 1) * cell)
            // Dropped onto the cushion: a little too big, then settling.
            var scale = 1f
            val placed = game.placedAt[index]
            if (placed != null && !still) {
                val p = ((now - placed) / 280.0).coerceIn(0.0, 1.0)
                scale = (1 + 0.18 * sin(p * PI) * (1 - p)).toFloat()
            }
            val inset = cell * 0.05f
            val box = Rect(rect.left + inset, rect.top + inset, rect.right - inset, rect.bottom - inset)
            val scaled = Rect(box.center.x - box.width * scale / 2, box.center.y - box.height * scale / 2, box.center.x + box.width * scale / 2, box.center.y + box.height * scale / 2)
            val breath = if (still) 0f else sin(t * 2 * PI / 3.6 + index).toFloat()
            with(NapArt) { drawNapCat(scaled, index in game.awake, breath) }
            if (game.solved && !still && solvedAt != null) with(NapArt) { drawZ(rect, (now - solvedAt) / 1000.0, index / n * 0.12) }
        }
    }
}

@Composable
private fun SolvedPage(
    onClose: () -> Unit, newBest: Boolean, seconds: Int, hints: Int, unlimited: Boolean, unlimitedSolved: Int, isToday: Boolean, streak: Int,
    level: CatNapLevel, unlimitedOpen: Boolean, record: CatNapRecord,
    onNextLevel: (CatNapLevel) -> Unit, onUnlimited: () -> Unit, onToday: () -> Unit, onArchive: () -> Unit, onShare: () -> Unit,
) {
    GamePage(onClose, Spacing.s, picture = { CatMascot(CatMood.PROUD, Modifier.widthIn(max = 170.dp).fillMaxWidth().padding(bottom = Spacing.xs)) }) {
        GameTitle(stringResource(if (newBest) R.string.game_new_best else R.string.naps_all_asleep), 28)
        Text(napClock(seconds), style = DawnType.display(96), color = DawnColors.Ink, maxLines = 1)
        Row(Modifier.heightIn(min = 36.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            if (hints == 0) GameChip(stringResource(R.string.naps_no_hints))
            if (unlimited) GameChip(stringResource(R.string.naps_n_solved, unlimitedSolved))
            else if (isToday && streak > 0) GameChip(stringResource(R.string.naps_streak, streak))
        }
        if (unlimited) {
            InkButton(onUnlimited) { Text(stringResource(R.string.naps_next)); UnlimitedBadge(unlimitedOpen, record) }
            Row {
                QuietButton(stringResource(R.string.naps_today), Modifier.weight(1f), onClick = onToday)
                QuietButton(stringResource(R.string.done), Modifier.weight(1f), onClick = onClose)
            }
        } else {
            // The next level up while there is one; after the hardest, another puzzle.
            val next = level.next
            if (next != null) InkButton({ onNextLevel(next) }) { Text(stringResource(R.string.naps_try_level, levelName(next), next.size)) }
            else InkButton(onUnlimited) {
                Icon(Icons.Rounded.AllInclusive, null, Modifier.size(20.dp)); Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.naps_another)); UnlimitedBadge(unlimitedOpen, record)
            }
            SoftButton(onShare) { ButtonLabel(stringResource(R.string.naps_share), Icons.Rounded.Share) }
            Row {
                if (next == null) QuietButton(stringResource(R.string.naps_past), Modifier.weight(1f), onClick = onArchive)
                else QuietButton(stringResource(R.string.naps_unlimited), Modifier.weight(1f), trailing = { UnlimitedBadge(unlimitedOpen, record) }, onClick = onUnlimited)
                QuietButton(stringResource(R.string.done), Modifier.weight(1f), onClick = onClose)
            }
        }
        if (!unlimitedOpen) {
            Text(stringResource(if (record.freeTriesLeft() > 0) R.string.naps_free_note else R.string.naps_premium_note),
                style = DawnType.footnote, color = Dawn.colors.textSecondary, textAlign = TextAlign.Center)
        }
    }
}

/** Every day before today's, newest first, with a paw for each level solved. */
@Composable
private fun NapArchive(today: Int, record: CatNapRecord, onClose: () -> Unit, pick: (Int) -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DawnTheme(dark = false) {
            val colors = Dawn.colors
            Column(Modifier.fillMaxSize().background(colors.background).safeDrawingPadding()) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 4.dp)) {
                    IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.back), tint = colors.textPrimary) }
                    Text(stringResource(R.string.naps_past), style = DawnType.headline, color = colors.textPrimary)
                }
                if (today <= 1) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.naps_no_past), style = DawnType.headline, color = colors.textSecondary)
                    }
                } else LazyColumn(Modifier.padding(horizontal = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    items((1 until today).reversed().toList()) { n ->
                        val solved = remember(n) { record.solves(n) }
                        Row(
                            Modifier.fillMaxWidth().pressable { pick(n) }.clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary).padding(Spacing.s),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.naps_past_number, n), style = DawnType.headline.copy(fontWeight = FontWeight.Black), color = colors.textPrimary)
                                Text(CatNapDay.date(n).format(DateTimeFormatter.ofPattern("EEEE, d MMMM", Locale.getDefault())), style = DawnType.footnote, color = colors.textSecondary)
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                CatNapLevel.entries.forEach { l ->
                                    Canvas(Modifier.size(16.dp)) {
                                        drawPath(Shapes.pawPrint(Rect(Offset.Zero, size)), if (solved[l] != null) DawnColors.Ink else DawnColors.Ink.copy(alpha = 0.15f))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** The game's picture on its intro and on the cards: a little board, three cats asleep. */
@Composable
fun CatNapPoster(modifier: Modifier = Modifier) {
    Canvas(modifier.aspectRatio(1f).clearAndSetSemantics {}) {
        val n = 4
        val cell = size.minDimension / n
        with(NapArt) {
            drawBoard(n, POSTER_REGIONS, cell, emptySet(), emptySet(), max(2f, cell / 16))
            for (index in listOf(1, 7, 8)) {
                val r = Rect(index % n * cell, index / n * cell, (index % n + 1) * cell, (index / n + 1) * cell)
                drawNapCat(r.deflate(cell * 0.06f), false, 0f)
            }
        }
    }
}

/** A 4 × 4 cut into four cushions, three of its four cats in place. */
private val POSTER_REGIONS = listOf(0, 0, 1, 1, 0, 1, 1, 1, 2, 2, 3, 1, 2, 3, 3, 3)

/**
 * How Cat Naps looks: cushions in soft print colours with an ink line around each, and
 * on them the white cat curled up asleep, or sitting up wide awake when it has been
 * put too close to another. Drawn in code like the rest of the cat.
 */
object NapArt {
    val ink = Color(0xFF1C1A17)
    private val fur = Color(0xFFFFFCF8)
    private val furShade = Color(0xFFE6DCCB)
    private val earInner = Color(0xFFF7A38E)
    private val nose = Color(0xFFF08B76)
    val clash = Color(0xFFD9483B)
    private val cushions = listOf(
        Color(0xFFFFC629), Color(0xFF9CC5E0), Color(0xFFF4A27A), Color(0xFFA9C79B), Color(0xFFC9B6E4),
        Color(0xFFE9D3AE), Color(0xFFF2B4C2), Color(0xFF86CDBF), Color(0xFFD3DA8C),
    )

    fun cushion(region: Int) = cushions[region % cushions.size]

    /** The cushions and the lines: thin between cells of one cushion, thick where two meet and round the edge. */
    fun DrawScope.drawBoard(n: Int, regions: List<Int>, cell: Float, clashing: Set<Int>, marks: Set<Int>, thick: Float) {
        val side = cell * n
        val corner = cell * 0.22f
        val frame = Path().apply { addRoundRect(RoundRect(0f, 0f, side, side, CornerRadius(corner))) }
        clipPath(frame) {
            for (index in 0 until n * n) {
                drawRect(cushion(regions[index]), Offset(index % n * cell, index / n * cell), Size(cell, cell))
            }
            if (clashing.isNotEmpty()) {
                val stripes = Path()
                val step = max(5f, cell / 5)
                var x = -side
                while (x < side) { stripes.moveTo(x, side); stripes.lineTo(x + side, 0f); x += step }
                for (index in clashing) {
                    val l = index % n * cell
                    val tp = index / n * cell
                    clipRect(l, tp, l + cell, tp + cell) {
                        drawRect(clash.copy(alpha = 0.16f), Offset(l, tp), Size(cell, cell))
                        drawPath(stripes, clash.copy(alpha = 0.55f), style = Stroke(max(1.2f, cell / 22)))
                    }
                }
            }
            val thin = Path()
            for (i in 1 until n) {
                val p = i * cell
                thin.moveTo(p, 0f); thin.lineTo(p, side)
                thin.moveTo(0f, p); thin.lineTo(side, p)
            }
            drawPath(thin, ink.copy(alpha = 0.18f), style = Stroke(1.dp.toPx()))
            val walls = Path()
            for (row in 0 until n) for (column in 0 until n) {
                val here = regions[row * n + column]
                if (column < n - 1 && regions[row * n + column + 1] != here) {
                    val x = (column + 1) * cell
                    walls.moveTo(x, row * cell); walls.lineTo(x, (row + 1) * cell)
                }
                if (row < n - 1 && regions[(row + 1) * n + column] != here) {
                    val y = (row + 1) * cell
                    walls.moveTo(column * cell, y); walls.lineTo((column + 1) * cell, y)
                }
            }
            drawPath(walls, ink, style = Stroke(thick, cap = StrokeCap.Square))
            for (index in marks) {
                val c = Offset((index % n + 0.5f) * cell, (index / n + 0.5f) * cell)
                val r = cell * 0.11f
                val w = max(1.5f, cell / 22)
                drawLine(ink.copy(alpha = 0.5f), Offset(c.x - r, c.y - r), Offset(c.x + r, c.y + r), w, StrokeCap.Round)
                drawLine(ink.copy(alpha = 0.5f), Offset(c.x + r, c.y - r), Offset(c.x - r, c.y + r), w, StrokeCap.Round)
            }
        }
        drawRoundRect(ink, Offset(thick / 2, thick / 2), Size(side - thick, side - thick), CornerRadius(corner - thick / 2), style = Stroke(thick))
    }

    /** The cat in a 100 × 100 square: curled asleep, or sitting up with its eyes open. `breath` −1…1 lifts the curl. */
    fun DrawScope.drawNapCat(rect: Rect, awake: Boolean, breath: Float) {
        val k = minOf(rect.width, rect.height) / 100
        val line = Stroke(4.5f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        at(rect.center.x - 50 * k, rect.center.y - 50 * k, sx = k) {
            if (awake) { awakeCat(line); return@at }
            val lift = breath * 1.6f
            val body = Shapes.ellipse(14f, 40 - lift, 74f, 46 + lift)
            drawPath(body, fur)
            clipPath(body) { drawOval(furShade, Offset(10f, 66f), Size(84f, 30f)) }
            drawPath(body, ink, style = line)
            val tail = Path().apply { moveTo(84f, 68f); cubicTo(84f, 86f, 58f, 88f, 40f, 82f) }
            drawPath(tail, ink, style = Stroke(12.5f, cap = StrokeCap.Round))
            drawPath(tail, fur, style = Stroke(4.5f, cap = StrokeCap.Round))
            at(38f, 54 - lift * 0.6f, -8f) { head(line, false) }
        }
    }

    private fun DrawScope.awakeCat(line: Stroke) {
        val tail = Path().apply { moveTo(66f, 78f); cubicTo(84f, 70f, 78f, 46f, 80f, 30f) }
        drawPath(tail, ink, style = Stroke(12.5f, cap = StrokeCap.Round))
        drawPath(tail, fur, style = Stroke(4.5f, cap = StrokeCap.Round))
        val body = Path().apply {
            moveTo(36f, 50f); cubicTo(28f, 62f, 22f, 84f, 28f, 90f); lineTo(72f, 90f); cubicTo(78f, 84f, 72f, 62f, 64f, 50f); close()
        }
        drawPath(body, fur)
        drawPath(body, ink, style = line)
        at(50f, 38f) { head(line, true) }
    }

    /** A head centred on the origin, 52 across. */
    private fun DrawScope.head(line: Stroke, eyesOpen: Boolean) {
        val ears = listOf(
            listOf(Offset(-24f, -6f), Offset(-20f, -30f), Offset(-4f, -19f)),
            listOf(Offset(24f, -6f), Offset(20f, -30f), Offset(4f, -19f)),
        )
        for (ear in ears) {
            val path = Shapes.roundedPolygon(ear, 3f)
            drawPath(path, fur)
            drawPath(path, ink, style = line)
            drawPath(Shapes.roundedPolygon(listOf(Offset(ear[0].x * 0.8f, -9f), Offset(ear[1].x * 0.95f, -24f), Offset(ear[2].x * 1.6f, -17f)), 2f), earInner)
        }
        val face = Shapes.ellipse(-26f, -21f, 52f, 44f)
        drawPath(face, fur)
        drawPath(face, ink, style = line)
        if (eyesOpen) {
            for (x in listOf(-10.5f, 10.5f)) {
                drawOval(ink, Offset(x - 5, -6f), Size(10f, 11f))
                drawOval(fur, Offset(x - 1.5f, -4.5f), Size(3.6f, 3.6f))
            }
        } else {
            for (x in listOf(-11f, 11f)) {
                drawPath(Path().apply { moveTo(x - 6, 0f); quadraticTo(x, 6f, x + 6, 0f) }, ink, style = Stroke(3.6f, cap = StrokeCap.Round))
            }
        }
        drawPath(Shapes.roundedPolygon(listOf(Offset(-3.5f, 6f), Offset(3.5f, 6f), Offset(0f, 10f)), 1f), nose)
    }

    /** Zzz, for the solved board: a few seconds' rise and fade, `t` from 0. */
    fun DrawScope.drawZ(rect: Rect, t: Double, delay: Double) {
        val phase = t - delay
        if (phase <= 0) return
        val local = phase % 2.4 / 2.4
        val fade = sin(local * PI).toFloat()
        val size = rect.width * 0.34f
        glyph("z", Offset(rect.right - size * 0.4f, rect.top + size * 0.2f - local.toFloat() * rect.height * 0.5f), size, ink.copy(alpha = 0.75f * fade))
    }
}
