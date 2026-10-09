package uz.ata.dawnwick.ui.missions

import androidx.compose.runtime.Composable
import uz.ata.dawnwick.alarm.model.MissionConfig

/** Any mission, by its settings: what the ring screen hosts and the picker previews. */
@Composable
fun MissionView(config: MissionConfig, onSuccess: () -> Unit) {
    when (config) {
        is MissionConfig.Math -> MathMission(config, onSuccess)
        is MissionConfig.Typing -> TypingMission(config, onSuccess)
        is MissionConfig.Memory -> MemoryMission(config, onSuccess)
        is MissionConfig.Shake -> ShakeMission(config, onSuccess)
        is MissionConfig.Steps -> StepsMission(config, onSuccess)
        is MissionConfig.Jump -> JumpMission(config, onSuccess)
        is MissionConfig.QrCode -> QrMission(config, onSuccess)
        is MissionConfig.Draw -> DrawMission(config, onSuccess)
        is MissionConfig.CatchCat -> CatchCatMission(config, onSuccess)
    }
}
