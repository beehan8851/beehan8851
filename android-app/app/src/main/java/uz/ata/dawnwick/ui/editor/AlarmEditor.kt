package uz.ata.dawnwick.ui.editor

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material.icons.rounded.VolumeDown
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import uz.ata.dawnwick.ui.components.keepAboveKeyboard
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.AlarmService
import uz.ata.dawnwick.alarm.SaveError
import uz.ata.dawnwick.alarm.SaveResult
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmDate
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.AlarmSound
import uz.ata.dawnwick.alarm.model.AlarmTime
import uz.ata.dawnwick.alarm.model.GradualWake
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.SnoozeConfig
import uz.ata.dawnwick.alarm.model.WakeCheckConfig
import uz.ata.dawnwick.alarm.model.Weekday
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ring.TonePlayer
import uz.ata.dawnwick.ui.components.RowDivider
import uz.ata.dawnwick.ui.components.Section
import uz.ata.dawnwick.ui.components.SectionRow
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.missions.MissionArt
import uz.ata.dawnwick.ui.missions.missionIcon
import uz.ata.dawnwick.ui.missions.missionName
import uz.ata.dawnwick.ui.missions.missionSummary
import uz.ata.dawnwick.ui.permissions.AlarmPermission
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

private enum class ScheduleMode { ONE_TIME, DAILY, WEEKDAYS, WEEKENDS, CUSTOM }

/**
 * The time on a yolk band at the top — two drums of large numerals that stay in
 * view — and the rest under it: when it repeats, the missions as small tiles, the
 * label, the sound, snooze and the wake check. Delete and Duplicate live at the
 * bottom of an existing alarm; Cancel asks before throwing edits away.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlarmEditor(existing: Alarm?, onClose: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    val initial = remember {
        existing ?: Alarm(sound = graph.preferences.defaultSound)
    }
    var draft by remember { mutableStateOf(initial) }
    var customDays by remember { mutableStateOf((initial.recurrence as? AlarmRecurrence.Repeating)?.days ?: emptySet()) }
    var mode by remember {
        mutableStateOf(when (val r = initial.recurrence) {
            AlarmRecurrence.Daily -> ScheduleMode.DAILY
            is AlarmRecurrence.OneTime -> ScheduleMode.ONE_TIME
            is AlarmRecurrence.Repeating -> when (r.days) {
                Weekday.all -> ScheduleMode.DAILY
                Weekday.workdays -> ScheduleMode.WEEKDAYS
                Weekday.weekend -> ScheduleMode.WEEKENDS
                else -> ScheduleMode.CUSTOM
            }
        })
    }
    var oneTimeDate by remember {
        mutableStateOf((initial.recurrence as? AlarmRecurrence.OneTime)?.date?.toLocalDate() ?: LocalDate.now())
    }
    var showDiscard by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var errorNeedsSettings by remember { mutableStateOf(false) }
    var showDatePicker by remember { mutableStateOf(false) }
    var editingMission by remember { mutableStateOf<Int?>(null) }
    var pickingMission by remember { mutableStateOf(false) }

    fun recurrence(): AlarmRecurrence = when (mode) {
        ScheduleMode.ONE_TIME -> {
            // A one-time alarm whose time today has passed is for tomorrow.
            val today = LocalDate.now()
            val date = if (oneTimeDate == today && draft.wallClockTime.minutesOfDay <= java.time.LocalTime.now().let { it.hour * 60 + it.minute }) today.plusDays(1) else oneTimeDate
            AlarmRecurrence.OneTime(AlarmDate.of(date))
        }
        ScheduleMode.DAILY -> AlarmRecurrence.Daily
        ScheduleMode.WEEKDAYS -> AlarmRecurrence.Repeating(Weekday.workdays)
        ScheduleMode.WEEKENDS -> AlarmRecurrence.Repeating(Weekday.weekend)
        ScheduleMode.CUSTOM -> AlarmRecurrence.Repeating(customDays)
    }
    fun built() = draft.copy(label = draft.label.trim(), recurrence = recurrence())
    val hasChanges = built() != initial.copy(label = initial.label.trim())
    val canSave = draft.missions.isNotEmpty() && draft.missions.all { it.isConfigured } && !(mode == ScheduleMode.CUSTOM && customDays.isEmpty())

    fun applyDays(days: Set<Weekday>) {
        mode = when (days) {
            Weekday.all -> ScheduleMode.DAILY
            Weekday.workdays -> ScheduleMode.WEEKDAYS
            Weekday.weekend -> ScheduleMode.WEEKENDS
            else -> { customDays = days; ScheduleMode.CUSTOM }
        }
    }
    fun effectiveDays(): Set<Weekday> = when (mode) {
        ScheduleMode.ONE_TIME -> emptySet()
        ScheduleMode.DAILY -> Weekday.all
        ScheduleMode.WEEKDAYS -> Weekday.workdays
        ScheduleMode.WEEKENDS -> Weekday.weekend
        ScheduleMode.CUSTOM -> customDays
    }

    fun save() {
        when (val result = graph.alarmService.save(built())) {
            is SaveResult.Success -> onClose()
            is SaveResult.PartialSuccess -> {
                saveError = context.getString(R.string.alarm_saved_not_scheduled)
                errorNeedsSettings = true
            }
            is SaveResult.Failure -> {
                saveError = when (val e = result.error) {
                    is SaveError.Validation -> e.reason
                    is SaveError.Persistence -> e.error.localizedMessage ?: e.toString()
                    SaveError.FreeAlarmLimit -> context.getString(R.string.free_alarm_limit)
                        .also { graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.UNLIMITED_ALARMS) }
                    SaveError.PremiumMission -> context.getString(R.string.premium_mission_locked)
                        .also { graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.ADVANCED_MISSIONS) }
                }
                errorNeedsSettings = false
            }
        }
    }
    fun cancel() { if (hasChanges) showDiscard = true else onClose() }
    BackHandler { cancel() }

    val colors = Dawn.colors
    val preview = remember { TonePlayer(context, alarmStream = false) }
    var previewing by remember { mutableStateOf<AlarmSound?>(null) }
    DisposableEffect(Unit) { onDispose { preview.stop() } }
    LaunchedEffect(previewing) {
        if (previewing != null) { delay(3000); preview.stop(); previewing = null }
    }

    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(15_000); now = System.currentTimeMillis() } }
    val ringsIn = NextAlarmCalculator.nextFireTime(built().copy(isEnabled = true), Instant.ofEpochMilli(now))
        ?.let { TimeFormat.until(context, it.toEpochMilli() - now) } ?: "—"

    Column(Modifier.fillMaxSize().background(colors.background).safeDrawingPadding().imePadding()) {
        // Top bar: Cancel · title · Save
        Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.xs, vertical = Spacing.xxs), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = ::cancel) { Text(stringResource(R.string.cancel), color = colors.textSecondary, style = DawnType.body) }
            Text(stringResource(if (existing == null) R.string.new_alarm else R.string.edit_alarm), style = DawnType.headline, color = colors.textPrimary,
                textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
            TextButton(onClick = ::save, enabled = canSave) {
                Text(stringResource(R.string.save), style = DawnType.headline, color = if (canSave) colors.textPrimary else colors.textTertiary)
            }
        }
        // The time, always in view.
        Column(
            Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(Radius.xl)).background(colors.heroBand).padding(vertical = Spacing.sm),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val figure = if (colors.isDark) DawnColors.Yolk else DawnColors.Ink
            TimeDrum(draft.wallClockTime.hour, draft.wallClockTime.minute, figure) { h, m -> draft = draft.copy(wallClockTime = AlarmTime(h, m)) }
            Text(stringResource(R.string.rings_in, ringsIn), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = colors.onHeroSecondary)
        }

        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = Spacing.l)) {
            // Schedule
            Section(stringResource(R.string.schedule), footer = if (mode == ScheduleMode.CUSTOM && customDays.isNotEmpty())
                Weekday.displayOrder.filter { it in customDays }.joinToString(", ") { TimeFormat.weekdayShort(context, it) } else null) {
                Column(Modifier.padding(Spacing.sm), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    // All four the height of the tallest: a label too long for one line
                    // ("Dam olish kunlari", "По выходным") wraps instead of being cut.
                    Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf(
                            ScheduleMode.ONE_TIME to R.string.one_time, ScheduleMode.DAILY to R.string.recurrence_daily,
                            ScheduleMode.WEEKDAYS to R.string.recurrence_weekdays, ScheduleMode.WEEKENDS to R.string.recurrence_weekends,
                        ).forEach { (m, title) ->
                            val selected = mode == m
                            Box(
                                Modifier.weight(1f).fillMaxHeight().defaultMinSize(minHeight = 36.dp).clip(RoundedCornerShape(10.dp))
                                    .background(if (selected) colors.accent else colors.surfaceSecondary)
                                    .semantics { this.selected = selected }
                                    .clickable {
                                        when (m) {
                                            ScheduleMode.ONE_TIME -> mode = ScheduleMode.ONE_TIME
                                            ScheduleMode.DAILY -> applyDays(Weekday.all)
                                            ScheduleMode.WEEKDAYS -> applyDays(Weekday.workdays)
                                            ScheduleMode.WEEKENDS -> applyDays(Weekday.weekend)
                                            else -> Unit
                                        }
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(stringResource(title), style = DawnType.footnote.copy(fontWeight = FontWeight.Bold, lineHeight = 15.sp), maxLines = 2,
                                    textAlign = TextAlign.Center, color = if (selected) colors.background else colors.textSecondary,
                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp))
                            }
                        }
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        Weekday.displayOrder.forEach { day ->
                            val on = day in effectiveDays()
                            val name = TimeFormat.weekdayLong(context, day)
                            Box(
                                Modifier.size(38.dp).clip(CircleShape).background(if (on) colors.accent else colors.surfaceSecondary)
                                    .semantics { contentDescription = name; selected = on }
                                    .clickable {
                                        val days = effectiveDays().let { if (day in it) it - day else it + day }
                                        if (days.isEmpty()) mode = ScheduleMode.ONE_TIME else applyDays(days)
                                    },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(TimeFormat.weekdayLetter(context, day), style = DawnType.callout.copy(fontWeight = FontWeight.Black),
                                    color = if (on) colors.background else colors.textSecondary)
                            }
                        }
                    }
                }
                if (mode == ScheduleMode.ONE_TIME) {
                    RowDivider()
                    SectionRow(stringResource(R.string.date), onClick = { showDatePicker = true }) {
                        Text(oneTimeDate.format(DateTimeFormatter.ofPattern("EEE, d MMM", Locale.getDefault())), style = DawnType.body, color = colors.accent)
                    }
                }
            }

            // Missions
            Section(stringResource(R.string.wake_missions), footer = stringResource(R.string.missions_footer)) {
                Row(Modifier.horizontalScroll(rememberScrollState()).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    draft.missions.forEachIndexed { i, m -> MissionTile(i, m) { editingMission = i } }
                    if (draft.missions.size < 3) {
                        Column(
                            Modifier.width(132.dp).height(156.dp).clip(RoundedCornerShape(20.dp))
                                .dashedBorder(colors.textTertiary, 20.dp)
                                .pressable { pickingMission = true }.padding(12.dp),
                        ) {
                            Box(Modifier.size(40.dp).clip(CircleShape).background(colors.surfaceSecondary), contentAlignment = Alignment.Center) {
                                Icon(Icons.Rounded.Add, null, tint = colors.textPrimary)
                            }
                            Spacer(Modifier.weight(1f))
                            Text(stringResource(R.string.add_mission), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = colors.textPrimary)
                            Text(stringResource(R.string.n_of_3, draft.missions.size), style = DawnType.footnote, color = colors.textSecondary)
                        }
                    }
                }
            }

            // Label
            Section(stringResource(R.string.label)) {
                OutlinedTextField(
                    value = draft.label, onValueChange = { draft = draft.copy(label = it.take(60)) },
                    placeholder = { Text(stringResource(R.string.name_this_alarm)) }, singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = androidx.compose.ui.graphics.Color.Transparent,
                        focusedBorderColor = androidx.compose.ui.graphics.Color.Transparent),
                    modifier = Modifier.fillMaxWidth().keepAboveKeyboard(),
                )
            }

            // Sound
            Section(stringResource(R.string.sound)) {
                AlarmSound.entries.forEachIndexed { i, s ->
                    if (i > 0) RowDivider()
                    val isSelected = draft.sound == s
                    SectionRow(
                        soundName(s), subtitle = soundDetail(s),
                        onClick = {
                            draft = draft.copy(sound = s)
                            preview.play(s, draft.volume)
                            previewing = s
                        },
                    ) { if (isSelected) Icon(Icons.Rounded.Check, null, tint = colors.accent) }
                }
                RowDivider()
                Row(Modifier.padding(horizontal = Spacing.s, vertical = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.VolumeDown, null, tint = colors.textTertiary)
                    Slider(
                        value = draft.volume, onValueChange = { draft = draft.copy(volume = it) },
                        valueRange = AlarmService.MINIMUM_VOLUME..1f, modifier = Modifier.weight(1f).padding(horizontal = Spacing.xs),
                        colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent),
                    )
                    Icon(Icons.Rounded.VolumeUp, null, tint = colors.textTertiary)
                }
                RowDivider()
                MenuRow(stringResource(R.string.gradual_wake), GradualWake.entries, draft.gradualWake, { gradualName(it, context) }) { draft = draft.copy(gradualWake = it) }
            }

            // Snooze
            Section(stringResource(R.string.snooze)) {
                MenuRow(stringResource(R.string.duration), SnoozeConfig.durationOptions, draft.snooze.durationMinutes, { minutesName(context, it) }) {
                    draft = draft.copy(snooze = if (it == 0) SnoozeConfig.OFF else draft.snooze.copy(durationMinutes = it, maxCount = draft.snooze.maxCount.takeIf { c -> c != 0 } ?: 2))
                }
                if (draft.snooze.isEnabled) {
                    RowDivider()
                    MenuRow(stringResource(R.string.max_snoozes), SnoozeConfig.maxCountOptions, draft.snooze.maxCount,
                        { if (it == -1) context.getString(R.string.unlimited) else "$it" }) { draft = draft.copy(snooze = draft.snooze.copy(maxCount = it)) }
                }
            }

            // Wake check
            Section(stringResource(R.string.wake_check)) {
                MenuRow(stringResource(R.string.still_awake), WakeCheckConfig.durationOptions, draft.wakeCheck.durationMinutes, { minutesName(context, it) },
                    subtitle = stringResource(R.string.still_awake_detail)) { draft = draft.copy(wakeCheck = WakeCheckConfig(it)) }
            }

            if (existing != null) {
                Section(null) {
                    SectionRow(stringResource(R.string.duplicate_alarm), titleColor = colors.accent, onClick = {
                        graph.alarmService.save(built().copy(id = java.util.UUID.randomUUID().toString(), isEnabled = false))
                        onClose()
                    })
                    RowDivider()
                    SectionRow(stringResource(R.string.delete_alarm), titleColor = colors.destructive, onClick = { showDelete = true })
                }
            }
        }
    }

    if (pickingMission) {
        MissionPicker(draft.missions, onCancel = { pickingMission = false }, onDone = { picked ->
            pickingMission = false
            // Kept missions keep their settings; the new ones start from their defaults.
            val merged = picked.map { p -> draft.missions.firstOrNull { it.kind == p.kind } ?: p }
            val added = merged.filter { m -> draft.missions.none { it.kind == m.kind } }
            draft = draft.copy(missions = merged)
            // A new one that needs setting up (or a phrase, or a permission) opens straight away.
            added.firstOrNull { !it.isConfigured || it is MissionConfig.Typing || it is MissionConfig.Steps }
                ?.let { first -> editingMission = merged.indexOfFirst { it.kind == first.kind } }
        })
    }
    editingMission?.let { index ->
        val mission = draft.missions.getOrNull(index)
        if (mission != null) {
            MissionEditorSheet(
                mission = mission,
                canMoveEarlier = index > 0,
                canMoveLater = index < draft.missions.lastIndex,
                onChange = { updated -> draft = draft.copy(missions = draft.missions.toMutableList().also { it[index] = updated }) },
                onMove = { delta ->
                    val list = draft.missions.toMutableList()
                    val to = index + delta
                    list[index] = list[to].also { list[to] = list[index] }
                    draft = draft.copy(missions = list)
                    editingMission = to
                },
                onRemove = {
                    draft = draft.copy(missions = draft.missions.filterIndexed { i, _ -> i != index })
                    editingMission = null
                },
                onDismiss = { editingMission = null },
            )
        }
    }
    if (showDatePicker) {
        val zone = ZoneOffset.UTC
        val state = rememberDatePickerState(
            initialSelectedDateMillis = oneTimeDate.atStartOfDay(zone).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = !Instant.ofEpochMilli(utcTimeMillis).atZone(zone).toLocalDate().isBefore(LocalDate.now())
            },
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { oneTimeDate = Instant.ofEpochMilli(it).atZone(zone).toLocalDate() }
                    showDatePicker = false
                }) { Text(stringResource(R.string.ok)) }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text(stringResource(R.string.cancel)) } },
        ) { DatePicker(state) }
    }
    if (showDiscard) {
        AlertDialog(
            onDismissRequest = { showDiscard = false },
            title = { Text(stringResource(R.string.discard_changes_question)) },
            confirmButton = { TextButton(onClick = { showDiscard = false; onClose() }) { Text(stringResource(R.string.discard_changes), color = colors.destructive) } },
            dismissButton = { TextButton(onClick = { showDiscard = false }) { Text(stringResource(R.string.keep_editing)) } },
        )
    }
    if (showDelete && existing != null) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text(stringResource(R.string.delete_alarm_question)) },
            confirmButton = { TextButton(onClick = { graph.alarmService.delete(existing.id); showDelete = false; onClose() }) { Text(stringResource(R.string.delete_alarm), color = colors.destructive) } },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    saveError?.let { message ->
        AlertDialog(
            onDismissRequest = { saveError = null },
            title = { Text(stringResource(if (errorNeedsSettings) R.string.alarm_wont_ring else R.string.could_not_save)) },
            text = { Text(message) },
            confirmButton = {
                if (errorNeedsSettings) TextButton(onClick = {
                    saveError = null
                    AlarmPermission.missingCritical(context).firstOrNull()?.open(context)
                    onClose()
                }) { Text(stringResource(R.string.fix)) }
                else TextButton(onClick = { saveError = null }) { Text(stringResource(R.string.ok)) }
            },
            dismissButton = if (errorNeedsSettings) ({ TextButton(onClick = { saveError = null; onClose() }) { Text(stringResource(R.string.ok)) } }) else null,
        )
    }
}

@Composable
private fun MissionTile(index: Int, mission: MissionConfig, onClick: () -> Unit) {
    val context = LocalContext.current
    val colors = Dawn.colors
    Column(
        Modifier.width(132.dp).height(156.dp).clip(RoundedCornerShape(20.dp)).background(colors.tile).pressable(onClick = onClick).padding(12.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(DawnColors.Yolk), contentAlignment = Alignment.Center) {
                Text("${index + 1}", style = DawnType.footnote.copy(fontWeight = FontWeight.Black), color = DawnColors.Ink)
            }
            Spacer(Modifier.weight(1f))
            if (!mission.isConfigured) Icon(Icons.Rounded.ErrorOutline, stringResource(R.string.setup_needed), tint = DawnColors.Yolk, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.weight(1f))
        MissionArt(mission.kind, Modifier.offset(x = (-4).dp).size(72.dp, 48.dp))
        Spacer(Modifier.height(Spacing.xs))
        Text(missionName(mission.kind), style = DawnType.callout.copy(fontWeight = FontWeight.Bold), color = colors.onTile, maxLines = 1)
        Text(if (mission.isConfigured) missionSummary(context, mission) else stringResource(R.string.setup_needed),
            style = DawnType.footnote, color = if (mission.isConfigured) colors.onTile.copy(alpha = 0.6f) else DawnColors.Yolk, maxLines = 1)
    }
}

@Composable
private fun <T> MenuRow(title: String, options: List<T>, selected: T, name: (T) -> String, subtitle: String? = null, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        SectionRow(title, subtitle = subtitle, onClick = { open = true }) {
            Text(name(selected), style = DawnType.body, color = Dawn.colors.accent)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.align(Alignment.CenterEnd)) {
            options.forEach { option ->
                DropdownMenuItem(text = { Text(name(option)) }, onClick = { open = false; onSelect(option) },
                    trailingIcon = { if (option == selected) Icon(Icons.Rounded.Check, null) })
            }
        }
    }
}

@Composable
fun soundName(s: AlarmSound): String {
    val pet = uz.ata.dawnwick.ui.cat.currentCompanion()
    if (s == AlarmSound.MEOW && pet != uz.ata.dawnwick.companion.Pet.CAT) return androidx.compose.ui.res.stringResource(petVoiceName(pet))
    return LocalContext.current.resources.getStringArray(R.array.sound_names)[s.ordinal]
}

/** The name of the companion's call where the cat's is "Meow". */
fun petVoiceName(pet: uz.ata.dawnwick.companion.Pet) = when (pet) {
    uz.ata.dawnwick.companion.Pet.PUPPY -> R.string.voice_puppy
    uz.ata.dawnwick.companion.Pet.CHICK -> R.string.voice_chick
    uz.ata.dawnwick.companion.Pet.CANARY -> R.string.voice_canary
    uz.ata.dawnwick.companion.Pet.LAMB -> R.string.voice_lamb
    uz.ata.dawnwick.companion.Pet.OWL -> R.string.voice_owl
    uz.ata.dawnwick.companion.Pet.HAMSTER -> R.string.voice_hamster
    uz.ata.dawnwick.companion.Pet.CAT -> R.string.voice_cat
}

@Composable
private fun soundDetail(s: AlarmSound): String {
    if (s == AlarmSound.MEOW && uz.ata.dawnwick.ui.cat.currentCompanion() != uz.ata.dawnwick.companion.Pet.CAT) {
        return androidx.compose.ui.res.stringResource(R.string.voice_detail_companion)
    }
    return LocalContext.current.resources.getStringArray(R.array.sound_details)[s.ordinal]
}

private fun gradualName(g: GradualWake, context: android.content.Context) = context.resources.getStringArray(R.array.gradual_names)[g.ordinal]

private fun minutesName(context: android.content.Context, m: Int) = if (m == 0) context.getString(R.string.off) else context.getString(R.string.n_min, m)

/** A dashed outline, 5 on and 4 off: the empty place for one more mission. */
private fun Modifier.dashedBorder(color: androidx.compose.ui.graphics.Color, radius: androidx.compose.ui.unit.Dp) = drawBehind {
    val stroke = 1.5.dp.toPx()
    drawRoundRect(
        color, topLeft = androidx.compose.ui.geometry.Offset(stroke / 2, stroke / 2),
        size = androidx.compose.ui.geometry.Size(size.width - stroke, size.height - stroke),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(radius.toPx()),
        style = androidx.compose.ui.graphics.drawscope.Stroke(stroke, pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx()))),
    )
}
