package uz.ata.dawnwick.ui.missions

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlin.math.sin
import kotlinx.coroutines.delay
import uz.ata.dawnwick.R
import uz.ata.dawnwick.ui.haptics.Haptic
import uz.ata.dawnwick.ui.haptics.rememberHaptics
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind
import uz.ata.dawnwick.missions.CatchMission
import uz.ata.dawnwick.ui.cat.CatMotion
import uz.ata.dawnwick.ui.cat.CatMove
import uz.ata.dawnwick.ui.cat.CatStage
import uz.ata.dawnwick.ui.cat.CatMood
import uz.ata.dawnwick.ui.cat.reduceMotion
import uz.ata.dawnwick.ui.theme.Dawn
import uz.ata.dawnwick.ui.theme.DawnColors
import uz.ata.dawnwick.ui.theme.DawnType
import uz.ata.dawnwick.ui.theme.Spacing

/**
 * The cat will not sit still; catch it. It sits a little under two seconds, fidgets
 * just before it goes, and jumps somewhere well away. A tap on the floor startles it.
 */
@Composable
fun CatchCatMission(config: MissionConfig.CatchCat, onSuccess: () -> Unit) {
    val mission = remember { CatchMission(config.catches) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val haptic = rememberHaptics()
    val success by rememberUpdatedState(onSuccess)
    val still = reduceMotion()

    LaunchedEffect(Unit) {
        mission.start(System.currentTimeMillis())
        while (!mission.isDone) {
            withFrameMillis { }
            now = System.currentTimeMillis()
            mission.tick(now)
        }
        delay(350)
        success()
    }

    val springy = spring<Float>(dampingRatio = 0.75f, stiffness = Spring.StiffnessMediumLow)
    val x by animateFloatAsState(mission.x.toFloat(), if (still) spring(stiffness = Spring.StiffnessHigh) else springy, label = "x")
    val y by animateFloatAsState(mission.y.toFloat(), if (still) spring(stiffness = Spring.StiffnessHigh) else springy, label = "y")
    val colors = Dawn.colors

    Column(Modifier.fillMaxSize().padding(horizontal = Spacing.m)) {
        MissionHeader(MissionKind.CATCH_CAT)
        Text("${mission.caught} / ${mission.required}", style = DawnType.display(44), color = colors.textPrimary)
        Text(stringResource(R.string.catch_hint), style = DawnType.callout, color = colors.textSecondary)
        BoxWithConstraints(
            Modifier.fillMaxWidth().weight(1f).padding(vertical = Spacing.s)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    mission.miss(System.currentTimeMillis())
                    haptic.perform(Haptic.ERROR)
                },
        ) {
            val inset = 50.dp
            val catSize = 116.dp
            val cx = inset + (maxWidth - inset * 2) * x
            val cy = inset + (maxHeight - inset * 2).coerceAtLeast(1.dp) * y
            val startled = mission.isStartled(now)
            val left = (mission.jumpsAt ?: Long.MAX_VALUE) - now
            val fidget = if (!still && left < 350) (sin(now / 1000.0 * 60) * 7).toFloat() else 0f
            val catLabel = stringResource(R.string.cat)
            Box(
                Modifier.offset(cx - catSize / 2, cy - catSize / 2).size(catSize).rotate(fidget)
                    .semantics { contentDescription = catLabel; role = Role.Button }
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                        if (mission.catchCat(System.currentTimeMillis())) {
                            haptic.perform(if (mission.isDone) Haptic.SUCCESS else Haptic.MEDIUM)
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(100.dp).offset(y = 6.dp).clip(CircleShape).background(DawnColors.Yolk))
                // A hop each time it moves; a fright when a tap misses.
                CatMotion(if (startled) CatMove.STARTLE else CatMove.HOP, mission.jumps, 78.dp) {
                    CatStage(
                        when { mission.isDone -> CatMood.PROUD; startled -> CatMood.STARTLED; else -> CatMood.AWAKE },
                        Modifier.width(88.dp),
                        animated = startled,
                    )
                }
            }
        }
    }
}
