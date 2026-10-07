package uz.ata.dawnwick.ui.editor

import uz.ata.dawnwick.graph
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.rounded.Close
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.ui.missions.ArtTone
import uz.ata.dawnwick.ui.missions.MissionArt
import uz.ata.dawnwick.ui.missions.MissionView
import uz.ata.dawnwick.ui.missions.missionNameRes
import uz.ata.dawnwick.ui.theme.DawnTheme
import uz.ata.dawnwick.ui.theme.DaylightTheme
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.imePadding
import uz.ata.dawnwick.ui.components.keepAboveKeyboard
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.MathDifficulty
import uz.ata.dawnwick.alarm.model.MemoryDifficulty
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.components.SoftButton
import uz.ata.dawnwick.ui.missions.Camera
import uz.ata.dawnwick.ui.missions.DrawSetupDialog
import uz.ata.dawnwick.ui.missions.MissionCapability
import uz.ata.dawnwick.ui.missions.Motion
import uz.ata.dawnwick.ui.missions.QrSetupDialog
import uz.ata.dawnwick.ui.missions.missionDetailRes
import uz.ata.dawnwick.ui.missions.missionIcon
import uz.ata.dawnwick.ui.missions.missionName
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * The missions as tiles, two to a row, each with a small moving picture of what you
 * will do. Tap a tile to add it to the wake sequence (or take it out), hold one to
 * try it, up to three in the order they were tapped. A chosen tile turns yolk and
 * shows its place; the sequence reads out above Done.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MissionPicker(current: List<MissionConfig>, onDone: (List<MissionConfig>) -> Unit, onCancel: () -> Unit) {
    val context = LocalContext.current
    val haptics = rememberHaptics()
    var missions by remember { mutableStateOf(current) }
    var preview by remember { mutableStateOf<MissionKind?>(null) }
    val limit = 3
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DawnTheme {
            val colors = Dawn.colors
            Column(Modifier.fillMaxSize().background(colors.background).safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.textSecondary) }
                    Text(stringResource(R.string.missions_title), style = DawnType.headline, color = colors.textPrimary,
                        textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                    Spacer(Modifier.size(72.dp, 1.dp))
                }
                LazyVerticalGrid(
                    GridCells.Fixed(2),
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = Spacing.s, vertical = Spacing.xs),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item(span = { GridItemSpan(2) }) {
                        Text(stringResource(R.string.picker_hint, limit), style = DawnType.callout, color = colors.textSecondary)
                    }
                    items(MissionKind.entries) { kind ->
                        val position = missions.indexOfFirst { it.kind == kind }.takeIf { it >= 0 }
                        val unavailable = MissionCapability.reasonUnavailable(context, kind)
                        val full = position == null && missions.size >= limit
                        val chosen = position != null
                        val ink = if (chosen) DawnColors.Ink else colors.onTile
                        Column(
                            Modifier.fillMaxWidth().heightIn(min = 150.dp).clip(RoundedCornerShape(22.dp))
                                .background(if (chosen) DawnColors.Yolk else colors.tile)
                                .alpha(if (full || unavailable != null) 0.45f else 1f)
                                .combinedClickable(
                                    onClick = {
                                        when {
                                            position != null -> { haptics.perform(Haptic.SELECTION); missions = missions.filterIndexed { i, _ -> i != position } }
                                            unavailable != null -> { haptics.perform(Haptic.WARNING); android.widget.Toast.makeText(context, unavailable, android.widget.Toast.LENGTH_LONG).show() }
                                            full -> haptics.perform(Haptic.WARNING)
                                            kind.isPremium && !context.graph.isPremium -> {
                                                haptics.perform(Haptic.WARNING)
                                                context.graph.showPaywall(uz.ata.dawnwick.premium.PremiumFeature.ADVANCED_MISSIONS)
                                            }
                                            else -> { haptics.perform(Haptic.SELECTION); missions = missions + kind.defaultConfig }
                                        }
                                    },
                                    onLongClick = { if (unavailable == null) { haptics.perform(Haptic.MEDIUM); preview = kind } },
                                )
                                .padding(14.dp),
                        ) {
                            Row(verticalAlignment = Alignment.Top) {
                                Column(Modifier.weight(1f)) {
                                    Text(missionName(kind), style = DawnType.headline, color = ink, maxLines = 1)
                                    Text(stringResource(pickerLine(kind)), style = DawnType.footnote, color = ink.copy(alpha = 0.6f), maxLines = 1)
                                }
                                if (position != null) {
                                    Box(Modifier.size(26.dp).clip(CircleShape).background(DawnColors.Ink), contentAlignment = Alignment.Center) {
                                        Text("${position + 1}", style = DawnType.footnote.copy(fontWeight = FontWeight.Black), color = DawnColors.Yolk)
                                    }
                                }
                            }
                            Spacer(Modifier.weight(1f).heightIn(min = Spacing.xs))
                            MissionArt(kind, Modifier.offset(x = (-6).dp).size(96.dp, 64.dp), tone = if (chosen) ArtTone.ON_YOLK else ArtTone.ON_INK)
                        }
                    }
                }
                Column(Modifier.padding(horizontal = Spacing.s).padding(top = Spacing.sm, bottom = Spacing.xs), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (missions.isEmpty()) stringResource(R.string.picker_none)
                        else stringResource(R.string.picker_selected, missions.joinToString(" → ") { context.getString(missionNameRes(it.kind)) }),
                        style = DawnType.callout, color = colors.textSecondary, textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(Spacing.xs))
                    InkButton(onClick = { onDone(missions) }, enabled = missions.isNotEmpty()) { ButtonLabel(stringResource(R.string.done)) }
                }
            }
            preview?.let { kind -> MissionPreview(kind) { preview = null } }
        }
    }
}

/** Trying a mission from the picker, full screen, with a way out. */
@Composable
private fun MissionPreview(kind: MissionKind, config: MissionConfig? = null, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        DaylightTheme {
            Box(Modifier.fillMaxSize().background(Dawn.colors.background).safeDrawingPadding()) {
                val shown = config ?: if (kind == MissionKind.TYPING) MissionConfig.Typing("I am awake and ready") else kind.defaultConfig
                MissionView(shown, onClose)
                Box(
                    Modifier.align(Alignment.TopEnd).padding(Spacing.s).size(44.dp).clip(CircleShape)
                        .background(Dawn.colors.surfaceSecondary).clickable(onClick = onClose),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Rounded.Close, stringResource(R.string.close_preview), tint = Dawn.colors.textSecondary) }
            }
        }
    }
}

/** A few words for the tile: what you will do, not how it is set. */
private fun pickerLine(kind: MissionKind) = when (kind) {
    MissionKind.MATH -> R.string.picker_math
    MissionKind.SHAKE -> R.string.picker_shake
    MissionKind.STEPS -> R.string.picker_steps
    MissionKind.QR_CODE -> R.string.picker_qr
    MissionKind.MEMORY -> R.string.picker_memory
    MissionKind.TYPING -> R.string.picker_typing
    MissionKind.DRAW -> R.string.picker_draw
    MissionKind.JUMP -> R.string.picker_jump
    MissionKind.CATCH_CAT -> R.string.picker_catch
}

/** One mission's settings, and moving or removing it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MissionEditorSheet(
    mission: MissionConfig,
    canMoveEarlier: Boolean,
    canMoveLater: Boolean,
    onChange: (MissionConfig) -> Unit,
    onMove: (Int) -> Unit,
    onRemove: () -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val difficulties = context.resources.getStringArray(R.array.difficulty)
    // A mission that needs setting up opens straight into it the first time.
    var settingUp by remember { mutableStateOf(!mission.isConfigured && mission.kind.requiresSetup) }
    if (settingUp) {
        when (mission) {
            is MissionConfig.QrCode -> QrSetupDialog(onSave = { onChange(MissionConfig.QrCode(it)); settingUp = false }, onCancel = { settingUp = false })
            is MissionConfig.Draw -> DrawSetupDialog(onSave = { onChange(MissionConfig.Draw(it)); settingUp = false }, onCancel = { settingUp = false })
            else -> settingUp = false
        }
        // The sheet steps aside while the setup has the screen; a dialog cannot sit above it.
        return
    }
    var trying by remember { mutableStateOf(false) }
    if (trying) {
        MissionPreview(mission.kind, config = mission.takeIf { it.isConfigured }) { trying = false }
        return
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = Dawn.colors.background) {
        Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(horizontal = Spacing.m).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(Spacing.s)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(missionIcon(mission.kind), null, tint = Dawn.colors.accent)
                Spacer(Modifier.width(Spacing.xs))
                Text(missionName(mission.kind), style = DawnType.title, color = Dawn.colors.textPrimary)
            }
            Text(stringResource(missionDetailRes(mission.kind)), style = DawnType.callout, color = Dawn.colors.textSecondary)

            when (mission) {
                is MissionConfig.Math -> {
                    Segmented(stringResource(R.string.difficulty_label), difficulties.toList(), mission.difficulty.ordinal) {
                        onChange(mission.copy(difficulty = MathDifficulty.entries[it]))
                    }
                    Stepper(stringResource(R.string.rounds_label), mission.rounds, 1..5) { onChange(mission.copy(rounds = it)) }
                }
                is MissionConfig.Memory -> {
                    Segmented(stringResource(R.string.difficulty_label), difficulties.toList(), mission.difficulty.ordinal) {
                        onChange(mission.copy(difficulty = MemoryDifficulty.entries[it]))
                    }
                    Stepper(stringResource(R.string.rounds_label), mission.rounds, 1..3) { onChange(mission.copy(rounds = it)) }
                }
                is MissionConfig.Shake -> Stepper(stringResource(R.string.shakes_label), mission.targetCount, 5..50, step = 5) { onChange(mission.copy(targetCount = it)) }
                is MissionConfig.Steps -> {
                    Stepper(stringResource(R.string.steps_label), mission.targetCount, 10..100, step = 10) { onChange(mission.copy(targetCount = it)) }
                    StepsPermissionRow()
                }
                is MissionConfig.QrCode -> SetupRow(
                    done = mission.registeredCode != null,
                    doneText = stringResource(R.string.qr_registered),
                    action = stringResource(if (mission.registeredCode == null) R.string.qr_register else R.string.rescan),
                ) { settingUp = true }
                is MissionConfig.Draw -> SetupRow(
                    done = mission.referenceStrokes != null,
                    doneText = stringResource(R.string.calibrated),
                    action = stringResource(if (mission.referenceStrokes == null) R.string.draw_setup_action else R.string.draw_redraw),
                ) { settingUp = true }
                is MissionConfig.Jump -> Stepper(stringResource(R.string.jumps_label), mission.targetCount, 3..30) { onChange(mission.copy(targetCount = it)) }
                is MissionConfig.CatchCat -> Stepper(stringResource(R.string.catches_label), mission.catches, 3..20) { onChange(mission.copy(catches = it)) }
                is MissionConfig.Typing -> {
                    var text by remember { mutableStateOf(mission.phrase) }
                    OutlinedTextField(
                        value = text,
                        onValueChange = { text = it.take(80); onChange(mission.copy(phrase = text)) },
                        label = { Text(stringResource(R.string.typing_phrase)) },
                        supportingText = { Text(stringResource(R.string.typing_phrase_hint, MissionConfig.TYPING_MINIMUM_LENGTH)) },
                        isError = !mission.isConfigured,
                        modifier = Modifier.fillMaxWidth().keepAboveKeyboard(),
                    )
                }
                else -> Unit
            }
            if (!mission.isConfigured && mission.kind.requiresSetup) {
                Text(stringResource(R.string.setup_before_save), style = DawnType.footnote, color = Dawn.colors.warning)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                if (canMoveEarlier) TextButton(onClick = { onMove(-1) }) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, null); Spacer(Modifier.width(4.dp)); Text(stringResource(R.string.move_earlier))
                }
                if (canMoveLater) TextButton(onClick = { onMove(1) }) {
                    Text(stringResource(R.string.move_later)); Spacer(Modifier.width(4.dp)); Icon(Icons.AutoMirrored.Rounded.ArrowForward, null)
                }
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onRemove) { Text(stringResource(R.string.remove), color = Dawn.colors.destructive) }
            }
            SoftButton(onClick = { trying = true }) { ButtonLabel(stringResource(R.string.try_mission)) }
            InkButton(onClick = onDismiss, enabled = mission.isConfigured) { ButtonLabel(stringResource(R.string.done)) }
            Spacer(Modifier.height(Spacing.m))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Segmented(title: String, options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    Column {
        Text(title, style = DawnType.footnote.copy(fontWeight = FontWeight.Bold), color = Dawn.colors.textSecondary, modifier = Modifier.padding(bottom = 6.dp))
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            options.forEachIndexed { i, label ->
                SegmentedButton(selected = i == selected, onClick = { onSelect(i) }, shape = SegmentedButtonDefaults.itemShape(i, options.size)) { Text(label) }
            }
        }
    }
}

@Composable
private fun Stepper(title: String, value: Int, range: IntRange, step: Int = 1, onChange: (Int) -> Unit) {
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = DawnType.body, color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
            Text("$value", style = DawnType.display(22), color = Dawn.colors.textPrimary)
        }
        val steps = (range.last - range.first) / step - 1
        Slider(
            value = value.toFloat(),
            onValueChange = { onChange(((it - range.first) / step).roundToInt() * step + range.first) },
            valueRange = range.first.toFloat()..range.last.toFloat(),
            steps = maxOf(0, steps),
            colors = SliderDefaults.colors(thumbColor = Dawn.colors.accent, activeTrackColor = Dawn.colors.accent),
        )
    }
}

/** Whether the mission's setup is done, and the button that does (or redoes) it. */
@Composable
private fun SetupRow(done: Boolean, doneText: String, action: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary).padding(Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (done) Icons.Rounded.CheckCircle else Icons.Rounded.ErrorOutline, null,
            tint = if (done) Dawn.colors.success else Dawn.colors.warning)
        Spacer(Modifier.width(Spacing.xs))
        Text(if (done) doneText else stringResource(R.string.setup_needed), style = DawnType.callout, color = Dawn.colors.textPrimary, modifier = Modifier.weight(1f))
        TextButton(onClick = onClick) { Text(action, color = Dawn.colors.accent, fontWeight = FontWeight.Bold) }
    }
}

/**
 * Steps needs "Physical activity", asked for here, when the alarm is set — not at
 * 7 am, when a half-asleep "Don't allow" would silently turn Steps into Math.
 */
@Composable
private fun StepsPermissionRow() {
    val context = LocalContext.current
    val permission = Motion.activityPermission ?: return
    var granted by remember { mutableStateOf(Motion.canCountSteps(context)) }
    var asked by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it; asked = true }
    LaunchedEffect(Unit) { if (!granted) launcher.launch(permission) }
    if (granted) return
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary).padding(Spacing.s),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.ErrorOutline, null, tint = Dawn.colors.warning)
        Spacer(Modifier.width(Spacing.xs))
        Text(stringResource(R.string.steps_permission_needed), style = DawnType.footnote, color = Dawn.colors.textSecondary, modifier = Modifier.weight(1f))
        TextButton(onClick = { if (asked) Camera.openAppSettings(context) else launcher.launch(permission) }) {
            Text(stringResource(if (asked) R.string.open_settings else R.string.allow), color = Dawn.colors.accent, fontWeight = FontWeight.Bold)
        }
    }
}
