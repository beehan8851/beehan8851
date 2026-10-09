package uz.ata.dawnwick.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import uz.ata.dawnwick.MainActivity
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore
import uz.ata.dawnwick.ring.AlarmReceiver

/**
 * Rings through `AlarmManager.setAlarmClock`: the one schedule Android treats as an
 * alarm clock. It fires on time in Doze, shows in the status bar and on the lock
 * screen as the next alarm, and lets the receiver start the ringing service from
 * the background.
 *
 * Android keeps no list of what it will ring, so the engine keeps its own: the id
 * and the instant of everything it scheduled.
 */
class SystemAlarmEngine(
    private val context: Context,
    private val store: KeyValueStore,
) : AlarmEngine {

    class NotPermittedException : IllegalStateException("Exact alarms are not allowed for this app")

    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val serializer = MapSerializer(String.serializer(), Long.serializer())

    override fun schedule(alarm: Alarm) {
        val at = NextAlarmCalculator.nextFireTime(alarm) ?: run { cancel(alarm.id); return }
        setAlarmClock(alarm.id, at.toEpochMilli())
    }

    override fun scheduleReArm(alarm: Alarm, reArmId: String, delayMillis: Long) =
        setAlarmClock(reArmId, System.currentTimeMillis() + delayMillis)

    override fun cancel(id: String) {
        alarmManager.cancel(fireIntent(id))
        forget(id)
    }

    override fun pendingIds(): Set<String> = pending().keys

    /** The next instant anything will ring, for the Today screen and the editor. */
    fun nextRingMillis(): Long? = pending().values.filter { it > System.currentTimeMillis() }.minOrNull()

    /** Called by the receiver as an id fires: it is no longer pending. */
    fun markFired(id: String) = forget(id)

    fun canScheduleExact(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    private fun setAlarmClock(id: String, atMillis: Long) {
        if (!canScheduleExact()) throw NotPermittedException()
        val show = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(atMillis, show), fireIntent(id))
        remember(id, atMillis)
    }

    /** One PendingIntent per id: the data URI keeps them apart. */
    private fun fireIntent(id: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, AlarmReceiver::class.java)
            .setAction(AlarmReceiver.ACTION_FIRE)
            .setData(Uri.parse("dawnwick://alarm/$id"))
            .putExtra(AlarmReceiver.EXTRA_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    @Synchronized
    private fun pending(): Map<String, Long> =
        store.getString(KEY)?.let { runCatching { AppJson.decodeFromString(serializer, it) }.getOrNull() } ?: emptyMap()

    @Synchronized
    private fun remember(id: String, at: Long) = store.putString(KEY, AppJson.encodeToString(serializer, pending() + (id to at)))

    @Synchronized
    private fun forget(id: String) {
        val all = pending()
        if (id in all) store.putString(KEY, AppJson.encodeToString(serializer, all - id))
    }

    companion object {
        private const val KEY = "engine.pending.v1"
    }
}
