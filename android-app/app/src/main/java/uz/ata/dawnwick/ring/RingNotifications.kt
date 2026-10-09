package uz.ata.dawnwick.ring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import uz.ata.dawnwick.MainActivity
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.ui.format.TimeFormat

/** The notifications an alarm needs: the ringing one, and the wake check. */
object RingNotifications {
    const val CHANNEL_RING = "ring"
    const val CHANNEL_WAKE_CHECK = "wake_check"
    const val ID_RING = 1001
    private const val ID_WAKE_CHECK = 1002

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        // The sound is the service's own, at alarm volume; the channel stays silent
        // so the two never play over each other.
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_RING, context.getString(R.string.channel_ring), NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                enableVibration(false)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_WAKE_CHECK, context.getString(R.string.channel_wake_check), NotificationManager.IMPORTANCE_HIGH),
        )
    }

    /** The ringing notification: on a locked or idle phone it opens the ring screen itself. */
    fun ringing(context: Context, alarm: Alarm): Notification {
        val fullScreen = PendingIntent.getActivity(
            context, 0,
            Intent(context, RingActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = alarm.label.ifBlank { context.getString(R.string.app_name) }
        return NotificationCompat.Builder(context, CHANNEL_RING)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(context.getString(R.string.ring_notification_body, TimeFormat.time(context, alarm.wallClockTime)))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .build()
    }

    fun showWakeCheck(context: Context, alarm: Alarm) {
        val open = PendingIntent.getActivity(
            context, 2, Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_WAKE_CHECK, true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val awake = PendingIntent.getBroadcast(
            context, 3, Intent(context, WakeCheckReceiver::class.java).setAction(WakeCheckReceiver.ACTION_AWAKE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val body = if (alarm.label.isBlank()) context.getString(R.string.wake_check_body)
        else context.getString(R.string.wake_check_body_label, alarm.label)
        val notification = NotificationCompat.Builder(context, CHANNEL_WAKE_CHECK)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(context.getString(R.string.wake_check_title))
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(0, context.getString(R.string.wake_check_awake), awake)
            .build()
        runCatching { context.getSystemService(NotificationManager::class.java).notify(ID_WAKE_CHECK, notification) }
    }

    fun cancelWakeCheck(context: Context) =
        context.getSystemService(NotificationManager::class.java).cancel(ID_WAKE_CHECK)
}
