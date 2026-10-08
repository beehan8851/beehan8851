package uz.ata.dawnwick.ui.sleep

import android.Manifest
import android.app.Activity
import android.app.TimePickerDialog
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.VolumeOff
import androidx.compose.material.icons.rounded.Waves
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.sleep.HealthSleep
import uz.ata.dawnwick.sleep.SleepEntry
import uz.ata.dawnwick.sleep.SleepHistory
import uz.ata.dawnwick.sleep.SleepSession
import uz.ata.dawnwick.sleep.SleepSound
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.missions.Camera
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/** "7h 40m". */
@Composable
fun sleepDuration(millis: Long): String {
    val minutes = (millis / 60_000).coerceAtLeast(0).toInt()
    return stringResource(R.string.duration_hm, minutes / 60, minutes % 60)
}

fun sleepDuration(context: android.content.Context, millis: Long): String {
    val minutes = (millis / 60_000).coerceAtLeast(0).toInt()
    return context.getString(R.string.duration_hm, minutes / 60, minutes % 60)
}

fun soundName(sound: SleepSound) = when (sound) {
    SleepSound.NONE -> R.string.sound_none
    SleepSound.WHITE_NOISE -> R.string.sound_white
    SleepSound.BROWN_NOISE -> R.string.sound_brown
}

fun soundIcon(sound: SleepSound): ImageVector = when (sound) {
    SleepSound.NONE -> Icons.Rounded.VolumeOff
    SleepSound.WHITE_NOISE -> Icons.Rounded.GraphicEq
    SleepSound.BROWN_NOISE -> Icons.Rounded.Waves
}

/**
 * Sleep: tonight on an ink band with the cat asleep, the start button and the
 * wind-down; then tonight's settings and last night — last night first in the
 * morning, tonight first in the evening. While a night is being tracked, the whole
 * tab is that night.
 */
@Composable
fun SleepScreen(alarms: List<Alarm>, windDownRequested: Boolean, onWindDownHandled: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val tracker = graph.sleep
    val scope = rememberCoroutineScope()
    val active by tracker.active.collectAsState()
    var sessions by remember { mutableStateOf(tracker.repository.loadCompleted()) }
    var health by remember { mutableStateOf<List<SleepEntry>>(emptyList()) }
    var healthState by remember { mutableStateOf<HealthSleep.State?>(null) }
    var result by remember { mutableStateOf<SleepSession?>(null) }
    var showHistory by remember { mutableStateOf(false) }
    var windDown by remember { mutableStateOf(false) }

    fun reload() {
        sessions = tracker.repository.loadCompleted()
        scope.launch {
            healthState = graph.health.state()
            health = graph.health.history()
        }
    }
    LifecycleResumeEffect(Unit) { reload(); onPauseOrDispose { } }
    LaunchedEffect(windDownRequested) {
        if (windDownRequested) {
            if (active == null) windDown = true
            onWindDownHandled()
        }
    }
    val healthLauncher = rememberLauncherForActivityResult(graph.health.requestContract()) { reload() }

    val next = alarms.mapNotNull { a -> NextAlarmCalculator.nextFireTime(a)?.let { a to it.toEpochMilli() } }.minByOrNull { it.second }
    val session = active
    if (session != null) {
        SleepActive(session, next) { done ->
            result = done
            reload()
        }
    } else {
        val evening = LocalTime.now().hour.let { it >= 17 || it < 5 }
        Column(Modifier.fillMaxSize().background(Dawn.colors.background).verticalScroll(rememberScrollState()).padding(bottom = Spacing.l)) {
            Row(Modifier.fillMaxWidth().padding(start = Spacing.s, end = Spacing.xs, top = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.tab_sleep), style = DawnType.display(34), color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
                TextButton(onClick = {
                    // Last night is free; the full history and trend are Premium.
                    if (graph.isPremium) showHistory = true
                    else graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.SLEEP_HISTORY)
                }) { Text(stringResource(R.string.sleep_history_button), color = Dawn.colors.accent, fontWeight = FontWeight.Bold) }
            }
            Column(Modifier.padding(horizontal = Spacing.s).padding(top = Spacing.xs), verticalArrangement = Arrangement.spacedBy(Spacing.l)) {
                Hero(next?.second, evening, onStart = { startTracking(context) }, onWindDown = { windDown = true })
                val tonight: @Composable () -> Unit = { TonightSection() }
                val lastNight: @Composable () -> Unit = {
                    LastNightSection(sessions, health, healthState) { healthLauncher.launch(setOf(graph.health.permission)) }
                }
                if (evening) { tonight(); lastNight() } else { lastNight(); tonight() }
            }
        }
    }

    result?.let { SleepResult(it) { result = null } }
    if (showHistory) SleepReport(sessions, health) { showHistory = false }
    if (windDown) WindDown(next?.second, onStartTracking = { startTracking(context) }) { windDown = false }
}

/** The microphone is asked for when tracking starts with listening on and it was never asked. */
private fun startTracking(context: android.content.Context) = context.graph.sleep.start()

@Composable
private fun Hero(nextAlarm: Long?, evening: Boolean, onStart: () -> Unit, onWindDown: () -> Unit) {
    val context = LocalContext.current
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }
    val summary = when {
        nextAlarm == null -> stringResource(R.string.no_alarm_set)
        evening && (nextAlarm - now) in 3600_000L..14 * 3600_000L ->
            stringResource(R.string.sleep_alarm_at_for, TimeFormat.clock(context, nextAlarm), sleepDuration(nextAlarm - now))
        else -> stringResource(R.string.sleep_alarm_at, TimeFormat.clock(context, nextAlarm))
    }
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.xl)).background(DawnColors.Ink).padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.sleep_tonight), style = DawnType.headline, color = DawnColors.NightTextSecondary)
                Text(summary, style = DawnType.headline.copy(fontWeight = FontWeight.SemiBold), color = DawnColors.Paper)
            }
            CatMascot(CatMood.SLEEPING, Modifier.width(128.dp).offset(x = 8.dp), ground = CatGround.DARK)
        }
        YolkButton(onClick = onStart) { ButtonLabel(stringResource(R.string.sleep_start)) }
        Row(
            Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).clip(RoundedCornerShape(Radius.l))
                .background(DawnColors.Paper.copy(alpha = 0.08f)).pressable(onClick = onWindDown),
            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.Air, null, tint = DawnColors.Paper, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(Spacing.xs))
            Text(stringResource(R.string.sleep_wind_down_first), style = DawnType.button, color = DawnColors.Paper)
        }
    }
}

@Composable
private fun SectionTitle(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(title.uppercase(), style = DawnType.section, color = Dawn.colors.textSecondary, modifier = Modifier.padding(start = 4.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary)) { content() }
    }
}

@Composable
private fun Divider() = Box(Modifier.padding(start = Spacing.s).fillMaxWidth().height(0.5.dp).background(Dawn.colors.separator))

@Composable
private fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    // The whole row is the switch, as on iOS: the label can be tapped too.
    Row(
        Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp)
            .toggleable(value = checked, role = androidx.compose.ui.semantics.Role.Switch, onValueChange = onChange)
            .padding(horizontal = Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = DawnType.body, color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
        Switch(checked, null, colors = SwitchDefaults.colors(checkedTrackColor = Dawn.colors.accent, checkedThumbColor = Dawn.colors.background))
    }
}

/** The sound, listening, and the reminder to start winding down. */
@Composable
private fun TonightSection() {
    val context = LocalContext.current
    val activity = context as? Activity
    val graph = context.graph
    val tracker = graph.sleep
    val colors = Dawn.colors
    var sound by remember { mutableStateOf(tracker.selectedSound) }
    var soundMenu by remember { mutableStateOf(false) }
    var listening by remember { mutableStateOf(tracker.noiseMonitoring && tracker.noise.allowed) }
    var micAsked by remember { mutableStateOf(graph.store.getBoolean(MIC_ASKED)) }
    var reminder by remember { mutableStateOf(graph.bedtime.load()) }
    var reminderNeedsPermission by remember { mutableStateOf(false) }

    val micLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        graph.store.putBoolean(MIC_ASKED, true); micAsked = true
        // Being asked for the microphone is consent to use it, so the setting follows.
        if (granted) tracker.microphoneGranted()
        listening = granted
    }
    val notifyLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        reminder = graph.bedtime.apply(reminder.copy(isEnabled = granted))
        reminderNeedsPermission = !granted
    }
    val micRefused = micAsked && !tracker.noise.allowed && activity != null &&
        !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.RECORD_AUDIO)

    SectionTitle(stringResource(R.string.sleep_tonight)) {
        Box {
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).pressable { soundMenu = true }.padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.sleep_sound), style = DawnType.body, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Icon(soundIcon(sound), null, tint = colors.accent, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(stringResource(soundName(sound)), style = DawnType.body, color = colors.accent)
            }
            DropdownMenu(soundMenu, { soundMenu = false }) {
                SleepSound.entries.forEach { s ->
                    DropdownMenuItem(text = { Text(stringResource(soundName(s))) }, leadingIcon = { Icon(soundIcon(s), null) },
                        onClick = { sound = s; tracker.selectedSound = s; soundMenu = false })
                }
            }
        }
        Divider()
        if (micRefused) {
            Row(Modifier.fillMaxWidth().padding(start = Spacing.s, end = 4.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.sleep_monitor_noise), style = DawnType.body, color = colors.textPrimary)
                    Text(stringResource(R.string.sleep_mic_denied), style = DawnType.footnote, color = colors.textSecondary)
                }
                TextButton(onClick = { Camera.openAppSettings(context) }) { Text(stringResource(R.string.tab_settings), color = colors.accent) }
            }
        } else {
            SwitchRow(stringResource(R.string.sleep_monitor_noise), listening) { on ->
                if (on && !tracker.noise.allowed) micLauncher.launch(Manifest.permission.RECORD_AUDIO)
                else { tracker.noiseMonitoring = on; listening = on }
            }
        }
        Divider()
        SwitchRow(stringResource(R.string.bedtime_reminder), reminder.isEnabled) { on ->
            reminderNeedsPermission = false
            if (on && !graph.bedtime.canNotify() && Build.VERSION.SDK_INT >= 33) {
                notifyLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                reminder = graph.bedtime.apply(reminder.copy(isEnabled = on))
                reminderNeedsPermission = on && !reminder.isEnabled
            }
        }
        if (reminder.isEnabled) {
            Divider()
            Row(
                Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).pressable {
                    TimePickerDialog(context, { _, h, m -> reminder = graph.bedtime.apply(reminder.copy(hour = h, minute = m)) },
                        reminder.hour, reminder.minute, TimeFormat.is24h(context)).show()
                }.padding(horizontal = Spacing.s),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.bedtime_remind_at), style = DawnType.body, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Text(TimeFormat.time(context, uz.ata.dawnwick.alarm.model.AlarmTime(reminder.hour, reminder.minute)), style = DawnType.body, color = colors.accent)
            }
        }
        if (reminderNeedsPermission) {
            Divider()
            Row(Modifier.fillMaxWidth().padding(start = Spacing.s, end = 4.dp, top = 8.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.bedtime_needs_permission), style = DawnType.footnote, color = colors.textSecondary, modifier = Modifier.weight(1f))
                TextButton(onClick = { Camera.openAppSettings(context) }) { Text(stringResource(R.string.tab_settings), color = colors.accent) }
            }
        }
    }
}

private const val MIC_ASKED = "sleep.mic.asked"

/** Last night's figure, then earlier nights; Health Connect is offered, never asked unprompted. */
@Composable
private fun LastNightSection(sessions: List<SleepSession>, health: List<SleepEntry>, state: HealthSleep.State?, onConnect: () -> Unit) {
    val colors = Dawn.colors
    val zone = ZoneId.systemDefault()
    val today = LocalDate.now(zone)
    val sinceYesterday = today.minusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
    val lastNightLocal = sessions.filter { it.startMillis >= sinceYesterday }.mapNotNull { it.durationMillis }.maxOrNull()
    val lastNightHealth = health.firstOrNull { it.date == today }?.durationMillis
    val lastNight = listOfNotNull(lastNightLocal, lastNightHealth).maxOrNull()
    val earlier = SleepHistory.merge(sessions, health).filter { it.date != today && it.durationMillis != null }
    SectionTitle(stringResource(R.string.sleep_last_night)) {
        Column(Modifier.padding(horizontal = Spacing.s, vertical = Spacing.sm)) {
            when {
                lastNight != null -> Text(sleepDuration(lastNight), style = DawnType.display(40), color = colors.textPrimary)
                state == HealthSleep.State.NOT_CONNECTED && earlier.isEmpty() -> {
                    Text(stringResource(R.string.health_connect_title), style = DawnType.body, color = colors.textPrimary)
                    Text(stringResource(R.string.health_connect_detail), style = DawnType.footnote, color = colors.textSecondary)
                }
                earlier.isEmpty() -> {
                    Text(stringResource(R.string.sleep_no_data), style = DawnType.body, color = colors.textPrimary)
                    Text(stringResource(R.string.sleep_no_data_hint), style = DawnType.footnote, color = colors.textSecondary)
                }
                else -> Text(stringResource(R.string.sleep_none_recorded), style = DawnType.body, color = colors.textSecondary)
            }
        }
        if (state == HealthSleep.State.NOT_CONNECTED) {
            Divider()
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).pressable(onClick = onConnect).padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.health_connect_button), style = DawnType.body, color = colors.accent, modifier = Modifier.weight(1f))
            }
        }
        val context = androidx.compose.ui.platform.LocalContext.current
        if (earlier.isNotEmpty() && !context.graph.isPremium) {
            Divider()
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp)
                .pressable { context.graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.SLEEP_HISTORY) }
                .padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Text(androidx.compose.ui.res.pluralStringResource(R.plurals.sleep_earlier_nights_locked, earlier.size, earlier.size),
                    style = DawnType.body, color = colors.accent, modifier = Modifier.weight(1f))
            }
        }
        if (context.graph.isPremium) earlier.forEach { day ->
            Divider()
            Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp).padding(horizontal = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
                Text(day.date.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL_STANDALONE, java.util.Locale.getDefault()).replaceFirstChar { it.uppercase() },
                    style = DawnType.body, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Text(sleepDuration(day.durationMillis!!), style = DawnType.body, color = colors.textSecondary)
            }
        }
    }
}

/** The tracked night, on screen until it is stopped: the cat asleep, the alarm, the time asleep. */
@Composable
private fun SleepActive(session: SleepSession, next: Pair<Alarm, Long>?, onStopped: (SleepSession) -> Unit) {
    val context = LocalContext.current
    val tracker = context.graph.sleep
    val colors = Dawn.colors
    val level by tracker.noise.level.collectAsState()
    val events by tracker.noise.events.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var confirm by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { while (true) { delay(1000); now = System.currentTimeMillis() } }
    Column(Modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(if (tracker.isRestored) R.string.sleep_restored else R.string.sleep_tracking_label), style = DawnType.callout, color = colors.textSecondary,
            modifier = Modifier.padding(top = Spacing.l))
        Spacer(Modifier.height(Spacing.l))
        Column(
            Modifier.padding(horizontal = Spacing.s).fillMaxWidth().clip(RoundedCornerShape(Radius.xl)).background(DawnColors.Ink).padding(vertical = Spacing.m, horizontal = Spacing.s),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.s),
        ) {
            CatMascot(CatMood.SLEEPING, Modifier.width(210.dp), ground = CatGround.DARK)
            Text(stringResource(if (next == null) R.string.sleep_went_to_bed else R.string.sleep_alarm), style = DawnType.headline, color = DawnColors.NightTextSecondary)
            Text(TimeFormat.clock(context, next?.second ?: session.startMillis), style = DawnType.display(60), color = DawnColors.Paper)
            val elapsed = (now - session.startMillis) / 1000
            Row {
                Text(stringResource(R.string.sleep_asleep_for) + " ", style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = DawnColors.NightTextSecondary)
                Text("%d:%02d:%02d".format(elapsed / 3600, elapsed / 60 % 60, elapsed % 60), style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"), color = DawnColors.Yolk)
            }
        }
        Spacer(Modifier.weight(1f).height(Spacing.l))
        Column(Modifier.padding(horizontal = Spacing.s).fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary)) {
            next?.let { (alarm, at) ->
                Detail(Icons.Rounded.Alarm) {
                    val time = TimeFormat.clock(context, at)
                    Text(if (alarm.label.isBlank()) stringResource(R.string.sleep_alarm_at_short, time) else "$time — ${alarm.label}", style = DawnType.callout, color = colors.textPrimary)
                }
                Divider()
            }
            if (tracker.noise.isMonitoring) {
                Detail(Icons.Rounded.GraphicEq) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row {
                            Text(stringResource(R.string.sleep_ambient_noise), style = DawnType.callout, color = colors.textPrimary, modifier = Modifier.weight(1f))
                            Text(if (events.isEmpty()) stringResource(R.string.sleep_quiet) else androidx.compose.ui.res.pluralStringResource(R.plurals.noise_events, events.size, events.size),
                                style = DawnType.callout, color = colors.textSecondary)
                        }
                        NoiseBar(level)
                    }
                }
                Divider()
            }
            Detail(soundIcon(tracker.selectedSound)) {
                Text(if (tracker.audio.isPlaying) stringResource(soundName(tracker.selectedSound)) else stringResource(R.string.sleep_no_sound), style = DawnType.callout, color = colors.textPrimary)
            }
        }
        Spacer(Modifier.height(Spacing.s))
        Box(
            Modifier.padding(horizontal = Spacing.s).fillMaxWidth().defaultMinSize(minHeight = 56.dp).clip(RoundedCornerShape(Radius.l))
                .background(colors.destructive.copy(alpha = 0.12f)).pressable { confirm = true },
            contentAlignment = Alignment.Center,
        ) { Text(stringResource(R.string.sleep_stop), style = DawnType.button, color = colors.destructive) }
        Spacer(Modifier.height(Spacing.m))
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text(stringResource(R.string.sleep_stop_question)) },
            text = { Text(stringResource(R.string.sleep_stop_message)) },
            confirmButton = { TextButton(onClick = { confirm = false; tracker.stop()?.let(onStopped) }) { Text(stringResource(R.string.sleep_stop), color = colors.destructive) } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.sleep_keep)) } },
        )
    }
}

@Composable
private fun Detail(icon: ImageVector, content: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().defaultMinSize(minHeight = 52.dp).padding(horizontal = Spacing.s, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = Dawn.colors.accent, modifier = Modifier.width(20.dp))
        Spacer(Modifier.width(Spacing.sm))
        Box(Modifier.weight(1f)) { content() }
    }
}

/** How loud the room is: green, then amber, then red. */
@Composable
private fun NoiseBar(levelDb: Float) {
    val fraction = ((levelDb.coerceIn(-80f, -10f) + 80f) / 70f)
    val color = when { fraction < 0.4f -> Dawn.colors.success; fraction < 0.7f -> Dawn.colors.warning; else -> Dawn.colors.destructive }
    Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(Dawn.colors.surfaceSecondary)) {
        Box(Modifier.fillMaxWidth(fraction).height(4.dp).background(color))
    }
}

