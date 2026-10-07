package uz.ata.dawnwick.ui.alarms

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.components.AlarmTimeText
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.format.TimeFormat
import uz.ata.dawnwick.ui.missions.missionIcon
import uz.ata.dawnwick.ui.missions.missionName
import uz.ata.dawnwick.ui.permissions.PermissionBanner
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/** Enabled first, then by when they ring; switched-off ones by time of day. */
fun sortAlarms(alarms: List<Alarm>): List<Alarm> {
    val now = java.time.Instant.now()
    return alarms.sortedWith(compareBy<Alarm>({ !it.isEnabled }, { NextAlarmCalculator.nextFireTime(it, now)?.toEpochMilli() ?: Long.MAX_VALUE }, { it.wallClockTime.minutesOfDay }))
}

@Composable
fun AlarmsScreen(alarms: List<Alarm>, onOpen: (Alarm?) -> Unit, onChanged: () -> Unit) {
    val context = LocalContext.current
    val graph = context.graph
    var pendingDelete by remember { mutableStateOf<Alarm?>(null) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { delay(30_000); now = System.currentTimeMillis() } }

    Column(Modifier.fillMaxSize().background(Dawn.colors.background)) {
        Row(Modifier.fillMaxWidth().padding(start = Spacing.s, end = Spacing.xs, top = Spacing.s), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.tab_alarms), style = DawnType.display(34), color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
            IconButton(onClick = { onOpen(null) }, modifier = Modifier.semantics { contentDescription = context.getString(R.string.new_alarm) }) {
                Icon(Icons.Rounded.Add, contentDescription = null, tint = Dawn.colors.accent, modifier = Modifier.size(30.dp))
            }
        }
        PermissionBanner()
        if (alarms.isEmpty()) {
            EmptyAlarms(onCreate = { onOpen(null) })
            return@Column
        }
        val sorted = sortAlarms(alarms)
        LazyColumn(contentPadding = PaddingValues(horizontal = Spacing.s, vertical = Spacing.xs), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            val next = alarms.mapNotNull { NextAlarmCalculator.nextFireTime(it)?.toEpochMilli() }.minOrNull()
            if (next != null) item {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(start = Spacing.xs, bottom = Spacing.xxs)) {
                    Icon(Icons.Rounded.Bedtime, null, tint = Dawn.colors.accent, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(stringResource(R.string.next_alarm_in, TimeFormat.until(context, next - now)),
                        style = DawnType.callout.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = Dawn.colors.textSecondary)
                }
            }
            items(sorted, key = { it.id }) { alarm ->
                // Swiped from the end, it asks to be deleted, as on iOS.
                val swipe = rememberSwipeToDismissBoxState()
                LaunchedEffect(swipe.currentValue) {
                    if (swipe.currentValue == SwipeToDismissBoxValue.EndToStart) {
                        pendingDelete = alarm
                        swipe.reset()
                    }
                }
                SwipeToDismissBox(
                    swipe,
                    enableDismissFromStartToEnd = false,
                    modifier = Modifier.animateItem(),
                    backgroundContent = {
                        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.destructive).padding(end = Spacing.m), contentAlignment = Alignment.CenterEnd) {
                            Icon(Icons.Rounded.Delete, stringResource(R.string.delete), tint = Color.White)
                        }
                    },
                ) {
                AlarmRow(
                    alarm = alarm,
                    onOpen = { onOpen(alarm) },
                    onToggle = {
                        graph.alarmService.save(alarm.copy(isEnabled = !alarm.isEnabled)).also { result ->
                            when (result) {
                                is uz.ata.dawnwick.alarm.SaveResult.PartialSuccess ->
                                    Toast.makeText(context, R.string.alarm_saved_not_scheduled, Toast.LENGTH_LONG).show()
                                // Until the paywall exists, say why the switch did not move.
                                is uz.ata.dawnwick.alarm.SaveResult.Failure -> Toast.makeText(context,
                                    when (val e = result.error) {
                                        uz.ata.dawnwick.alarm.SaveError.FreeAlarmLimit -> context.getString(R.string.free_alarm_limit)
                                        is uz.ata.dawnwick.alarm.SaveError.Validation -> e.reason
                                        else -> context.getString(R.string.alarm_saved_not_scheduled)
                                    }, Toast.LENGTH_LONG).show()
                                else -> Unit
                            }
                        }
                        onChanged()
                    },
                    onDuplicate = { graph.alarmService.save(alarm.copy(id = java.util.UUID.randomUUID().toString(), isEnabled = false)); onChanged() },
                    onDelete = { pendingDelete = alarm },
                )
                }
            }
            item { TestAlarmRow() }
        }
    }

    pendingDelete?.let { alarm ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.delete_alarm_question)) },
            text = {
                Text(if (alarm.label.isBlank()) stringResource(R.string.delete_alarm_message, TimeFormat.time(context, alarm.wallClockTime))
                else stringResource(R.string.delete_alarm_message_label, alarm.label, TimeFormat.time(context, alarm.wallClockTime)))
            },
            confirmButton = {
                TextButton(onClick = { graph.alarmService.delete(alarm.id); pendingDelete = null; onChanged() }) {
                    Text(stringResource(R.string.delete_alarm), color = Dawn.colors.destructive)
                }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Nothing set: the cat, awake and waiting, and the one thing to do. */
@Composable
private fun EmptyAlarms(onCreate: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = Spacing.l, vertical = Spacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.s),
    ) {
        CatMascot(CatMood.AWAKE, Modifier.width(150.dp), ground = if (Dawn.colors.isDark) CatGround.DARK else CatGround.LIGHT)
        Text(stringResource(R.string.no_alarms_yet), style = DawnType.title, color = Dawn.colors.textPrimary)
        Text(stringResource(R.string.no_alarms_detail), style = DawnType.body, color = Dawn.colors.textSecondary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(Spacing.xs))
        YolkButton(onClick = onCreate, modifier = Modifier.widthIn(max = 420.dp)) { ButtonLabel(stringResource(R.string.add_first_alarm)) }
    }
}

/** One alarm: the time set large, what it is and when it repeats, the missions. Off, it dims. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
private fun AlarmRow(alarm: Alarm, onOpen: () -> Unit, onToggle: () -> Unit, onDuplicate: () -> Unit, onDelete: () -> Unit) {
    val context = LocalContext.current
    val colors = Dawn.colors
    val ink = if (alarm.isEnabled) colors.textSecondary else colors.textTertiary
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(colors.surfacePrimary)
            .clickable(onClick = onOpen).padding(start = Spacing.s, end = Spacing.xs, top = Spacing.sm, bottom = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            AlarmTimeText(alarm.wallClockTime, 44, if (alarm.isEnabled) colors.textPrimary else colors.textTertiary, weight = androidx.compose.ui.text.font.FontWeight.SemiBold)
            val recurrence = TimeFormat.recurrence(context, alarm.recurrence)
            Text(if (alarm.label.isBlank()) recurrence else "${alarm.label} · $recurrence", style = DawnType.callout, color = ink)
            Spacer(Modifier.height(4.dp))
            // Wraps to a second line rather than cutting a mission off.
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                alarm.missions.forEach { m ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(missionIcon(m.kind), null, tint = if (alarm.isEnabled) colors.accent else colors.textTertiary, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(4.dp))
                        Text(missionName(m.kind), style = DawnType.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = ink, maxLines = 1)
                    }
                }
            }
        }
        Switch(
            checked = alarm.isEnabled, onCheckedChange = { onToggle() },
            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.background),
        )
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreVert, stringResource(R.string.more), tint = colors.textTertiary) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.edit)) }, onClick = { menu = false; onOpen() })
                DropdownMenuItem(text = { Text(stringResource(R.string.duplicate)) }, onClick = { menu = false; onDuplicate() })
                DropdownMenuItem(text = { Text(stringResource(R.string.delete), color = colors.destructive) }, onClick = { menu = false; onDelete() })
            }
        }
    }
}

/** An alarm app is trusted once it has been heard. */
@Composable
private fun TestAlarmRow() {
    val context = LocalContext.current
    var message by remember { mutableStateOf<String?>(null) }
    Row(
        Modifier.fillMaxWidth().padding(top = Spacing.s).clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary).padding(Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(Dawn.colors.surfaceSecondary), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.VolumeUp, null, tint = Dawn.colors.accent)
        }
        Spacer(Modifier.width(Spacing.s))
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.test_alarm_title), style = DawnType.headline, color = Dawn.colors.textPrimary)
            Text(stringResource(R.string.test_alarm_detail), style = DawnType.footnote, color = Dawn.colors.textSecondary)
        }
        Spacer(Modifier.width(Spacing.xs))
        Box(
            Modifier.clip(RoundedCornerShape(50)).background(DawnColors.Yolk)
                .pressable { message = context.getString(if (context.graph.ring.scheduleTestAlarm()) R.string.test_alarm_scheduled else R.string.test_alarm_failed) }
                .padding(horizontal = Spacing.s, vertical = Spacing.xs),
        ) { Text(stringResource(R.string.test), style = DawnType.headline, color = DawnColors.Ink) }
    }
    message?.let {
        AlertDialog(
            onDismissRequest = { message = null },
            title = { Text(stringResource(R.string.test_alarm)) },
            text = { Text(it) },
            confirmButton = { TextButton(onClick = { message = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}
