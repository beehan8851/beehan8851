package uz.ata.dawnwick.alarm

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmDate
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.AlarmTime
import uz.ata.dawnwick.alarm.model.Weekday

/**
 * When an alarm rings next: pure, deterministic, the time zone passed in so tests
 * can pin it. A time that does not exist on a day (a clock jumping forward) rings at
 * the first moment after the gap, as `ZonedDateTime` resolves it.
 */
object NextAlarmCalculator {

    /** The next instant strictly after `after`, or null if it never rings again. */
    fun nextFireTime(alarm: Alarm, after: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant? {
        if (!alarm.isEnabled) return null
        return when (val r = alarm.recurrence) {
            is AlarmRecurrence.OneTime -> nextOneTime(r.date, alarm.wallClockTime, after, zone)
            is AlarmRecurrence.Repeating -> if (r.days.isEmpty()) null else nextRepeating(r.days, alarm.wallClockTime, after, zone)
            AlarmRecurrence.Daily -> nextRepeating(Weekday.all, alarm.wallClockTime, after, zone)
        }
    }

    private fun at(date: java.time.LocalDate, time: AlarmTime, zone: ZoneId): Instant =
        ZonedDateTime.of(LocalDateTime.of(date, java.time.LocalTime.of(time.hour, time.minute)), zone).toInstant()

    private fun nextOneTime(date: AlarmDate, time: AlarmTime, after: Instant, zone: ZoneId): Instant? {
        val fire = runCatching { at(date.toLocalDate(), time, zone) }.getOrNull() ?: return null
        return if (fire.isAfter(after)) fire else null
    }

    private fun nextRepeating(days: Set<Weekday>, time: AlarmTime, after: Instant, zone: ZoneId): Instant? {
        val start = after.atZone(zone).toLocalDate()
        // Eight days reach every weekday, today's included once more next week.
        for (offset in 0L..7L) {
            val day = start.plusDays(offset)
            if (Weekday.of(day.dayOfWeek) !in days) continue
            val fire = at(day, time, zone)
            if (fire.isAfter(after)) return fire
        }
        return null
    }

    /** True for a one-time alarm whose moment has come and gone. */
    fun isPastOneTime(alarm: Alarm, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val r = alarm.recurrence as? AlarmRecurrence.OneTime ?: return false
        val fire = runCatching { at(r.date.toLocalDate(), alarm.wallClockTime, zone) }.getOrNull() ?: return true
        return !fire.isAfter(now)
    }
}
