package uz.ata.dawnwick.alarm

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmRecurrence

/**
 * What actually makes the phone ring at a time. On a device that is Android's
 * `AlarmManager.setAlarmClock`; in tests, a list.
 */
interface AlarmEngine {
    /** Schedules the alarm's next occurrence under its own id. */
    fun schedule(alarm: Alarm)

    /** A one-shot ring under `reArmId`, `delayMillis` from now, for `alarm`. */
    fun scheduleReArm(alarm: Alarm, reArmId: String, delayMillis: Long)

    fun cancel(id: String)

    /** Every id the engine holds: alarms and re-arms. */
    fun pendingIds(): Set<String>
}

/** Who may have more than two alarms on, and Premium missions. */
fun interface EntitlementProvider {
    fun isPremium(): Boolean
}

object FreeTier {
    /** Alarms a free account can keep switched on at once. */
    const val ENABLED_ALARM_LIMIT = 2
}

sealed interface SaveResult {
    data class Success(val alarm: Alarm) : SaveResult
    /** Stored, but the engine refused it: it will not ring until reconcile succeeds. */
    data class PartialSuccess(val alarm: Alarm, val error: Throwable) : SaveResult
    data class Failure(val error: SaveError) : SaveResult
}

sealed interface SaveError {
    data class Validation(val reason: String) : SaveError
    data class Persistence(val error: Throwable) : SaveError
    /** The free tier's limit would be passed; the caller shows the paywall. */
    data object FreeAlarmLimit : SaveError
    /** A Premium mission on a free account; the caller shows the paywall. */
    data object PremiumMission : SaveError
}

/**
 * The single write boundary for alarms. Order for a save: validate, persist, cancel
 * every snooze and re-arm the previous version left, then schedule. The stored list
 * is always the truth; the engine is brought in line with it on every launch.
 */
class AlarmService(
    private val repository: AlarmRepository,
    private val engine: AlarmEngine,
    val registry: ReArmRegistry,
    private val entitlements: EntitlementProvider,
    private val clock: () -> Instant = Instant::now,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) {
    fun fetchAll(): List<Alarm> = repository.fetchAll()
    fun alarm(id: String): Alarm? = repository.alarm(id)

    fun save(alarm: Alarm): SaveResult {
        validate(alarm)?.let { return SaveResult.Failure(SaveError.Validation(it)) }
        freeTierRejection(alarm)?.let { return SaveResult.Failure(it) }
        try {
            repository.save(alarm)
        } catch (e: Exception) {
            return SaveResult.Failure(SaveError.Persistence(e))
        }
        cancelReArms(alarm.id)
        return try {
            if (alarm.isEnabled) engine.schedule(alarm) else engine.cancel(alarm.id)
            SaveResult.Success(alarm)
        } catch (e: Exception) {
            SaveResult.PartialSuccess(alarm, e)
        }
    }

    fun delete(id: String) {
        repository.delete(id)
        cancelReArms(id)
        runCatching { engine.cancel(id) }
    }

    /**
     * Two rules: a new alarm is refused once the free account already has the limit;
     * switching one on is refused when the limit is already on. A lapse never
     * silences alarms that exist — it only stops more being added.
     */
    private fun freeTierRejection(alarm: Alarm): SaveError? {
        if (entitlements.isPremium()) return null
        val existing = repository.fetchAll()
        val isNew = existing.none { it.id == alarm.id }
        if (isNew && existing.size >= FreeTier.ENABLED_ALARM_LIMIT) return SaveError.FreeAlarmLimit
        // New Premium missions are refused; ones kept from a lapsed subscription stay, so nothing set up is lost.
        val stored = existing.firstOrNull { it.id == alarm.id }
        if (alarm.missions != stored?.missions && alarm.missions.any { it.kind.isPremium }) return SaveError.PremiumMission
        if (!alarm.isEnabled) return null
        if (existing.firstOrNull { it.id == alarm.id }?.isEnabled == true) return null
        val othersOn = existing.count { it.id != alarm.id && it.isEnabled }
        return if (othersOn >= FreeTier.ENABLED_ALARM_LIMIT) SaveError.FreeAlarmLimit else null
    }

    // MARK: - Snooze and re-arms

    /** A registered snooze `delayMillis` from now. Returns its id, or null if it failed. */
    fun snooze(alarm: Alarm, delayMillis: Long): String? {
        val id = UUID.randomUUID().toString()
        return if (scheduleReArm(alarm, id, delayMillis, ReArmRegistry.Kind.SNOOZE)) id else null
    }

    /** A one-shot re-arm, registered first so it can always be found and cancelled. */
    fun scheduleReArm(alarm: Alarm, reArmId: String, delayMillis: Long, kind: ReArmRegistry.Kind = ReArmRegistry.Kind.RE_ARM): Boolean {
        val delay = maxOf(1000L, delayMillis)
        registry.register(reArmId, alarm.id, clock().toEpochMilli() + delay, kind)
        return try {
            engine.scheduleReArm(alarm, reArmId, delay)
            true
        } catch (e: Exception) {
            registry.remove(reArmId)
            false
        }
    }

    fun cancelReArm(id: String) {
        runCatching { engine.cancel(id) }
        registry.remove(id)
    }

    fun cancelReArms(originalId: String, kind: ReArmRegistry.Kind? = null) {
        for (id in registry.reArmIds(originalId, kind)) {
            runCatching { engine.cancel(id) }
            registry.remove(id)
        }
    }

    /**
     * After the mission: a one-time alarm is switched off and kept in the list; a
     * repeating one is scheduled for its next day.
     */
    fun completeOccurrence(alarm: Alarm) {
        cancelReArms(alarm.id)
        if (alarm.recurrence is AlarmRecurrence.OneTime) {
            repository.save(alarm.copy(isEnabled = false))
            runCatching { engine.cancel(alarm.id) }
        } else {
            repository.alarm(alarm.id)?.takeIf { it.isEnabled }?.let { runCatching { engine.schedule(it) } }
        }
    }

    // MARK: - Reconcile

    /**
     * Brings the engine in line with the list: enabled alarms are (re)scheduled — a
     * one-time alarm whose moment has passed is switched off instead — and ids that
     * are neither an enabled alarm nor a registered re-arm are cancelled.
     *
     * Unlike AlarmKit, Android keeps no list of what it will ring, and forgets all of
     * it on reboot or a clock change; so every enabled alarm is scheduled again,
     * which also moves it to the right instant after a time-zone change.
     */
    fun reconcile(skipIds: Set<String> = emptySet()) {
        for (stale in registry.prune(clock().toEpochMilli())) runCatching { engine.cancel(stale) }
        val alarms = repository.fetchAll()
        val active = alarms.filter { it.isEnabled }.map { it.id }.toSet()
        for (orphan in ReArmRegistry.orphanedReArmIds(registry.entries, active, clock().toEpochMilli())) {
            runCatching { engine.cancel(orphan) }
            registry.remove(orphan)
        }
        val plan = reconcilePlan(alarms, engine.pendingIds(), skipIds, registry.allReArmIds)
        for (alarm in plan.toSchedule) {
            val reason = validate(alarm)
            if (reason != null) {
                if (NextAlarmCalculator.isPastOneTime(alarm, clock(), zone())) {
                    repository.save(alarm.copy(isEnabled = false))
                    runCatching { engine.cancel(alarm.id) }
                    cancelReArms(alarm.id)
                }
                continue
            }
            runCatching { engine.schedule(alarm) }
        }
        for (id in plan.toCancel) runCatching { engine.cancel(id) }
    }

    data class ReconcilePlan(val toSchedule: List<Alarm>, val toCancel: Set<String>)

    // MARK: - Validation

    /** Why the alarm cannot be scheduled, or null when it can. */
    fun validate(alarm: Alarm): String? {
        val t = alarm.wallClockTime
        if (t.hour !in 0..23) return "Hour must be 0–23, got ${t.hour}"
        if (t.minute !in 0..59) return "Minute must be 0–59, got ${t.minute}"
        val r = alarm.recurrence
        if (r is AlarmRecurrence.Repeating && r.days.isEmpty()) return "A repeating alarm requires at least one weekday"
        if (r is AlarmRecurrence.OneTime && NextAlarmCalculator.isPastOneTime(alarm, clock(), zone())) {
            return "A one-time alarm must be scheduled in the future"
        }
        if (alarm.volume < MINIMUM_VOLUME) return "Volume must be at least ${(MINIMUM_VOLUME * 100).toInt()}%"
        if (alarm.missions.isEmpty()) return "An alarm requires at least one mission"
        if (alarm.missions.size > 3) return "A maximum of 3 missions is allowed"
        alarm.missions.firstOrNull { !it.isConfigured }?.let { return "'${it.kind}' mission requires setup before saving" }
        return null
    }

    companion object {
        /** Anything quieter is inaudible on a night stand. */
        const val MINIMUM_VOLUME = 0.3f

        /** The pure part of reconcile, so its rules can be tested without an engine. */
        fun reconcilePlan(alarms: List<Alarm>, pendingIds: Set<String>, skipIds: Set<String>, reArmIds: Set<String>): ReconcilePlan {
            val enabled = alarms.filter { it.isEnabled }
            val enabledIds = enabled.map { it.id }.toSet()
            return ReconcilePlan(
                toSchedule = enabled.filter { it.id !in skipIds },
                toCancel = pendingIds.filter { it !in enabledIds && it !in reArmIds }.toSet(),
            )
        }
    }
}
