package uz.ata.dawnwick.ui.ring

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.draw.alpha
import uz.ata.dawnwick.ui.cat.CatMotion
import uz.ata.dawnwick.ui.cat.CatMove
import uz.ata.dawnwick.ui.cat.CatStage
import uz.ata.dawnwick.ui.cat.STARTLE_HOLD_MS
import uz.ata.dawnwick.ui.cat.reduceMotion
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material3.Icon
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.Shapes
import uz.ata.dawnwick.ui.components.AlarmTimeText
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.missions.MissionView
import uz.ata.dawnwick.ui.missions.MissionCapability
import uz.ata.dawnwick.ui.missions.missionIcon
import uz.ata.dawnwick.ui.missions.missionName
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * The alarm, ringing: what it is, the time, the cat pawing at the glass, what turns
 * it off, and one button. All yolk: it is there to wake you. Snooze is there but
 * second, plain text under the button, with how many are left.
 */
@Composable
fun RingScreen(alarm: Alarm, snoozeCount: Int, onStartMission: () -> Unit, onSnooze: () -> Unit) {
    val context = LocalContext.current
    var startled by remember { mutableStateOf(true) }
    var startles by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        // The jump waits for the screen to finish arriving.
        delay(450)
        startles++
        delay(STARTLE_HOLD_MS)
        startled = false
    }
    val caption = listOf(alarm.label, ringSummary(context, alarm.recurrence)).filter { it.isNotBlank() }.joinToString(" · ")

    Column(
        Modifier.fillMaxSize().background(DawnColors.Yolk).safeDrawingPadding().padding(horizontal = Spacing.m),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(Spacing.xl))
        if (caption.isNotEmpty()) {
            Text(caption, style = DawnType.headline, color = DawnColors.OnYolkSecondary, textAlign = TextAlign.Center)
        }
        AlarmTimeText(alarm.wallClockTime, 96, DawnColors.Ink, periodColor = DawnColors.OnYolkSecondary)
        Spacer(Modifier.weight(1f))
        CatMotion(CatMove.STARTLE, startles, 200.dp) {
            Crossfade(startled, animationSpec = tween(200), label = "fright") { s ->
                CatStage(if (s) CatMood.STARTLED else CatMood.RINGING, Modifier.widthIn(max = 200.dp))
            }
        }
        Spacer(Modifier.weight(1f))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            alarm.missions.forEachIndexed { i, m ->
                if (i > 0) Icon(Icons.AutoMirrored.Rounded.ArrowForward, null, tint = DawnColors.OnYolkSecondary, modifier = Modifier.padding(horizontal = 6.dp).size(14.dp))
                Icon(missionIcon(m.kind), null, tint = DawnColors.Ink, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(missionName(m.kind), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = DawnColors.Ink)
            }
        }
        Spacer(Modifier.height(Spacing.m))
        InkButton(onClick = onStartMission) { ButtonLabel(stringResource(R.string.start_mission)) }
        if (alarm.snooze.isEnabled) {
            val atLimit = alarm.snooze.maxCount > 0 && snoozeCount >= alarm.snooze.maxCount
            if (atLimit) {
                Text(stringResource(R.string.no_more_snoozes), style = DawnType.footnote, color = DawnColors.OnYolkSecondary,
                    modifier = Modifier.padding(vertical = Spacing.sm))
            } else {
                val minutes = alarm.snooze.durationMinutes
                val remaining = alarm.snooze.maxCount - snoozeCount
                val label = when {
                    alarm.snooze.maxCount <= 0 -> stringResource(R.string.snooze_min, minutes)
                    remaining <= 1 -> stringResource(R.string.snooze_min_last, minutes)
                    else -> stringResource(R.string.snooze_min_left, minutes, remaining)
                }
                Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).clickable(onClick = onSnooze), contentAlignment = Alignment.Center) {
                    Text(label, style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = DawnColors.OnYolkSecondary)
                }
            }
        }
        Spacer(Modifier.height(Spacing.s))
    }
}

/** "Every weekday", "Today only": how the ring screen names when it repeats. */
private fun ringSummary(context: android.content.Context, r: AlarmRecurrence): String = when (r) {
    is AlarmRecurrence.OneTime -> context.getString(R.string.today_only)
    else -> TimeFormat.recurrence(context, r)
}

/**
 * The alarm's missions in order, with how many are done and five minutes on the
 * clock. When the time runs out the ring screen comes back; the alarm never stopped.
 */
@Composable
fun MissionHost(alarm: Alarm, onAllDone: () -> Unit, onTimeout: () -> Unit) {
    val context = LocalContext.current
    val (missions, notes) = remember { MissionCapability.runnable(context, alarm.missions) }
    var index by remember { mutableIntStateOf(0) }
    var secondsLeft by remember { mutableIntStateOf(300) }
    val advanced = remember { mutableSetOf<Int>() }
    LaunchedEffect(Unit) {
        while (secondsLeft > 0) { delay(1000); secondsLeft-- }
        onTimeout()
    }
    // A mission can report success twice (a sensor, a late callback): the second
    // must neither skip a mission nor finish the alarm twice.
    fun advance(at: Int) {
        if (at != index || !advanced.add(at)) return
        if (index + 1 < missions.size) index++ else onAllDone()
    }
    val colors = Dawn.colors
    Column(Modifier.fillMaxSize().background(colors.background).safeDrawingPadding()) {
        Column(Modifier.padding(horizontal = Spacing.l, vertical = Spacing.s)) {
            if (missions.size > 1) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    missions.indices.forEach { i ->
                        Box(Modifier.weight(1f).height(4.dp).clip(RoundedCornerShape(2.dp)).background(
                            when { i < index -> DawnColors.Ink; i == index -> DawnColors.Yolk; else -> colors.surfaceSecondary }))
                    }
                }
            }
            Text(
                "%d:%02d".format(Locale.ROOT, secondsLeft / 60, secondsLeft % 60),
                style = DawnType.footnote.copy(fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum"),
                color = when { secondsLeft <= 30 -> colors.destructive; secondsLeft <= 60 -> colors.warning; else -> colors.textSecondary },
                modifier = Modifier.align(Alignment.End).padding(top = 6.dp),
            )
        }
        if (notes.isNotEmpty()) {
            Row(Modifier.padding(horizontal = Spacing.s).fillMaxWidth().clip(RoundedCornerShape(Radius.s)).background(colors.surfaceSecondary).padding(Spacing.sm)) {
                Icon(Icons.Rounded.Info, null, tint = colors.warning, modifier = Modifier.size(14.dp))
                Spacer(Modifier.width(Spacing.xs))
                Text(notes.joinToString(" "), style = DawnType.footnote, color = colors.textSecondary)
            }
        }
        AnimatedContent(index, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "mission", modifier = Modifier.weight(1f)) { i ->
            val done = { advance(i) }
            MissionView(missions[i], done)
        }
    }
}

/**
 * A short "it's off": the cat, pleased, leaping twice; good morning; when you got
 * up and how long the mission took; and the streak, with today's paw print pressed
 * in. Hands back on its own after a moment.
 */
@Composable
fun MissionSuccess(elapsedSeconds: Int, streakDays: Int, onComplete: () -> Unit) {
    val haptics = rememberHaptics()
    val still = reduceMotion()
    var shown by remember { mutableStateOf(still) }
    var stamped by remember { mutableStateOf(still) }
    var leaps by remember { mutableIntStateOf(0) }
    val appear by animateFloatAsState(if (shown) 1f else 0f, spring(dampingRatio = 0.8f, stiffness = 300f), label = "shown")
    val stamp by animateFloatAsState(if (stamped) 1f else 0f, spring(dampingRatio = 0.55f, stiffness = 500f), label = "stamp")
    LaunchedEffect(Unit) {
        haptics.perform(Haptic.SUCCESS)
        shown = true
        delay(250)
        leaps++
        delay(200)
        stamped = true
        haptics.perform(Haptic.MEDIUM)
        delay(750)
        leaps++
        delay(2800 - 750)
        onComplete()
    }
    val time = LocalTime.now().format(DateTimeFormatter.ofPattern(if (TimeFormat.is24h(LocalContext.current)) "H:mm" else "h:mm a", Locale.getDefault()))
    val minutes = maxOf(1, (elapsedSeconds + 59) / 60)
    Column(
        Modifier.fillMaxSize().background(DawnColors.Yolk).safeDrawingPadding().padding(Spacing.m).alpha(appear),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CatMotion(CatMove.LEAP, leaps, 190.dp, shadow = true, modifier = Modifier.scale(0.92f + 0.08f * appear)) {
            CatMascot(CatMood.PROUD, Modifier.height(190.dp))
        }
        Spacer(Modifier.height(Spacing.s))
        Text(stringResource(R.string.good_morning), style = DawnType.display(34), color = DawnColors.Ink)
        Spacer(Modifier.height(Spacing.xs))
        Text(stringResource(R.string.success_summary, time, minutes), style = DawnType.callout, color = DawnColors.OnYolkSecondary)
        Spacer(Modifier.height(Spacing.s))
        Row(verticalAlignment = Alignment.CenterVertically) {
            PawPrint(DawnColors.Ink, Modifier.size(22.dp).scale(1.8f - 0.8f * stamp).alpha(stamp.coerceIn(0f, 1f)))
            Spacer(Modifier.width(Spacing.xs))
            Text(if (streakDays > 1) stringResource(R.string.cat_line_proud, streakDays) else stringResource(R.string.streak_starts_today),
                style = DawnType.headline, color = DawnColors.Ink)
        }
    }
}

/** "Still awake?" — asked in the app when the wake check's minutes are up. */
@Composable
fun WakeCheckPrompt(onAwake: () -> Unit, onFellAsleep: () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(Dawn.colors.background).safeDrawingPadding().padding(horizontal = Spacing.m),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        Box(contentAlignment = Alignment.Center) {
            Box(Modifier.size(108.dp).offset(y = 5.dp).clip(CircleShape).background(DawnColors.Yolk))
            CatMascot(CatMood.AWAKE, Modifier.height(78.dp))
        }
        Spacer(Modifier.height(Spacing.m))
        Text(stringResource(R.string.wake_check_title), style = DawnType.title, color = Dawn.colors.textPrimary)
        Spacer(Modifier.height(Spacing.xs))
        Text(stringResource(R.string.wake_check_body), style = DawnType.callout, color = Dawn.colors.textSecondary, textAlign = TextAlign.Center)
        Spacer(Modifier.weight(1f))
        YolkButton(onClick = onAwake) { ButtonLabel(stringResource(R.string.wake_check_awake)) }
        Box(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).clickable(onClick = onFellAsleep), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.wake_check_fell_asleep), style = DawnType.callout, color = Dawn.colors.textSecondary)
        }
        Spacer(Modifier.height(Spacing.s))
    }
}

/** A paw print, for the streak and the archive. */
@Composable
fun PawPrint(color: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier) =
    androidx.compose.foundation.Canvas(modifier) { drawPath(Shapes.pawPrint(androidx.compose.ui.geometry.Rect(androidx.compose.ui.geometry.Offset.Zero, size)), color) }
