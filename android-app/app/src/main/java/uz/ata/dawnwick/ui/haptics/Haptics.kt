package uz.ata.dawnwick.ui.haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import uz.ata.dawnwick.graph

/** The feels the app uses, named as iOS names them. */
enum class Haptic { SELECTION, SOFT, LIGHT, MEDIUM, HEAVY, RIGID, SUCCESS, WARNING, ERROR }

/**
 * Every haptic in the app goes through here, so the Haptics switch in Settings
 * turns all of them off — not only the alarm's.
 */
class Haptics(private val context: Context) {
    private val vibrator: Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        else @Suppress("DEPRECATION") context.getSystemService(Vibrator::class.java)

    private val enabled get() = context.graph.preferences.hapticsEnabled && vibrator?.hasVibrator() == true

    fun perform(h: Haptic) {
        if (!enabled) return
        val v = vibrator ?: return
        val effect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            when (h) {
                Haptic.SELECTION, Haptic.SOFT, Haptic.LIGHT -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK)
                Haptic.MEDIUM -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                Haptic.HEAVY, Haptic.RIGID -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
                Haptic.SUCCESS -> VibrationEffect.createWaveform(longArrayOf(0, 18, 90, 28), intArrayOf(0, 120, 0, 220), -1)
                Haptic.WARNING -> VibrationEffect.createWaveform(longArrayOf(0, 30, 110, 30), intArrayOf(0, 200, 0, 140), -1)
                Haptic.ERROR -> VibrationEffect.createWaveform(longArrayOf(0, 30, 70, 30, 70, 40), intArrayOf(0, 220, 0, 220, 0, 255), -1)
            }
        } else {
            VibrationEffect.createOneShot(if (h == Haptic.HEAVY || h == Haptic.RIGID || h == Haptic.ERROR) 30 else 12, VibrationEffect.DEFAULT_AMPLITUDE)
        }
        runCatching { v.vibrate(effect) }
    }

    /**
     * The feel of a purr, looping: about 26 taps a second breathing out, 23 and
     * softer breathing in, swelling and fading with each breath of the sound.
     */
    fun purr() {
        if (!enabled) return
        val v = vibrator ?: return
        if (!v.hasAmplitudeControl()) return
        val timings = mutableListOf<Long>()
        val amplitudes = mutableListOf<Int>()
        fun stretch(length: Double, rate: Double, gain: Double) {
            var t = 0.0
            val step = 1000 / rate
            while (t < length * 1000) {
                val swell = sin(PI * t / (length * 1000)).coerceAtLeast(0.0).pow(0.6)
                timings += 8; amplitudes += (255 * gain * swell).toInt().coerceIn(1, 255)
                timings += (step - 8).toLong(); amplitudes += 0
                t += step
            }
        }
        stretch(1.05, 26.0, 0.5)
        timings += 120; amplitudes += 0
        stretch(0.72, 23.0, 0.3)
        timings += 110; amplitudes += 0
        runCatching { v.vibrate(VibrationEffect.createWaveform(timings.toLongArray(), amplitudes.toIntArray(), 0)) }
    }

    fun stopPurr() { runCatching { vibrator?.cancel() } }
}

@Composable
fun rememberHaptics(): Haptics {
    val context = LocalContext.current.applicationContext
    return remember { Haptics(context) }
}
