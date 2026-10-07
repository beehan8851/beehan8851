package uz.ata.dawnwick.ring

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import uz.ata.dawnwick.graph

/**
 * An alarm's moment has come. Starts the ringing service at once — the receiver may
 * be killed as soon as it returns, and a setAlarmClock broadcast is what allows a
 * foreground service to start from the background.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        context.graph.engine.markFired(id)
        ContextCompat.startForegroundService(
            context,
            Intent(context, RingService::class.java).setAction(RingService.ACTION_RING).putExtra(EXTRA_ID, id),
        )
    }

    companion object {
        const val ACTION_FIRE = "uz.ata.dawnwick.FIRE"
        const val EXTRA_ID = "id"
    }
}

/**
 * Android forgets every scheduled alarm on reboot, and moves none of them when the
 * clock or the time zone changes. Each of those puts the schedule back from the
 * stored list.
 */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                val graph = context.graph
                // Everything Android held is gone after a reboot: start the list afresh.
                if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_LOCKED_BOOT_COMPLETED) {
                    graph.store.remove("engine.pending.v1")
                }
                // Re-arms of a ring that was going on are scheduled again too.
                for ((id, entry) in graph.registry.entries) {
                    val original = graph.alarmService.alarm(id = entry.originalId)
                        ?: graph.ring.state.value?.alarm?.takeIf { it.id == entry.originalId }
                        ?: continue
                    val delay = maxOf(5_000L, entry.fireAtMillis - System.currentTimeMillis())
                    runCatching { graph.engine.scheduleReArm(original, id, delay) }
                }
                graph.alarmService.reconcile(skipIds = graph.registry.allReArmIds)
                graph.bedtime.reschedule()
                // A ring in progress when the phone went down starts again.
                graph.ring.state.value?.let { graph.ring.startSound(it.alertingId ?: it.alarm.id) }
            } finally {
                pending.finish()
            }
        }.start()
    }
}

/** "Still awake?" — the prompt after a wake check's minutes are up. */
class WakeCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_PROMPT -> {
                val alarm = context.graph.ring.wakeCheck.value ?: return
                RingNotifications.showWakeCheck(context, alarm)
            }
            ACTION_AWAKE -> {
                context.graph.ring.acknowledgeWakeCheck()
                RingNotifications.cancelWakeCheck(context)
            }
        }
    }

    companion object {
        const val ACTION_PROMPT = "uz.ata.dawnwick.WAKE_CHECK_PROMPT"
        const val ACTION_AWAKE = "uz.ata.dawnwick.WAKE_CHECK_AWAKE"

        private fun intent(context: Context) = PendingIntent.getBroadcast(
            context, 1,
            Intent(context, WakeCheckReceiver::class.java).setAction(ACTION_PROMPT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun schedulePrompt(context: Context, atMillis: Long) {
            val manager = context.getSystemService(AlarmManager::class.java)
            runCatching { manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, intent(context)) }
                .onFailure { manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, intent(context)) }
        }

        fun cancel(context: Context) {
            context.getSystemService(AlarmManager::class.java).cancel(intent(context))
            RingNotifications.cancelWakeCheck(context)
        }
    }
}
