package uz.ata.dawnwick.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Alarm
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.DirectionsRun
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.SaveError
import uz.ata.dawnwick.alarm.SaveResult
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.AlarmTime
import uz.ata.dawnwick.alarm.model.MathDifficulty
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.cat.CatGround
import uz.ata.dawnwick.ui.cat.CatMascot
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.components.ButtonLabel
import uz.ata.dawnwick.ui.components.InkButton
import uz.ata.dawnwick.ui.components.YolkButton
import uz.ata.dawnwick.ui.components.pressable
import uz.ata.dawnwick.ui.editor.TimeDrum
import uz.ata.dawnwick.ui.permissions.AlarmPermission
import uz.ata.dawnwick.ui.permissions.rememberPermissionTick
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Radius
import uz.ata.dawnwick.ui.theme.Spacing

private enum class Step { WELCOME, PERMISSIONS, FIRST_ALARM }

/** The two missions offered first: both free, both gentle. A first morning is no place for twelve rounds of sums. */
private enum class FirstMission(val title: Int, val detail: Int, val config: MissionConfig) {
    MATH(R.string.mission_math, R.string.onb_mission_math_detail, MissionConfig.Math(MathDifficulty.EASY, 1)),
    SHAKE(R.string.mission_shake, R.string.onb_mission_shake_detail, MissionConfig.Shake(15)),
}

/**
 * Three steps, as on iOS: what the app is, the permissions an alarm needs, the first alarm.
 * Nothing is asked for before the person has read what it is for. [onFinished] runs
 * when they set an alarm or skip; either way onboarding is done.
 */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    var step by remember { mutableStateOf(Step.WELCOME) }
    val welcome = step == Step.WELCOME
    Box(
        Modifier.fillMaxSize().background(if (welcome) DawnColors.Yolk else Dawn.colors.background).safeDrawingPadding(),
    ) {
        when (step) {
            Step.WELCOME -> WelcomeStep { step = Step.PERMISSIONS }
            Step.PERMISSIONS -> PermissionsStep { step = Step.FIRST_ALARM }
            Step.FIRST_ALARM -> FirstAlarmStep(onFinished)
        }
    }
}

@Composable
private fun StepFrame(footer: @Composable () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Spacing.s, vertical = Spacing.m),
            verticalArrangement = Arrangement.spacedBy(Spacing.m),
        ) { content() }
        Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.s, vertical = Spacing.s), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) { footer() }
    }
}

@Composable
private fun WelcomeStep(onNext: () -> Unit) = StepFrame(
    footer = { InkButton(onNext, Modifier.fillMaxWidth()) { ButtonLabel(stringResource(R.string.onb_get_started)) } },
) {
    CatMascot(CatMood.RINGING, Modifier.fillMaxWidth().height(220.dp), ground = CatGround.LIGHT)
    Text(stringResource(R.string.onb_tagline), style = DawnType.display(32), color = DawnColors.Ink)
    Text(stringResource(R.string.onb_subtitle), style = DawnType.callout, color = DawnColors.OnYolkSecondary)
    Point(Icons.Rounded.Alarm, R.string.onb_point_alarm)
    Point(Icons.Rounded.DirectionsRun, R.string.onb_point_missions)
    Point(Icons.Rounded.Bedtime, R.string.onb_point_sleep)
}

@Composable
private fun Point(icon: ImageVector, text: Int) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = DawnColors.Ink, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(Spacing.sm))
        Text(stringResource(text), style = DawnType.body, color = DawnColors.Ink)
    }
}

@Composable
private fun PermissionsStep(onNext: () -> Unit) {
    val context = LocalContext.current
    val tick = rememberPermissionTick()
    val granted = remember(tick) { AlarmPermission.entries.associateWith { it.isGranted(context) } }
    // Notifications first ask Android's own dialog; after a "Don't allow" only Settings can turn them on.
    val askNotifications = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { if (!it) AlarmPermission.NOTIFICATIONS.open(context) }
    val missingCritical = AlarmPermission.entries.any { it.critical && granted[it] != true }
    StepFrame(
        footer = {
            YolkButton(onNext, Modifier.fillMaxWidth()) { ButtonLabel(stringResource(R.string.next)) }
            if (missingCritical) {
                Text(stringResource(R.string.onb_permissions_missing), style = DawnType.footnote, color = Dawn.colors.textSecondary)
            }
        },
    ) {
        CatMascot(CatMood.AWAKE, Modifier.fillMaxWidth().height(150.dp), ground = if (Dawn.colors.isDark) CatGround.DARK else CatGround.LIGHT)
        Text(stringResource(R.string.onb_permissions_title), style = DawnType.display(28), color = Dawn.colors.textPrimary)
        Text(stringResource(R.string.onb_permissions_subtitle), style = DawnType.callout, color = Dawn.colors.textSecondary)
        Column(Modifier.clip(RoundedCornerShape(Radius.m)).background(Dawn.colors.surfacePrimary)) {
            AlarmPermission.entries.forEach { permission ->
                val on = granted[permission] == true
                Row(
                    Modifier.fillMaxWidth().pressable(enabled = !on) {
                        if (permission == AlarmPermission.NOTIFICATIONS && android.os.Build.VERSION.SDK_INT >= 33) {
                            askNotifications.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                        } else permission.open(context)
                    }.padding(Spacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(permission.title), style = DawnType.headline, color = Dawn.colors.textPrimary)
                        Text(stringResource(permission.detail), style = DawnType.footnote, color = Dawn.colors.textSecondary)
                        if (!permission.critical && !on) {
                            Text(stringResource(R.string.onb_permission_optional), style = DawnType.footnote, color = Dawn.colors.textTertiary)
                        }
                    }
                    Spacer(Modifier.width(Spacing.xs))
                    if (on) {
                        Icon(Icons.Rounded.CheckCircle, stringResource(R.string.onb_permission_granted), tint = Dawn.colors.success, modifier = Modifier.size(24.dp))
                    } else {
                        Text(stringResource(R.string.allow), style = DawnType.headline, color = Dawn.colors.accent)
                    }
                }
            }
        }
    }
}

@Composable
private fun FirstAlarmStep(onFinished: () -> Unit) {
    val graph = LocalContext.current.graph
    val label = stringResource(R.string.onb_default_label)
    var hour by remember { mutableIntStateOf(7) }
    var minute by remember { mutableIntStateOf(0) }
    var mission by remember { mutableStateOf(FirstMission.MATH) }
    var error by remember { mutableStateOf<String?>(null) }
    val saveFailed = R.string.onb_save_failed

    val context = LocalContext.current
    fun save() {
        val alarm = Alarm(
            label = label,
            wallClockTime = AlarmTime(hour, minute),
            recurrence = AlarmRecurrence.Daily,
            missions = listOf(mission.config),
            isEnabled = true,
        )
        when (val result = graph.alarmService.save(alarm)) {
            // Stored but not scheduled: the alarm list says so and the next reconcile retries. Not worth stopping here.
            is SaveResult.Success, is SaveResult.PartialSuccess -> onFinished()
            is SaveResult.Failure -> error = context.getString(
                saveFailed,
                when (val e = result.error) {
                    is SaveError.Validation -> e.reason
                    is SaveError.Persistence -> e.error.message.orEmpty()
                    SaveError.FreeAlarmLimit, SaveError.PremiumMission -> ""
                },
            )
        }
    }

    StepFrame(
        footer = {
            error?.let { Text(it, style = DawnType.footnote, color = Dawn.colors.destructive) }
            YolkButton(::save, Modifier.fillMaxWidth()) { ButtonLabel(stringResource(R.string.onb_set_alarm)) }
            TextButton(onClick = onFinished, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.onb_skip), style = DawnType.headline, color = Dawn.colors.textSecondary)
            }
        },
    ) {
        CatMascot(CatMood.PROUD, Modifier.fillMaxWidth().height(120.dp), ground = if (Dawn.colors.isDark) CatGround.DARK else CatGround.LIGHT)
        Text(stringResource(R.string.onb_first_alarm_title), style = DawnType.display(28), color = Dawn.colors.textPrimary)
        Text(stringResource(R.string.onb_first_alarm_subtitle), style = DawnType.callout, color = Dawn.colors.textSecondary)
        TimeDrum(hour, minute, Dawn.colors.textPrimary) { h, m -> hour = h; minute = m }
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            FirstMission.entries.forEach { option ->
                val selected = option == mission
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(Radius.m))
                        .background(if (selected) DawnColors.Yolk else Dawn.colors.surfacePrimary)
                        .pressable { mission = option }.padding(Spacing.s),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(option.title), style = DawnType.headline, color = if (selected) DawnColors.Ink else Dawn.colors.textPrimary)
                        Text(stringResource(option.detail), style = DawnType.footnote, color = if (selected) DawnColors.OnYolkSecondary else Dawn.colors.textSecondary)
                    }
                    if (selected) Icon(Icons.Rounded.CheckCircle, null, tint = DawnColors.Ink, modifier = Modifier.size(22.dp))
                }
            }
        }
    }
}
