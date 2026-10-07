package uz.ata.dawnwick.ring

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.ServiceCompat
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.graph

/**
 * The alarm, ringing: the sound on the alarm stream, the vibration, and the
 * full-screen notification that puts the ring screen over a locked phone. It goes on
 * in the background whatever the screen does, and stops only when the mission is
 * done or the snooze is set.
 */
class RingService : Service() {
    private var player: TonePlayer? = null
    private var ringingAlarmId: String? = null
    private var restoreVolume: Int? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RING -> {
                val id = intent.getStringExtra(AlarmReceiver.EXTRA_ID)
                val alarm = id?.let { graph.ring.fire(it) } ?: graph.ring.state.value?.alarm
                if (alarm == null) {
                    // A deleted alarm's leftover: nothing to ring for.
                    id?.let { graph.alarmService.cancelReArm(it) }
                    stopSelfCompletely()
                    return START_NOT_STICKY
                }
                startRinging(alarm)
            }
            ACTION_STOP -> stopSelfCompletely()
            // Quiet in the hand while a mission is on screen: the buzz would also be
            // counted as shakes and jumps by the accelerometer.
            ACTION_VIBRATION -> if (intent.getBooleanExtra(EXTRA_ON, true)) { if (ringingAlarmId != null) vibrate() } else vibrator().cancel()
            else -> {
                // Restarted by the system after a kill: carry on if something is ringing.
                val alarm = graph.ring.state.value?.alarm
                if (alarm == null) stopSelfCompletely() else startRinging(alarm)
            }
        }
        return START_STICKY
    }

    private fun startRinging(alarm: Alarm) {
        val notification = RingNotifications.ringing(this, alarm)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0
        ServiceCompat.startForeground(this, RingNotifications.ID_RING, notification, type)

        if (wakeLock == null) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dawnwick:ring")
                .apply { acquire(30 * 60_000L) }
        }
        // The same alarm again (a re-arm while it rings): the sound is already going.
        if (ringingAlarmId == alarm.id && player != null) return
        ringingAlarmId = alarm.id

        if (restoreVolume == null) restoreVolume = TonePlayer.raiseAlarmStream(this, alarm.volume)
        player?.stop()
        player = TonePlayer(this, alarmStream = true).also { it.play(alarm.sound, 1f, alarm.gradualWake.seconds) }
        vibrate()

        // Over the lock screen at once when the app may: the notification covers the rest.
        runCatching {
            startActivity(Intent(this, RingActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    private fun vibrator(): Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        getSystemService(VibratorManager::class.java).defaultVibrator
    } else {
        @Suppress("DEPRECATION") getSystemService(Vibrator::class.java)
    }

    private fun vibrate() {
        if (!graph.preferences.hapticsEnabled) return
        val vibrator = vibrator()
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 600, 400, 600, 1400), 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION") vibrator.vibrate(effect)
        }
    }

    private fun stopSelfCompletely() {
        player?.stop()
        player = null
        ringingAlarmId = null
        restoreVolume?.let { TonePlayer.restoreAlarmStream(this, it) }
        restoreVolume = null
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION") getSystemService(Vibrator::class.java)
        }
        vibrator.cancel()
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        player?.stop()
        restoreVolume?.let { TonePlayer.restoreAlarmStream(this, it) }
        wakeLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }

    companion object {
        const val ACTION_RING = "uz.ata.dawnwick.RING"
        const val ACTION_STOP = "uz.ata.dawnwick.STOP"
        const val ACTION_VIBRATION = "uz.ata.dawnwick.VIBRATION"
        const val EXTRA_ON = "on"

        /** Turns the ring's vibration off while a mission is shown, and back on after. */
        fun setVibration(context: android.content.Context, on: Boolean) {
            runCatching { context.startService(Intent(context, RingService::class.java).setAction(ACTION_VIBRATION).putExtra(EXTRA_ON, on)) }
        }
    }
}
