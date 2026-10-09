package uz.ata.dawnwick.ring

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import uz.ata.dawnwick.AppGraph
import uz.ata.dawnwick.alarm.ReArmRegistry
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.core.AppJson

/**
 * The ringing alarm and everything about it: which alarm, which id is ringing for
 * it, how many snoozes it has had, the wake check after it.
 *
 * Invariants, as in the iOS app:
 * - `present` is the only place that sets the ringing state, and it runs before any
 *   re-arm is forgotten: nothing is silenced until the ring screen has an alarm.
 * - The sound stops only when the mission is done or the snooze is scheduled.
 * - While an alarm rings, a re-arm two minutes out is always registered, so a
 *   killed process or a reboot cannot end the ring without the mission.
 */
class RingController(private val context: Context, private val graph: AppGraph) {

    @Serializable
    data class Ringing(val alarm: Alarm, val alertingId: String?, val startedAtMillis: Long)

    private val _state = MutableStateFlow<Ringing?>(null)
    val state: StateFlow<Ringing?> = _state.asStateFlow()

    /** The wake check waiting for an answer, if any. */
    private val _wakeCheck = MutableStateFlow<Alarm?>(null)
    val wakeCheck: StateFlow<Alarm?> = _wakeCheck.asStateFlow()

    private val service get() = graph.alarmService
    private val registry get() = graph.registry
    private val store get() = graph.store

    init {
        // Back after a kill: the ring screen comes straight back if it was fresh.
        restore()?.let { _state.value = it }
        loadWakeCheck()?.let { (id, _) -> _wakeCheck.value = resolve(id) }
    }

    // MARK: - An alarm fires

    /**
     * Every "this id is ringing" signal goes through here: the alarm itself, a
     * snooze, a re-arm, the wake check's auto-fail, the test alarm. Returns the alarm
     * to ring for, or null when there is nothing (a deleted alarm's leftover).
     */
    @Synchronized
    fun fire(id: String): Alarm? {
        val current = _state.value
        if (current != null && current.alertingId == id) return current.alarm

        registry.entry(id)?.let { entry ->
            val alarm = current?.alarm?.takeIf { it.id == entry.originalId } ?: resolve(entry.originalId)
            if (alarm == null) {
                service.cancelReArm(id)
                return null
            }
            present(alarm, id)
            // It fired; it is no longer pending. A test entry stays until the mission,
            // so the transient alarm can still be found after a relaunch.
            if (entry.kind != ReArmRegistry.Kind.TEST) registry.remove(id)
            if (entry.kind == ReArmRegistry.Kind.WAKE_CHECK || _wakeCheck.value?.id == alarm.id) clearWakeCheck()
            ensurePersistenceReArm(alarm)
            return alarm
        }

        val alarm = resolve(id) ?: return null
        present(alarm, id)
        // Re-arms left from an earlier occurrence are stale now.
        service.cancelReArms(alarm.id, ReArmRegistry.Kind.RE_ARM)
        if (_wakeCheck.value?.id == alarm.id) clearWakeCheck()
        ensurePersistenceReArm(alarm)
        // A repeating alarm is due again next time: schedule it now, not after the
        // mission, so a phone left ringing on the night stand still rings tomorrow.
        if (alarm.isEnabled) runCatching { graph.engine.schedule(alarm) }
        return alarm
    }

    private fun present(alarm: Alarm, alertingId: String?) {
        val ringing = Ringing(alarm, alertingId, _state.value?.takeIf { it.alarm.id == alarm.id }?.startedAtMillis ?: System.currentTimeMillis())
        _state.value = ringing
        store.putString(RINGING_KEY, AppJson.encodeToString(Ringing.serializer(), ringing))
    }

    private fun ensurePersistenceReArm(alarm: Alarm) {
        if (_state.value?.alarm?.id != alarm.id) return
        if (registry.reArmIds(alarm.id, ReArmRegistry.Kind.RE_ARM).isNotEmpty()) return
        service.scheduleReArm(alarm, UUID.randomUUID().toString(), PERSISTENCE_RE_ARM_MILLIS)
    }

    /** The stored alarm, or the transient test alarm when the id came from the test flow. */
    private fun resolve(id: String): Alarm? =
        service.alarm(id) ?: if (registry.isTestOriginal(id)) Alarm.testAlarm(id, graph.preferences.defaultSound) else null

    // MARK: - The mission is done

    @Synchronized
    fun complete(alarm: Alarm) {
        stopSound()
        if (registry.isTestOriginal(alarm.id)) {
            service.cancelReArms(alarm.id)
        } else {
            service.completeOccurrence(alarm)
            // A won morning; a test alarm is not one.
            graph.streak.recordCompletion(graph.repository.fetchAll())
            graph.refreshCompanion()
            uz.ata.dawnwick.widgets.DawnWidgets.refresh(context)
            returnToToday = true
        }
        clearRinging()
        setSnoozeCount(alarm.id, null)
    }

    // MARK: - Snooze

    fun snoozeCount(alarmId: String): Int = snoozeCounts()[alarmId] ?: 0

    /** False when the snooze could not be scheduled: then the alarm keeps ringing. */
    @Synchronized
    fun snooze(alarm: Alarm): Boolean {
        val count = snoozeCount(alarm.id)
        if (!alarm.snooze.isEnabled) return false
        if (alarm.snooze.maxCount != -1 && count >= alarm.snooze.maxCount) return false
        // The snooze is scheduled before anything is silenced.
        service.cancelReArms(alarm.id, ReArmRegistry.Kind.RE_ARM)
        val id = service.snooze(alarm, alarm.snooze.durationMinutes * 60_000L)
        if (id == null) {
            ensurePersistenceReArm(alarm)
            return false
        }
        setSnoozeCount(alarm.id, count + 1)
        stopSound()
        clearRinging()
        return true
    }

    // MARK: - Test alarm

    /** A real alarm thirty seconds out, at full volume: hear it before you trust it. */
    fun scheduleTestAlarm(): Boolean {
        val alarm = Alarm.testAlarm(UUID.randomUUID().toString(), graph.preferences.defaultSound)
        return service.scheduleReArm(alarm, UUID.randomUUID().toString(), TEST_ALARM_MILLIS, ReArmRegistry.Kind.TEST)
    }

    // MARK: - Wake check

    /**
     * After the mission: in `durationMinutes` a "Still awake?" notification; two
     * minutes after that, unless someone answered, the alarm rings again.
     */
    fun scheduleWakeCheck(alarm: Alarm) {
        if (!alarm.wakeCheck.isEnabled) return
        val promptAt = System.currentTimeMillis() + alarm.wakeCheck.durationMinutes * 60_000L
        store.putString(WAKE_CHECK_KEY, "${alarm.id}|$promptAt")
        _wakeCheck.value = alarm
        service.cancelReArms(alarm.id, ReArmRegistry.Kind.WAKE_CHECK)
        service.scheduleReArm(alarm, UUID.randomUUID().toString(),
            alarm.wakeCheck.durationMinutes * 60_000L + WAKE_CHECK_PROMPT_TIMEOUT_MILLIS, ReArmRegistry.Kind.WAKE_CHECK)
        WakeCheckReceiver.schedulePrompt(context, promptAt)
    }

    /** "I'm awake." */
    fun acknowledgeWakeCheck() = clearWakeCheck()

    /**
     * "I fell back asleep": the check is over and the alarm rings again, through a
     * re-arm a few seconds out so it rings the way any alarm does.
     */
    fun failWakeCheck() {
        val alarm = _wakeCheck.value ?: loadWakeCheck()?.first?.let { resolve(it) }
        clearWakeCheck()
        if (alarm != null) service.scheduleReArm(alarm, UUID.randomUUID().toString(), WAKE_CHECK_FAIL_DELAY_MILLIS)
    }

    /** Set when a morning is won, so the app opens on Today and the cat can celebrate. */
    @Volatile var returnToToday = false

    /** When the prompt shows; null when there is none. */
    fun wakeCheckPromptAt(): Long? = loadWakeCheck()?.second

    private fun clearWakeCheck() {
        val alarm = _wakeCheck.value ?: loadWakeCheck()?.first?.let { resolve(it) }
        _wakeCheck.value = null
        store.remove(WAKE_CHECK_KEY)
        WakeCheckReceiver.cancel(context)
        alarm?.let { service.cancelReArms(it.id, ReArmRegistry.Kind.WAKE_CHECK) }
    }

    private fun loadWakeCheck(): Pair<String, Long>? {
        val raw = store.getString(WAKE_CHECK_KEY) ?: return null
        val parts = raw.split("|")
        return if (parts.size == 2) parts[0] to (parts[1].toLongOrNull() ?: return null) else null
    }

    // MARK: - Ringing state

    private fun clearRinging() {
        _state.value = null
        store.remove(RINGING_KEY)
    }

    private fun restore(): Ringing? {
        val raw = store.getString(RINGING_KEY) ?: return null
        val ringing = runCatching { AppJson.decodeFromString(Ringing.serializer(), raw) }.getOrNull()
        val age = ringing?.let { System.currentTimeMillis() - it.startedAtMillis }
        if (ringing == null || age == null || age < 0 || age > RINGING_MAX_AGE_MILLIS) {
            store.remove(RINGING_KEY)
            return null
        }
        return ringing
    }

    private fun stopSound() {
        context.startService(Intent(context, RingService::class.java).setAction(RingService.ACTION_STOP))
    }

    /** Starts the sound for `id` from the foreground (a notification action, a relaunch). */
    fun startSound(id: String) {
        ContextCompat.startForegroundService(context,
            Intent(context, RingService::class.java).setAction(RingService.ACTION_RING).putExtra(AlarmReceiver.EXTRA_ID, id))
    }

    private val countsSerializer = MapSerializer(String.serializer(), Int.serializer())

    private fun snoozeCounts(): Map<String, Int> =
        store.getString(SNOOZE_KEY)?.let { runCatching { AppJson.decodeFromString(countsSerializer, it) }.getOrNull() } ?: emptyMap()

    private fun setSnoozeCount(id: String, count: Int?) {
        val counts = snoozeCounts().toMutableMap()
        if (count == null) counts.remove(id) else counts[id] = count
        store.putString(SNOOZE_KEY, AppJson.encodeToString(countsSerializer, counts))
    }

    companion object {
        const val PERSISTENCE_RE_ARM_MILLIS = 2 * 60_000L
        const val WAKE_CHECK_FAIL_DELAY_MILLIS = 5_000L
        const val TEST_ALARM_MILLIS = 30_000L
        const val WAKE_CHECK_PROMPT_TIMEOUT_MILLIS = 2 * 60_000L
        /** Ringing older than this is not brought back on launch. */
        const val RINGING_MAX_AGE_MILLIS = 15 * 60_000L
        private const val RINGING_KEY = "ring.state.v1"
        private const val SNOOZE_KEY = "ring.snoozeCounts.v1"
        private const val WAKE_CHECK_KEY = "ring.wakeCheck.v1"
    }
}
