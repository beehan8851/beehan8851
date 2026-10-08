package uz.ata.dawnwick.ui.missions

import uz.ata.dawnwick.graph
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Calculate
import androidx.compose.material.icons.rounded.Draw
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material.icons.rounded.Pets
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material.icons.rounded.SportsGymnastics
import androidx.compose.material.icons.rounded.Vibration
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.MissionKind

fun missionIcon(kind: MissionKind): ImageVector = when (kind) {
    MissionKind.MATH -> Icons.Rounded.Calculate
    MissionKind.SHAKE -> Icons.Rounded.Vibration
    MissionKind.STEPS -> Icons.Rounded.DirectionsWalk
    MissionKind.QR_CODE -> Icons.Rounded.QrCodeScanner
    MissionKind.MEMORY -> Icons.Rounded.GridView
    MissionKind.TYPING -> Icons.Rounded.Keyboard
    MissionKind.DRAW -> Icons.Rounded.Draw
    MissionKind.JUMP -> Icons.Rounded.SportsGymnastics
    MissionKind.CATCH_CAT -> Icons.Rounded.Pets
}

fun missionNameRes(kind: MissionKind): Int = when (kind) {
    MissionKind.MATH -> R.string.mission_math
    MissionKind.SHAKE -> R.string.mission_shake
    MissionKind.STEPS -> R.string.mission_steps
    MissionKind.QR_CODE -> R.string.mission_qr
    MissionKind.MEMORY -> R.string.mission_memory
    MissionKind.TYPING -> R.string.mission_typing
    MissionKind.DRAW -> R.string.mission_draw
    MissionKind.JUMP -> R.string.mission_jump
    MissionKind.CATCH_CAT -> R.string.mission_catch_cat
}

@Composable
fun missionName(kind: MissionKind): String = LocalContext.current.getString(missionNameRes(kind))

fun missionDetailRes(kind: MissionKind): Int = when (kind) {
    MissionKind.MATH -> R.string.mission_math_detail
    MissionKind.SHAKE -> R.string.mission_shake_detail
    MissionKind.STEPS -> R.string.mission_steps_detail
    MissionKind.QR_CODE -> R.string.mission_qr_detail
    MissionKind.MEMORY -> R.string.mission_memory_detail
    MissionKind.TYPING -> R.string.mission_typing_detail
    MissionKind.DRAW -> R.string.mission_draw_detail
    MissionKind.JUMP -> R.string.mission_jump_detail
    MissionKind.CATCH_CAT -> R.string.mission_catch_cat_detail
}

/** "Medium · 3 rounds", "10 shakes", "\"Good morning\"". */
fun missionSummary(context: Context, m: MissionConfig): String {
    val r = context.resources
    return when (m) {
        is MissionConfig.Math -> "${r.getStringArray(R.array.difficulty)[m.difficulty.ordinal]} · ${r.getQuantityString(R.plurals.rounds, m.rounds, m.rounds)}"
        is MissionConfig.Memory -> "${r.getStringArray(R.array.difficulty)[m.difficulty.ordinal]} · ${r.getQuantityString(R.plurals.rounds, m.rounds, m.rounds)}"
        is MissionConfig.Shake -> r.getQuantityString(R.plurals.shakes, m.targetCount, m.targetCount)
        is MissionConfig.Steps -> r.getQuantityString(R.plurals.steps, m.targetCount, m.targetCount)
        is MissionConfig.Jump -> r.getQuantityString(R.plurals.jumps, m.targetCount, m.targetCount)
        is MissionConfig.CatchCat -> context.getString(R.string.catches_n, m.catches)
        is MissionConfig.Typing -> if (m.phrase.isBlank()) context.getString(R.string.typing_no_phrase)
            else "“" + (if (m.phrase.length > 22) m.phrase.take(22) + "…" else m.phrase) + "”"
        is MissionConfig.QrCode -> context.getString(if (m.registeredCode == null) R.string.not_configured else R.string.ready)
        is MissionConfig.Draw -> context.getString(if (m.referenceStrokes == null) R.string.not_calibrated else R.string.calibrated)
    }
}

/**
 * Whether a mission can run on this phone, now. One that cannot is refused in the
 * picker and, should it slip through (a permission taken away later, a screen reader
 * switched on), becomes Math at ring time with a note — never a screen nobody can
 * get past at 7 am.
 */
object MissionCapability {

    /** Missions with no way through for someone using TalkBack. */
    private fun blockedByScreenReader(kind: MissionKind) =
        kind == MissionKind.DRAW || kind == MissionKind.QR_CODE || kind == MissionKind.MEMORY || kind == MissionKind.CATCH_CAT

    private fun screenReaderOn(context: Context) =
        context.getSystemService(android.view.accessibility.AccessibilityManager::class.java)?.isTouchExplorationEnabled == true

    /** Why `kind` cannot be chosen on this phone at all, or null. */
    fun reasonUnavailable(context: Context, kind: MissionKind): String? = when (kind) {
        MissionKind.SHAKE, MissionKind.JUMP ->
            if (Motion.hasAccelerometer(context)) null else context.getString(R.string.mission_no_accelerometer, context.getString(missionNameRes(kind)))
        MissionKind.STEPS -> if (Motion.hasStepSensor(context)) null else context.getString(R.string.mission_no_step_sensor)
        MissionKind.QR_CODE -> if (Camera.present(context)) null else context.getString(R.string.mission_no_camera)
        else -> null
    }

    /** Why it cannot run right now — everything above, plus permissions and setup. */
    private fun reasonCannotRun(context: Context, m: MissionConfig): String? {
        // A lapsed subscription: the alarm still rings, the morning is not the place for a paywall.
        if (m.kind.isPremium && !context.graph.isPremium) {
            return context.getString(R.string.mission_premium_swapped, context.getString(missionNameRes(m.kind)))
        }
        reasonUnavailable(context, m.kind)?.let { return it }
        if (!m.isConfigured) return context.getString(R.string.mission_needs_setup_swapped)
        val name = context.getString(missionNameRes(m.kind))
        return when {
            m.kind == MissionKind.STEPS && !Motion.canCountSteps(context) -> context.getString(R.string.mission_permission_swapped, name)
            m.kind == MissionKind.QR_CODE && !Camera.allowed(context) -> context.getString(R.string.mission_permission_swapped, name)
            screenReaderOn(context) && blockedByScreenReader(m.kind) -> context.getString(R.string.mission_screen_reader_swapped, name)
            else -> null
        }
    }

    /** The missions to run, with Math in place of any that cannot, and why. */
    fun runnable(context: Context, missions: List<MissionConfig>): Pair<List<MissionConfig>, List<String>> {
        val notes = mutableListOf<String>()
        val list = missions.ifEmpty { listOf(MissionConfig.defaultMath) }.map { m ->
            val reason = reasonCannotRun(context, m)
            if (reason == null) m else {
                notes += reason
                MissionConfig.defaultMath
            }
        }
        return list to notes.distinct()
    }
}
