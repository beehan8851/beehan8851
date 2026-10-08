package uz.ata.dawnwick.ui.sleep

import android.app.Activity
import android.view.WindowManager
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.UnfoldMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.min
import uz.ata.dawnwick.R
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.sleep.BreathPacer
import uz.ata.dawnwick.sleep.SleepEntry
import uz.ata.dawnwick.sleep.SleepHistory
import uz.ata.dawnwick.sleep.SleepSession
import uz.ata.dawnwick.sleep.SleepSound
import uz.ata.dawnwick.sleep.WindDownNote
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatTricksProvider
import uz.ata.dawnwick.ui.cat.reduceMotion
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.components.keepAboveKeyboard
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnTheme
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

@Composable
private fun Page(title: String, onClose: () -> Unit, dark: Boolean? = null, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        if (dark != null) DawnTheme(dark) { CatTricksProvider { PageBody(title, onClose, content) } }
        else DawnTheme { CatTricksProvider { PageBody(title, onClose, content) } }
    }
}

@Composable
private fun PageBody(title: String, onClose: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(Dawn.colors.background).safeDrawingPadding()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 4.dp)) {
            IconButton(onClick = onClose) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, stringResource(R.string.back), tint = Dawn.colors.textPrimary) }
            Text(title, style = DawnType.headline, color = Dawn.colors.textPrimary)
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Spacing.s).padding(bottom = Spacing.l), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
            content()
        }
    }
}

@Composable
private fun Card(title: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        if (title != null) Text(title.uppercase(), style = DawnType.section, color = Dawn.colors.textSecondary, modifier = Modifier.padding(start = 4.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary)) { content() }
    }
}

@Composable
private fun LabeledRow(label: String, value: String, divider: Boolean = false) {
    if (divider) Box(Modifier.padding(start = Spacing.s).fillMaxWidth().height(0.5.dp).background(Dawn.colors.separator))
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = DawnType.body, color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
        Text(value, style = DawnType.body, color = Dawn.colors.textSecondary)
    }
}

/** The night just ended: how long, when, what disturbed it, what played. */
@Composable
fun SleepResult(session: SleepSession, onDone: () -> Unit) {
    val context = LocalContext.current
    Page(stringResource(R.string.sleep_recorded), onDone) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.xl)).background(Dawn.colors.heroBand).padding(start = 20.dp, end = Spacing.s, top = 12.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.sleep_total), style = DawnType.headline, color = Dawn.colors.onHeroSecondary)
                Text(session.durationMillis?.let { sleepDuration(it) } ?: "—", style = DawnType.display(48), color = Dawn.colors.onHero)
            }
            CatMascot(CatMood.AWAKE, Modifier.width(96.dp))
        }
        Card {
            LabeledRow(stringResource(R.string.sleep_fell_asleep), TimeFormat.clock(context, session.startMillis))
            session.endMillis?.let { LabeledRow(stringResource(R.string.sleep_woke_up), TimeFormat.clock(context, it), divider = true) }
        }
        if (session.noiseEvents.isNotEmpty()) {
            Card(pluralStringResource(R.plurals.noise_events, session.noiseEvents.size, session.noiseEvents.size)) {
                session.noiseEvents.forEachIndexed { i, e ->
                    LabeledRow(TimeFormat.clock(context, e.timestampMillis), stringResource(when {
                        e.peakDecibels > -20 -> R.string.noise_loud
                        e.peakDecibels > -35 -> R.string.noise_moderate
                        else -> R.string.noise_soft
                    }), divider = i > 0)
                }
            }
        }
        Card {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Icon(soundIcon(session.soundUsed), null, tint = Dawn.colors.accent, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(Spacing.sm))
                Text(stringResource(soundName(session.soundUsed)), style = DawnType.body, color = Dawn.colors.textPrimary)
            }
        }
        YolkButton(onClick = onDone) { ButtonLabel(stringResource(R.string.done)) }
    }
}

/** The last seven nights as bars against an eight-hour line, the average, and every night recorded. */
@Composable
fun SleepReport(sessions: List<SleepSession>, health: List<SleepEntry>, onClose: () -> Unit) {
    val days = SleepHistory.merge(sessions, health)
    val colors = Dawn.colors
    Page(stringResource(R.string.sleep_history_title), onClose) {
        if (days.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(top = Spacing.xl), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
                CatMascot(CatMood.SLEEPING, Modifier.width(150.dp), ground = if (colors.isDark) CatGround.DARK else CatGround.LIGHT)
                Text(stringResource(R.string.sleep_history_empty), style = DawnType.title, color = colors.textPrimary, textAlign = TextAlign.Center)
                Text(stringResource(R.string.sleep_history_empty_detail), style = DawnType.callout, color = colors.textSecondary, textAlign = TextAlign.Center)
            }
            return@Page
        }
        val today = LocalDate.now()
        val week = (6 downTo 0).map { today.minusDays(it.toLong()) }.map { d -> d to days.firstOrNull { it.date == d }?.durationMillis }
        val ceiling = maxOf(8 * 3600_000L, week.mapNotNull { it.second }.maxOrNull() ?: 0L)
        Card {
            Column(Modifier.padding(Spacing.s)) {
                val barArea = 96.dp
                Box(Modifier.fillMaxWidth().height(barArea)) {
                    val guide = 8 * 3600_000f / ceiling
                    Row(Modifier.fillMaxWidth().offset(y = barArea * (1 - guide) - 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f).height(1.dp).background(colors.separator))
                        Spacer(Modifier.width(4.dp))
                        Text(stringResource(R.string.eight_hours), style = DawnType.eyebrow, color = colors.textTertiary)
                    }
                    Row(Modifier.fillMaxSize().padding(end = 28.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.xs), verticalAlignment = Alignment.Bottom) {
                        week.forEach { (_, d) ->
                            val h = if (d == null) 4.dp else maxOf(4.dp, barArea * (d.toFloat() / ceiling))
                            Box(Modifier.weight(1f).height(h).clip(RoundedCornerShape(2.dp))
                                .background(if (d == null) colors.textTertiary.copy(alpha = 0.4f) else if (colors.isDark) DawnColors.Yolk else DawnColors.Ink))
                        }
                    }
                }
                Spacer(Modifier.height(Spacing.xs))
                Row(Modifier.fillMaxWidth().padding(end = 28.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    week.forEach { (day, _) ->
                        Text(day.dayOfWeek.getDisplayName(TextStyle.NARROW_STANDALONE, Locale.getDefault()), style = DawnType.eyebrow,
                            color = if (day == today) colors.textPrimary else colors.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
        val values = days.mapNotNull { it.durationMillis }
        if (values.isNotEmpty()) {
            Card(stringResource(R.string.sleep_average)) { LabeledRow(stringResource(R.string.sleep_per_night), sleepDuration(values.sum() / values.size)) }
        }
        Card(stringResource(R.string.sleep_recent_nights)) {
            days.forEachIndexed { i, day ->
                if (i > 0) Box(Modifier.padding(start = Spacing.s).fillMaxWidth().height(0.5.dp).background(colors.separator))
                Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(day.date.format(DateTimeFormatter.ofPattern("EEEE, d MMM", Locale.getDefault())).replaceFirstChar { it.uppercase() },
                            style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = colors.textPrimary)
                        Text(stringResource(if (day.tracked) R.string.sleep_source_tracked else R.string.sleep_source_health), style = DawnType.footnote, color = colors.textSecondary)
                    }
                    Text(day.durationMillis?.let { sleepDuration(it) } ?: "—", style = DawnType.callout, color = colors.textSecondary)
                }
            }
        }
    }
}

/**
 * The wind-down, at night colours: a length, a sound, and anything on your mind
 * written down for the morning; then a few minutes breathing with the cat — in for
 * four, out for six, a soft tap at each turn — and the screen dimming as it goes.
 */
@Composable
fun WindDown(nextAlarm: Long?, onStartTracking: () -> Unit, onClose: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val tracker = graph.sleep
    val haptics = rememberHaptics()
    val still = reduceMotion()
    val pacer = remember { BreathPacer() }
    val player = remember { uz.ata.dawnwick.sleep.SleepAudio(context) }
    var stage by remember { mutableStateOf("setup") }
    var minutes by remember { mutableIntStateOf(graph.store.getInt(MINUTES_KEY, 5)) }
    var note by remember { mutableStateOf("") }
    var noteParked by remember { mutableStateOf(false) }
    var sound by remember { mutableStateOf(tracker.selectedSound) }
    var length by remember { mutableDoubleStateOf(0.0) }

    DisposableEffect(Unit) { onDispose { if (tracker.active.value == null) player.stop() } }

    fun begin() {
        noteParked = WindDownNote.park(note, graph.store, nextAlarm?.let(Instant::ofEpochMilli)) || noteParked
        if (noteParked) note = ""
        if (sound != SleepSound.NONE && tracker.active.value == null) player.play(sound)
        length = pacer.wholeBreaths(minutes)
        stage = "breathing"
    }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DawnTheme(dark = true) {
            val colors = Dawn.colors
            Box(Modifier.fillMaxSize().background(colors.background)) {
                AnimatedContent(stage, transitionSpec = { fadeIn(tween(800)) togetherWith fadeOut(tween(800)) }, label = "wind-down") { s ->
                    when (s) {
                        "setup" -> Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
                            Box(Modifier.padding(horizontal = Spacing.m, vertical = Spacing.xs).size(44.dp).clip(CircleShape).background(colors.surfacePrimary).pressable(onClick = onClose),
                                contentAlignment = Alignment.Center) { Icon(Icons.Rounded.Close, stringResource(R.string.close), tint = DawnColors.Paper) }
                            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = Spacing.m), verticalArrangement = Arrangement.spacedBy(Spacing.m)) {
                                Box(Modifier.fillMaxWidth().padding(top = Spacing.m), contentAlignment = Alignment.Center) {
                                    Box(Modifier.size(160.dp).clip(CircleShape).background(DawnColors.Yolk.copy(alpha = 0.08f)))
                                    CatMascot(CatMood.YAWNING, Modifier.width(118.dp), ground = CatGround.DARK)
                                }
                                Text(stringResource(R.string.wind_down_title), style = DawnType.display(34), color = DawnColors.Paper)
                                Text(stringResource(if (uz.ata.dawnwick.ui.cat.currentCompanion() == uz.ata.dawnwick.companion.Pet.CAT) R.string.wind_down_detail else R.string.wind_down_detail_pet), style = DawnType.callout, color = DawnColors.NightTextSecondary)
                                Text(stringResource(R.string.wind_down_length), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = DawnColors.NightTextSecondary)
                                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                                    listOf(3, 5, 10).forEach { m ->
                                        val chosen = m == minutes
                                        Box(
                                            Modifier.weight(1f).defaultMinSize(minHeight = 52.dp).clip(RoundedCornerShape(Radius.m))
                                                .background(if (chosen) DawnColors.Yolk else colors.surfacePrimary)
                                                .pressable { haptics.perform(Haptic.SELECTION); minutes = m; graph.store.putInt(MINUTES_KEY, m) },
                                            contentAlignment = Alignment.Center,
                                        ) { Text(stringResource(R.string.minutes_short, m), style = DawnType.button, color = if (chosen) DawnColors.Ink else DawnColors.Paper) }
                                    }
                                }
                                Text(stringResource(R.string.wind_down_sound), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = DawnColors.NightTextSecondary)
                                var menu by remember { mutableStateOf(false) }
                                Box {
                                    Row(
                                        Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary)
                                            .pressable { menu = true }.padding(horizontal = Spacing.s),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Icon(soundIcon(sound), null, tint = DawnColors.Yolk, modifier = Modifier.size(22.dp))
                                        Spacer(Modifier.width(Spacing.s))
                                        Text(stringResource(soundName(sound)), style = DawnType.body, color = DawnColors.Paper, modifier = Modifier.weight(1f))
                                        Icon(Icons.Rounded.UnfoldMore, null, tint = DawnColors.NightTextSecondary)
                                    }
                                    DropdownMenu(menu, { menu = false }) {
                                        SleepSound.entries.forEach { s2 ->
                                            DropdownMenuItem(text = { Text(stringResource(soundName(s2))) }, leadingIcon = { Icon(soundIcon(s2), null) },
                                                onClick = { sound = s2; tracker.selectedSound = s2; menu = false })
                                        }
                                    }
                                }
                                Text(stringResource(R.string.wind_down_mind), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = DawnColors.NightTextSecondary)
                                OutlinedTextField(
                                    value = note, onValueChange = { note = it.take(280) },
                                    placeholder = { Text(stringResource(R.string.wind_down_mind_hint), color = DawnColors.NightTextSecondary) },
                                    minLines = 2, maxLines = 5,
                                    shape = RoundedCornerShape(Radius.m),
                                    colors = OutlinedTextFieldDefaults.colors(
                                        unfocusedContainerColor = colors.surfacePrimary, focusedContainerColor = colors.surfacePrimary,
                                        unfocusedBorderColor = colors.surfacePrimary, focusedBorderColor = DawnColors.Yolk,
                                        focusedTextColor = DawnColors.Paper, unfocusedTextColor = DawnColors.Paper,
                                    ),
                                    modifier = Modifier.fillMaxWidth().keepAboveKeyboard(),
                                )
                                Spacer(Modifier.height(Spacing.s))
                            }
                            YolkButton(onClick = ::begin, modifier = Modifier.padding(horizontal = Spacing.m, vertical = Spacing.s)) { ButtonLabel(stringResource(R.string.wind_down_begin)) }
                        }
                        "breathing" -> Breathing(pacer, length, still, onTurn = { haptics.perform(Haptic.SOFT) }) {
                            haptics.perform(Haptic.SUCCESS)
                            stage = "done"
                        }
                        else -> Column(
                            Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = Spacing.m).padding(bottom = Spacing.s),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.m),
                        ) {
                            Spacer(Modifier.weight(1f))
                            CatMascot(CatMood.SLEEPING, Modifier.width(200.dp), ground = CatGround.DARK)
                            Text(stringResource(R.string.sleep_well), style = DawnType.display(34), color = DawnColors.Paper)
                            val lines = listOfNotNull(
                                if (noteParked) stringResource(R.string.wind_down_note_waiting) else null,
                                stringResource(if (tracker.active.value != null) R.string.wind_down_tracking_on else R.string.wind_down_start_then),
                            )
                            Text(lines.joinToString("\n"), style = DawnType.body, color = DawnColors.NightTextSecondary, textAlign = TextAlign.Center)
                            Spacer(Modifier.weight(1f))
                            if (tracker.active.value == null) {
                                YolkButton(onClick = { player.stopImmediate(); onStartTracking(); onClose() }) { ButtonLabel(stringResource(R.string.sleep_start)) }
                            }
                            Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).pressable(onClick = onClose), contentAlignment = Alignment.Center) {
                                Text(stringResource(R.string.close), style = DawnType.button, color = DawnColors.NightTextSecondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private const val MINUTES_KEY = "sleep.windDown.minutes"

@Composable
private fun Breathing(pacer: BreathPacer, length: Double, still: Boolean, onTurn: () -> Unit, onFinished: () -> Unit) {
    val activity = LocalContext.current as? Activity
    var elapsed by remember { mutableDoubleStateOf(0.0) }
    // The screen stays on while the cat breathes.
    DisposableEffect(Unit) {
        activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        var index = 0
        while (true) {
            val now = withFrameNanos { it }
            elapsed = (now - start) / 1e9
            if (elapsed >= length) { onFinished(); break }
            val m = pacer.moment(elapsed)
            if (m.index != index) { index = m.index; onTurn() }
        }
    }
    val moment = pacer.moment(elapsed)
    val fullness = ((moment.breath + 1) / 2).toFloat()
    val remaining = ceil(length - elapsed).toInt().coerceAtLeast(0)
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().drawWithContent {
            drawContent()
            // Darker as the session goes on.
            drawRect(Color.Black.copy(alpha = 0.55f * min(1f, (elapsed / length).toFloat())))
        },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Box(Modifier.fillMaxWidth().height(340.dp), contentAlignment = Alignment.Center) {
            for (ring in 0 until 3) {
                val base = 170f + ring * 56
                val grow = if (still) 0f else (36f + ring * 22) * fullness
                val alpha = (0.11f - ring * 0.03f) * (if (still) 0.5f + fullness else 1f)
                Canvas(Modifier.size((base + grow).dp)) { drawCircle(DawnColors.Yolk.copy(alpha = alpha)) }
            }
            CatMascot(
                CatMood.SLEEPING,
                Modifier.width(220.dp).offset(y = 18.dp).graphicsLayer {
                    val k = if (still) 1f else 1 + 0.04f * fullness
                    scaleX = k; scaleY = k; transformOrigin = TransformOrigin(0.5f, 1f)
                },
                ground = CatGround.DARK, animated = !still, breath = if (still) null else moment.breath,
            )
        }
        Spacer(Modifier.height(Spacing.l))
        val edge = min(moment.progress, 1 - moment.progress)
        Text(stringResource(if (moment.phase == BreathPacer.Phase.IN) R.string.breathe_in else R.string.breathe_out),
            style = DawnType.display(30), color = DawnColors.Paper, modifier = Modifier.alpha((0.25 + 0.75 * min(1.0, edge * 5 + 0.1)).toFloat()))
        Spacer(Modifier.height(Spacing.l))
        Text("%d:%02d".format(remaining / 60, remaining % 60), style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
            color = DawnColors.NightTextSecondary.copy(alpha = 0.7f))
        Spacer(Modifier.weight(1f))
        TextButton(onClick = onFinished, modifier = Modifier.padding(bottom = Spacing.m).defaultMinSize(minWidth = 120.dp)) {
            Text(stringResource(R.string.wind_down_end), style = DawnType.button, color = DawnColors.NightTextSecondary)
        }
    }
}

