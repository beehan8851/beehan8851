package uz.ata.dawnwick.ui.missions

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Backspace
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import uz.ata.dawnwick.ui.components.keepAboveKeyboard
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import kotlin.math.sqrt
import kotlin.random.Random
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.BuildConfig
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.alarm.model.MathDifficulty
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

@Composable
fun MissionHeader(kind: MissionKind, rounds: Int = 1, done: Int = 0) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth().padding(top = Spacing.l, bottom = Spacing.s)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(missionIcon(kind), null, tint = Dawn.colors.accent, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(missionName(kind), style = DawnType.callout.copy(fontWeight = FontWeight.SemiBold), color = Dawn.colors.textSecondary)
        }
        if (rounds > 1) {
            Spacer(Modifier.height(Spacing.xs))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                repeat(rounds) { i ->
                    Box(Modifier.size(8.dp).clip(CircleShape).background(if (i <= done) DawnColors.Yolk else Dawn.colors.surfaceSecondary))
                }
            }
        }
    }
}

// MARK: - Math

/** One sum to solve. Medium and hard cycle through their operations, as the iOS app does. */
data class MathProblem(val a: Int, val b: Int, val op: Char) {
    val answer get() = when (op) { '+' -> a + b; '−' -> a - b; else -> a * b }
    val display get() = "$a  $op  $b"

    companion object {
        fun generate(difficulty: MathDifficulty, index: Int, random: Random = Random): MathProblem {
            fun r(range: IntRange) = random.nextInt(range.first, range.last + 1)
            return when (difficulty) {
                MathDifficulty.EASY -> MathProblem(r(2..9), r(2..9), '+')
                MathDifficulty.MEDIUM -> when (index % 3) {
                    0 -> MathProblem(r(10..40), r(5..20), '+')
                    1 -> { val a = r(15..50); MathProblem(a, r(3..minOf(a - 1, 15)), '−') }
                    else -> MathProblem(r(3..9), r(3..9), '×')
                }
                MathDifficulty.HARD -> when (index % 3) {
                    1 -> { val a = r(30..99); MathProblem(a, r(10..minOf(a - 5, 30)), '−') }
                    else -> MathProblem(r(12..19), r(3..9), '×')
                }
            }
        }
    }
}

@Composable
fun MathMission(config: MissionConfig.Math, onSuccess: () -> Unit) {
    val problems = remember { List(config.rounds) { MathProblem.generate(config.difficulty, it) } }
    var index by remember { mutableIntStateOf(0) }
    var input by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }
    val shake = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val haptic = rememberHaptics()
    val current = problems[index]
    val colors = Dawn.colors

    fun check() {
        val entered = input.toIntOrNull() ?: return
        if (entered == current.answer) {
            haptic.perform(Haptic.SUCCESS)
            input = ""
            if (index + 1 < problems.size) index++ else onSuccess()
        } else {
            haptic.perform(Haptic.ERROR)
            wrong = true
            scope.launch {
                shake.animateTo(14f, spring(dampingRatio = 0.2f, stiffness = 800f))
                shake.animateTo(0f, spring(dampingRatio = 0.6f))
                delay(700)
                wrong = false
                input = ""
            }
        }
    }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(MissionKind.MATH, problems.size, index)
        Spacer(Modifier.weight(1f))
        Text(current.display, style = DawnType.display(52), color = colors.textPrimary)
        Text("=", style = DawnType.display(36, FontWeight.Medium), color = colors.textTertiary)
        Box(
            Modifier.padding(horizontal = Spacing.xl).fillMaxWidth().height(80.dp)
                .offset { IntOffset(shake.value.roundToInt(), 0) }
                .clip(RoundedCornerShape(Radius.m))
                .background(if (wrong) colors.destructive.copy(alpha = 0.12f) else colors.surfacePrimary)
                .border(1.5.dp, if (wrong) colors.destructive else colors.surfaceSecondary, RoundedCornerShape(Radius.m)),
            contentAlignment = Alignment.Center,
        ) {
            Text(input.ifEmpty { "?" }, style = DawnType.display(40, FontWeight.Medium),
                color = when { input.isEmpty() -> colors.textTertiary; wrong -> colors.destructive; else -> colors.textPrimary })
        }
        Spacer(Modifier.height(Spacing.s))
        Text(if (wrong) stringResource(R.string.math_wrong) else stringResource(R.string.math_round, index + 1, problems.size),
            style = DawnType.footnote, color = if (wrong) colors.destructive else colors.textSecondary)
        Spacer(Modifier.weight(1f))
        Column(Modifier.padding(horizontal = Spacing.l).padding(bottom = Spacing.l).widthIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            for (row in listOf(listOf(1, 2, 3), listOf(4, 5, 6), listOf(7, 8, 9))) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    row.forEach { d -> Key(Modifier.weight(1f), colors.surfacePrimary, onClick = { if (input.length < 4) input += d }) { Text("$d", style = DawnType.display(28, FontWeight.Normal), color = colors.textPrimary) } }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                val delete = stringResource(R.string.delete)
                Key(Modifier.weight(1f).semantics { contentDescription = delete }, colors.surfaceSecondary, onClick = { input = input.dropLast(1) }) {
                    Icon(Icons.AutoMirrored.Rounded.Backspace, null, tint = colors.textSecondary)
                }
                Key(Modifier.weight(1f), colors.surfacePrimary, onClick = { if (input.length < 4) input += "0" }) { Text("0", style = DawnType.display(28, FontWeight.Normal), color = colors.textPrimary) }
                val submit = stringResource(R.string.submit_answer)
                Key(Modifier.weight(1f).semantics { contentDescription = submit }, if (input.isEmpty()) colors.surfaceSecondary else DawnColors.Yolk, onClick = ::check) {
                    Icon(Icons.Rounded.Check, null, tint = if (input.isEmpty()) colors.textTertiary else DawnColors.Ink)
                }
            }
        }
    }
}

@Composable
private fun Key(modifier: Modifier, color: androidx.compose.ui.graphics.Color, onClick: () -> Unit, content: @Composable () -> Unit) {
    var pressed by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (pressed) 0.92f else 1f, tween(80), label = "key")
    Box(
        modifier.height(64.dp).scale(scale).clip(RoundedCornerShape(Radius.s)).background(color)
            .clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) { content() }
}

// MARK: - Typing

@Composable
fun TypingMission(config: MissionConfig.Typing, onSuccess: () -> Unit) {
    val phrase = config.phrase.ifBlank { "Good morning" }
    var input by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val haptic = rememberHaptics()
    val colors = Dawn.colors
    LaunchedEffect(Unit) { delay(500); runCatching { focus.requestFocus() } }

    fun check() {
        if (done) return
        if (input.trim().equals(phrase.trim(), ignoreCase = true)) {
            done = true
            haptic.perform(Haptic.SUCCESS)
            onSuccess()
        } else {
            haptic.perform(Haptic.ERROR)
            wrong = true
        }
    }

    Column(Modifier.fillMaxSize().imePadding(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(MissionKind.TYPING)
        Spacer(Modifier.weight(1f))
        Text(stringResource(R.string.typing_instruction), style = DawnType.callout, color = colors.textSecondary)
        Spacer(Modifier.height(Spacing.s))
        Text("“$phrase”", style = DawnType.display(24), color = colors.textPrimary, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.l))
        Spacer(Modifier.height(Spacing.l))
        OutlinedTextField(
            value = input,
            onValueChange = { input = it; wrong = false },
            singleLine = true,
            isError = wrong,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Go),
            keyboardActions = KeyboardActions(onGo = { check() }),
            shape = RoundedCornerShape(Radius.m),
            colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = colors.accent, unfocusedContainerColor = colors.surfacePrimary, focusedContainerColor = colors.surfacePrimary),
            modifier = Modifier.padding(horizontal = Spacing.l).fillMaxWidth().focusRequester(focus).keepAboveKeyboard(),
        )
        if (wrong) Text(stringResource(R.string.typing_wrong), style = DawnType.footnote, color = colors.destructive, modifier = Modifier.padding(top = Spacing.xs))
        Spacer(Modifier.weight(1f))
        InkButton(onClick = ::check, enabled = input.isNotBlank(), modifier = Modifier.padding(horizontal = Spacing.l).padding(bottom = Spacing.l)) {
            ButtonLabel(stringResource(R.string.done))
        }
    }
}

// MARK: - Memory

@Composable
fun MemoryMission(config: MissionConfig.Memory, onSuccess: () -> Unit) {
    val columns = config.difficulty.columns
    val cells = columns * columns
    var round by remember { mutableIntStateOf(0) }
    var phase by remember { mutableStateOf("memorize") }
    var highlighted by remember { mutableStateOf(emptySet<Int>()) }
    var selected by remember { mutableStateOf(emptySet<Int>()) }
    var wrong by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    val drain = remember { Animatable(1f) }
    val haptic = rememberHaptics()
    val colors = Dawn.colors

    LaunchedEffect(round, attempt) {
        selected = emptySet()
        wrong = false
        phase = "memorize"
        highlighted = (0 until cells).shuffled().take(config.difficulty.highlightCount).toSet()
        drain.snapTo(1f)
        drain.animateTo(0f, tween(2500, easing = LinearEasing))
        phase = "hidden"
        delay(400)
        phase = "recall"
    }
    LaunchedEffect(selected) {
        if (phase != "recall" || selected.size != highlighted.size) return@LaunchedEffect
        phase = "feedback"
        if (selected == highlighted) {
            haptic.perform(Haptic.SUCCESS)
            delay(600)
            if (round + 1 >= config.rounds) onSuccess() else round++
        } else {
            haptic.perform(Haptic.ERROR)
            wrong = true
            delay(900)
            attempt++
        }
    }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(MissionKind.MEMORY, config.rounds, round)
        Spacer(Modifier.weight(1f))
        Text(
            when (phase) {
                "memorize", "hidden" -> stringResource(R.string.memory_memorize)
                "recall" -> stringResource(R.string.memory_recall)
                else -> if (wrong) stringResource(R.string.memory_wrong) else stringResource(R.string.memory_correct)
            },
            style = DawnType.callout,
            color = when { phase == "feedback" && wrong -> colors.destructive; phase == "feedback" -> colors.success; else -> colors.textSecondary },
        )
        Spacer(Modifier.height(Spacing.xs))
        Box(Modifier.width(120.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(colors.surfaceSecondary)) {
            if (phase == "memorize") Box(Modifier.fillMaxWidth(drain.value).height(3.dp).background(DawnColors.Yolk))
        }
        Spacer(Modifier.height(Spacing.m))
        Column(Modifier.padding(horizontal = Spacing.l).widthIn(max = 420.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (r in 0 until columns) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (c in 0 until columns) {
                        val idx = r * columns + c
                        val lit = (phase == "memorize" && idx in highlighted) || ((phase == "recall" || phase == "feedback") && idx in selected)
                        val label = stringResource(R.string.cell_position, r + 1, c + 1)
                        Box(
                            Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(10.dp))
                                .background(if (lit) DawnColors.Yolk else colors.surfacePrimary)
                                .semantics { contentDescription = label }
                                .clickable(enabled = phase == "recall") {
                                    haptic.perform(Haptic.SELECTION)
                                    selected = if (idx in selected) selected - idx else selected + idx
                                },
                        )
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
    }
}

// MARK: - Shake

/**
 * Shakes counted from the accelerometer: a jolt well past gravity, at most one per
 * quarter second, so one hard shake is not counted three times.
 */
@Composable
fun ShakeMission(config: MissionConfig.Shake, onSuccess: () -> Unit) {
    val context = LocalContext.current
    val required = config.targetCount
    var count by remember { mutableIntStateOf(0) }
    val bump = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()
    val haptic = rememberHaptics()
    val colors = Dawn.colors

    fun shook() {
        if (count >= required) return
        count++
        haptic.perform(Haptic.SELECTION)
        scope.launch { bump.snapTo(1.25f); bump.animateTo(1f, spring(dampingRatio = 0.38f)) }
        if (count >= required) onSuccess()
    }

    DisposableEffect(Unit) {
        val manager = context.getSystemService(SensorManager::class.java)
        val sensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        var last = 0L
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val (x, y, z) = event.values
                val g = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
                val now = System.currentTimeMillis()
                if (g > 2.2f && now - last > 250) {
                    last = now
                    shook()
                }
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        sensor?.let { manager.registerListener(listener, it, SensorManager.SENSOR_DELAY_GAME) }
        onDispose { manager.unregisterListener(listener) }
    }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(MissionKind.SHAKE)
        Spacer(Modifier.weight(1f))
        Icon(missionIcon(MissionKind.SHAKE), null, tint = colors.accent, modifier = Modifier.size(80.dp).scale(bump.value))
        Spacer(Modifier.height(Spacing.m))
        Text("$count / $required", style = DawnType.display(52), color = colors.textPrimary)
        Spacer(Modifier.height(Spacing.s))
        Box(Modifier.padding(horizontal = Spacing.l).fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(colors.surfaceSecondary)) {
            Box(Modifier.fillMaxWidth(count / required.toFloat()).height(6.dp).background(DawnColors.Yolk))
        }
        Spacer(Modifier.height(Spacing.m))
        Text(stringResource(R.string.shake_instruction), style = DawnType.callout, color = colors.textSecondary)
        Spacer(Modifier.weight(1f))
        // Debug builds only: no one wants to shake a phone on a desk to test the flow.
        if (BuildConfig.DEBUG) {
            androidx.compose.material3.TextButton(onClick = ::shook, modifier = Modifier.padding(bottom = Spacing.l)) {
                Text(stringResource(R.string.simulate_shake), style = DawnType.callout, color = colors.textSecondary)
            }
        }
    }
}
