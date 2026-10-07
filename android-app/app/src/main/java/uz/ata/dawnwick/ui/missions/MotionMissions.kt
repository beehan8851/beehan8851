package uz.ata.dawnwick.ui.missions

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import kotlin.math.sqrt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uz.ata.dawnwick.BuildConfig
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.missions.JumpDetector
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Spacing

/** What the phone can tell about walking and jumping, and whether it may. */
object Motion {
    fun hasStepSensor(context: Context): Boolean {
        val sm = context.getSystemService(SensorManager::class.java)
        return sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null || sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
    }

    fun hasAccelerometer(context: Context): Boolean =
        context.getSystemService(SensorManager::class.java).getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null

    /** Steps need "Physical activity" from Android 10 on. */
    val activityPermission: String? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Manifest.permission.ACTIVITY_RECOGNITION else null

    fun canCountSteps(context: Context): Boolean =
        activityPermission?.let { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED } ?: true
}

/**
 * The shape both counting missions share: a big icon that jumps with each count,
 * "3 / 20", a bar, and one line saying what to do or what went wrong.
 */
@Composable
private fun CountingMission(
    kind: MissionKind,
    count: Int,
    required: Int,
    bump: Float,
    message: String,
    problem: Boolean,
    simulateLabel: String?,
    onSimulate: () -> Unit,
) {
    val colors = Dawn.colors
    val progress by animateFloatAsState((count / required.toFloat()).coerceIn(0f, 1f), tween(200), label = "progress")
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        MissionHeader(kind)
        Spacer(Modifier.weight(1f))
        Icon(missionIcon(kind), null, tint = colors.accent, modifier = Modifier.size(80.dp).scale(bump))
        Spacer(Modifier.height(Spacing.m))
        Text("$count / $required", style = DawnType.display(52), color = colors.textPrimary,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        Spacer(Modifier.height(Spacing.s))
        Box(Modifier.padding(horizontal = Spacing.l).fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(colors.surfaceSecondary)) {
            Box(Modifier.fillMaxWidth(progress).height(6.dp).background(DawnColors.Yolk))
        }
        Spacer(Modifier.height(Spacing.m))
        Text(message, style = DawnType.callout, color = if (problem) colors.destructive else colors.textSecondary,
            textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = Spacing.l))
        Spacer(Modifier.weight(1f))
        if (simulateLabel != null) {
            TextButton(onClick = onSimulate, modifier = Modifier.padding(bottom = Spacing.l)) {
                Text(simulateLabel, style = DawnType.callout, color = colors.textSecondary)
            }
        } else {
            Spacer(Modifier.height(Spacing.xl))
        }
    }
}

// MARK: - Steps

/**
 * Steps from the step detector (one event a step), or the step counter, which counts
 * since boot — its first reading is only the starting point. Physical activity is
 * asked for when the alarm is saved, never here: an alarm that cannot count steps is
 * turned into Math before this screen is reached.
 */
@Composable
fun StepsMission(config: MissionConfig.Steps, onSuccess: () -> Unit) {
    val context = LocalContext.current
    val required = config.targetCount
    var count by remember { mutableIntStateOf(0) }
    var done by remember { mutableStateOf(false) }
    val bump = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()
    val haptic = rememberHaptics()
    val success by rememberUpdatedState(onSuccess)
    val available = remember { Motion.hasStepSensor(context) }
    val allowed = remember { Motion.canCountSteps(context) }

    fun add(n: Int) {
        if (done || n <= 0) return
        count = minOf(required, count + n)
        haptic.perform(Haptic.SELECTION)
        scope.launch { bump.snapTo(1.18f); bump.animateTo(1f, spring(dampingRatio = 0.4f)) }
        if (count >= required) {
            done = true
            haptic.perform(Haptic.SUCCESS)
            scope.launch { delay(300); success() }
        }
    }

    DisposableEffect(available, allowed) {
        val sm = context.getSystemService(SensorManager::class.java)
        val detector = sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        val counter = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        var baseline: Float? = null
        var counted = 0
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                when (event.sensor.type) {
                    Sensor.TYPE_STEP_DETECTOR -> add(1)
                    Sensor.TYPE_STEP_COUNTER -> {
                        val raw = event.values[0]
                        val base = baseline ?: raw.also { baseline = it }
                        val total = (raw - base).toInt()
                        add(total - counted)
                        counted = total
                    }
                }
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        if (available && allowed) {
            val sensor = detector ?: counter
            sensor?.let { sm.registerListener(listener, it, SensorManager.SENSOR_DELAY_UI) }
        }
        onDispose { sm.unregisterListener(listener) }
    }

    CountingMission(
        kind = MissionKind.STEPS,
        count = count,
        required = required,
        bump = bump.value,
        message = when {
            !available -> stringResource(R.string.steps_unavailable)
            !allowed -> stringResource(R.string.steps_denied)
            else -> stringResource(R.string.steps_instruction)
        },
        problem = !available || !allowed,
        simulateLabel = if (BuildConfig.DEBUG) stringResource(R.string.simulate_steps) else null,
        onSimulate = { add(5) },
    )
}

// MARK: - Jump

/** Jumps with the phone in hand, from the accelerometer. */
@Composable
fun JumpMission(config: MissionConfig.Jump, onSuccess: () -> Unit) {
    val context = LocalContext.current
    val required = config.targetCount
    var count by remember { mutableIntStateOf(0) }
    var done by remember { mutableStateOf(false) }
    val bump = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()
    val haptic = rememberHaptics()
    val success by rememberUpdatedState(onSuccess)
    val available = remember { Motion.hasAccelerometer(context) }

    fun jumped() {
        if (done) return
        count++
        haptic.perform(Haptic.HEAVY)
        scope.launch { bump.snapTo(1.3f); bump.animateTo(1f, spring(dampingRatio = 0.35f)) }
        if (count >= required) {
            done = true
            haptic.perform(Haptic.SUCCESS)
            scope.launch { delay(300); success() }
        }
    }

    DisposableEffect(available) {
        val sm = context.getSystemService(SensorManager::class.java)
        val detector = JumpDetector()
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val (x, y, z) = event.values
                val g = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
                if (detector.onReading(g.toDouble(), System.currentTimeMillis())) jumped()
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sm.registerListener(listener, it, SensorManager.SENSOR_DELAY_GAME) }
        onDispose { sm.unregisterListener(listener) }
    }

    CountingMission(
        kind = MissionKind.JUMP,
        count = count,
        required = required,
        bump = bump.value,
        message = if (available) stringResource(R.string.jump_instruction) else stringResource(R.string.jump_unavailable),
        problem = !available,
        simulateLabel = if (BuildConfig.DEBUG) stringResource(R.string.simulate_jump) else null,
        onSimulate = ::jumped,
    )
}
