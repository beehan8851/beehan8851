package uz.ata.dawnwick.sleep

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.time.LocalDateTime
import java.time.ZoneId
import uz.ata.dawnwick.MainActivity
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore
import uz.ata.dawnwick.graph
import uz.ata.dawnwick.ui.format.TimeFormat

/**
 * The nightly "time to wind down": a notification at the chosen time every night,
 * which opens the wind-down. A reminder does not need to be to the minute, so it is
 * an inexact alarm within a few minutes, set again each time it arrives and after a
 * restart.
 */
class BedtimeScheduler(private val context: Context, private val store: KeyValueStore) {
    fun load(): BedtimeReminder = store.getString(KEY)?.let { runCatching { AppJson.decodeFromString(BedtimeReminder.serializer(), it) }.getOrNull() }?.clamped()
        ?: BedtimeReminder()

    fun canNotify() = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Stores the setting and makes the system match it; nothing is stored as on that cannot arrive. */
    fun apply(reminder: BedtimeReminder): BedtimeReminder {
        val r = if (reminder.isEnabled && !canNotify()) reminder.copy(isEnabled = false) else reminder.clamped()
        store.putString(KEY, AppJson.encodeToString(BedtimeReminder.serializer(), r))
        if (r.isEnabled) schedule(r) else cancel()
        return r
    }

    fun reschedule() { load().takeIf { it.isEnabled }?.let(::schedule) }

    private fun pending() = PendingIntent.getBroadcast(context, 77, Intent(context, BedtimeReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    private fun schedule(r: BedtimeReminder) {
        val now = LocalDateTime.now()
        var at = now.toLocalDate().atTime(r.hour, r.minute)
        if (!at.isAfter(now)) at = at.plusDays(1)
        val millis = at.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        context.getSystemService(AlarmManager::class.java).setWindow(AlarmManager.RTC_WAKEUP, millis, 5 * 60_000L, pending())
    }

    private fun cancel() = context.getSystemService(AlarmManager::class.java).cancel(pending())

    companion object { const val KEY = "sleep.bedtime.v1" }
}

class BedtimeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val graph = context.graph
        val reminder = graph.bedtime.load()
        if (!reminder.isEnabled) return
        graph.bedtime.reschedule()
        if (!graph.bedtime.canNotify()) return
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.channel_bedtime), NotificationManager.IMPORTANCE_DEFAULT))
        val next = graph.alarmService.fetchAll().mapNotNull { a -> NextAlarmCalculator.nextFireTime(a)?.let { a to it } }.minByOrNull { it.second }
        val body = next?.let { (alarm, at) ->
            val time = TimeFormat.clock(context, at.toEpochMilli())
            context.getString(R.string.bedtime_body, if (alarm.label.isBlank()) time else "$time — ${alarm.label}")
        } ?: context.getString(R.string.bedtime_body_no_alarm)
        val open = PendingIntent.getActivity(context, 78,
            Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_TAB, 2).putExtra(MainActivity.EXTRA_WIND_DOWN, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        nm.notify(ID, NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(context.getString(R.string.bedtime_title))
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build())
    }

    companion object {
        private const val CHANNEL = "bedtime"
        private const val ID = 4402
    }
}
