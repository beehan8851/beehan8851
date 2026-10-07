package uz.ata.dawnwick.alarm.model

import java.time.DayOfWeek
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * One alarm, as the person set it: a wall-clock time, when it repeats, the missions
 * that turn it off, how it sounds, snooze and the wake check.
 *
 * Stored as user intent, never as an instant: "7:00 on weekdays", so a time-zone or
 * clock change moves the next ring with the clock, as the iOS app does.
 */
@Serializable
data class Alarm(
    val id: String = UUID.randomUUID().toString(),
    val label: String = "",
    val wallClockTime: AlarmTime = AlarmTime(7, 0),
    val recurrence: AlarmRecurrence = AlarmRecurrence.Daily,
    /** One to three missions, done in order at wake time. */
    val missions: List<MissionConfig> = listOf(MissionConfig.defaultMath),
    val sound: AlarmSound = AlarmSound.DEFAULT,
    /** Playback volume, 0.3–1.0. */
    val volume: Float = 1f,
    val gradualWake: GradualWake = GradualWake.OFF,
    val snooze: SnoozeConfig = SnoozeConfig.DEFAULT,
    val wakeCheck: WakeCheckConfig = WakeCheckConfig.OFF,
    val isEnabled: Boolean = true,
) {
    companion object {
        /** The transient alarm "Test alarm (30 s)" rings. Never stored with the others. */
        fun testAlarm(id: String, sound: AlarmSound, now: java.time.LocalDateTime = java.time.LocalDateTime.now()) = Alarm(
            id = id,
            label = "",
            wallClockTime = AlarmTime(now.hour, now.minute),
            recurrence = AlarmRecurrence.OneTime(AlarmDate.of(now.toLocalDate())),
            missions = listOf(MissionConfig.Math(MathDifficulty.EASY, 1)),
            sound = sound,
            snooze = SnoozeConfig.OFF,
            wakeCheck = WakeCheckConfig.OFF,
        )
    }
}

/** Wall-clock hour and minute, independent of calendar and time zone. */
@Serializable
data class AlarmTime(val hour: Int, val minute: Int) {
    val minutesOfDay: Int get() = hour * 60 + minute
}

/** Wall-clock calendar date as user intent, not a UTC instant. */
@Serializable
data class AlarmDate(val year: Int, val month: Int, val day: Int) {
    fun toLocalDate(): LocalDate = LocalDate.of(year, month, day)

    companion object {
        fun of(date: LocalDate) = AlarmDate(date.year, date.monthValue, date.dayOfMonth)
    }
}

/** When an alarm rings relative to its wall-clock time. */
@Serializable
sealed interface AlarmRecurrence {
    /** Once, on the given date. */
    @Serializable @SerialName("oneTime")
    data class OneTime(val date: AlarmDate) : AlarmRecurrence

    /** Every week on these days. */
    @Serializable @SerialName("repeating")
    data class Repeating(val days: Set<Weekday>) : AlarmRecurrence

    @Serializable @SerialName("daily")
    data object Daily : AlarmRecurrence
}

/** Sunday first, numbered as the iOS app numbers them (Sunday = 1). */
@Serializable
enum class Weekday(val number: Int) {
    SUNDAY(1), MONDAY(2), TUESDAY(3), WEDNESDAY(4), THURSDAY(5), FRIDAY(6), SATURDAY(7);

    val dayOfWeek: DayOfWeek
        get() = when (this) {
            SUNDAY -> DayOfWeek.SUNDAY
            MONDAY -> DayOfWeek.MONDAY
            TUESDAY -> DayOfWeek.TUESDAY
            WEDNESDAY -> DayOfWeek.WEDNESDAY
            THURSDAY -> DayOfWeek.THURSDAY
            FRIDAY -> DayOfWeek.FRIDAY
            SATURDAY -> DayOfWeek.SATURDAY
        }

    companion object {
        /** Monday first, as the day circles show them. */
        val displayOrder = listOf(MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY)
        val workdays = setOf(MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY)
        val weekend = setOf(SATURDAY, SUNDAY)
        val all = entries.toSet()

        fun of(day: DayOfWeek): Weekday = entries.first { it.dayOfWeek == day }
    }
}

@Serializable
enum class AlarmSound { DEFAULT, GENTLE, RISE, PULSE, CHIME, DIGITAL, MEOW }

@Serializable
enum class GradualWake(val seconds: Int) { OFF(0), SEC_15(15), SEC_30(30), SEC_60(60), MIN_3(180) }

@Serializable
data class SnoozeConfig(
    /** Minutes; 0 means snooze is off. */
    val durationMinutes: Int,
    /** Snoozes per ring; -1 is unlimited. */
    val maxCount: Int,
) {
    val isEnabled: Boolean get() = durationMinutes > 0
    val isUnlimited: Boolean get() = maxCount == -1

    companion object {
        val DEFAULT = SnoozeConfig(5, 2)
        val OFF = SnoozeConfig(0, 0)
        val durationOptions = listOf(0, 3, 5, 10)
        val maxCountOptions = listOf(1, 2, 3, -1)
    }
}

@Serializable
data class WakeCheckConfig(
    /** Minutes after the mission before "Still awake?"; 0 is off. */
    val durationMinutes: Int,
) {
    val isEnabled: Boolean get() = durationMinutes > 0

    companion object {
        val OFF = WakeCheckConfig(0)
        val durationOptions = listOf(0, 3, 5, 10)
    }
}
