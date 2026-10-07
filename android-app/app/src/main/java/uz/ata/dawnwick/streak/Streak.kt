package uz.ata.dawnwick.streak

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale
import kotlinx.serialization.Serializable
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore

/**
 * The wake streak: mornings won in a row. Days are "yyyy-MM-dd" (ISO local dates).
 *
 * A day with no alarm is a rest day and breaks nothing. Every seventh morning in a
 * row earns a cover, up to two; a missed morning the cat can cover for does not end
 * the streak. The best streak never goes down.
 */
@Serializable
data class StreakRecord(
    val currentStreak: Int = 0,
    val bestStreak: Int = 0,
    /** The most recent day a mission was completed. */
    val lastCompletion: String? = null,
    /** Completed days, kept for about thirteen months. */
    val completedDates: Set<String> = emptySet(),
    val covers: Int = 0,
    /** Days the cat covered for: scheduled, not won, still not a break. */
    val coveredDates: Set<String> = emptySet(),
) {
    fun isCompleted(day: LocalDate) = day.toString() in completedDates
    fun isCovered(day: LocalDate) = day.toString() in coveredDates

    /**
     * The streak on `today`. The stored count only changes on a win, so read alone it
     * would go on showing the old number after a missed morning. A morning counts as
     * missed once its day is over: today is still to play for.
     */
    fun liveStreak(today: LocalDate, hadAlarm: (LocalDate) -> Boolean): Int {
        val last = lastCompletion?.let(LocalDate::parse) ?: return 0
        if (currentStreak <= 0) return 0
        val settled = settled(today, hadAlarm)
        return if (missedDays(last, today, hadAlarm, settled.coveredDates).isEmpty()) currentStreak else 0
    }

    /**
     * Covers spent on the mornings missed since the last win, if there are enough
     * for all of them. If not, the streak is over and the covers are kept.
     */
    fun settled(today: LocalDate, hadAlarm: (LocalDate) -> Boolean): StreakRecord {
        val last = lastCompletion?.let(LocalDate::parse) ?: return this
        if (currentStreak <= 0) return this
        val missed = missedDays(last, today, hadAlarm, coveredDates)
        if (missed.isEmpty() || missed.size > covers) return this
        return copy(covers = covers - missed.size, coveredDates = coveredDates + missed.map { it.toString() })
    }

    /** Records a win on `day`. A second win the same day changes nothing. */
    fun recordingCompletion(day: LocalDate, hadAlarm: (LocalDate) -> Boolean): StreakRecord {
        if (isCompleted(day)) return this
        var r = settled(day, hadAlarm)
        val last = r.lastCompletion?.let(LocalDate::parse)
        val current = if (last != null && missedDays(last, day, hadAlarm, r.coveredDates).isEmpty()) r.currentStreak + 1 else 1
        val cutoff = day.minusDays(RETENTION_DAYS).toString()
        r = r.copy(
            currentStreak = current,
            bestStreak = maxOf(r.bestStreak, current),
            lastCompletion = day.toString(),
            completedDates = (r.completedDates + day.toString()).filterTo(mutableSetOf()) { it >= cutoff },
            coveredDates = r.coveredDates.filterTo(mutableSetOf()) { it >= cutoff },
            covers = if (current % COVER_EVERY == 0) minOf(MAX_COVERS, r.covers + 1) else r.covers,
        )
        return r
    }

    companion object {
        const val COVER_EVERY = 7
        const val MAX_COVERS = 2
        const val RETENTION_DAYS = 400L

        /** Days strictly between the two that had an alarm and so needed a win, less those covered. */
        fun missedDays(last: LocalDate, day: LocalDate, hadAlarm: (LocalDate) -> Boolean, covered: Set<String>): List<LocalDate> {
            val gap = ChronoUnit.DAYS.between(last, day)
            if (gap <= 1) return emptyList()
            return (1 until gap).map { last.plusDays(it) }.filter { hadAlarm(it) && it.toString() !in covered }
        }

        /**
         * The rest-day rule as the alarms stand now: a day was scheduled if an enabled
         * alarm falls on it. Days up to `since` — before the person had the app, and
         * the day they set it up, often after that morning's alarm time — were never
         * scheduled, whatever the alarms say now.
         */
        fun scheduledBy(alarms: List<Alarm>, since: LocalDate? = null): (LocalDate) -> Boolean = { day ->
            (since == null || day.isAfter(since)) && alarms.any { it.isEnabled && it.recurrence.occursOn(day) }
        }
    }
}

fun AlarmRecurrence.occursOn(day: LocalDate): Boolean = when (this) {
    is AlarmRecurrence.Daily -> true
    is AlarmRecurrence.Repeating -> days.any { it.number == day.dayOfWeek.value % 7 + 1 }
    is AlarmRecurrence.OneTime -> date.year == day.year && date.month == day.monthValue && date.day == day.dayOfMonth
}

/** What one calendar day did for the streak. */
enum class DayOutcome { WON, MISSED, REST, COVERED, TODAY, UPCOMING }

data class DayCell(val date: LocalDate, val outcome: DayOutcome)

object StreakDays {
    private fun outcome(day: LocalDate, today: LocalDate, record: StreakRecord, alarms: List<Alarm>, since: LocalDate?) = when {
        record.isCompleted(day) -> DayOutcome.WON
        record.isCovered(day) -> DayOutcome.COVERED
        day == today -> DayOutcome.TODAY
        day.isAfter(today) -> DayOutcome.UPCOMING
        StreakRecord.scheduledBy(alarms, since)(day) -> DayOutcome.MISSED
        else -> DayOutcome.REST
    }

    /** This week, from the locale's first weekday. */
    fun week(today: LocalDate, record: StreakRecord, alarms: List<Alarm>, since: LocalDate? = null, locale: Locale = Locale.getDefault()): List<DayCell> {
        val first: DayOfWeek = WeekFields.of(locale).firstDayOfWeek
        val start = today.with(TemporalAdjusters.previousOrSame(first))
        return (0L until 7).map { start.plusDays(it).let { d -> DayCell(d, outcome(d, today, record, alarms, since)) } }
    }

    /** Every day of the month containing `today`. */
    fun month(today: LocalDate, record: StreakRecord, alarms: List<Alarm>, since: LocalDate? = null): List<DayCell> =
        (1..today.lengthOfMonth()).map { today.withDayOfMonth(it).let { d -> DayCell(d, outcome(d, today, record, alarms, since)) } }
}

/** What a long streak teaches the cat. Learned by the best streak, kept for good. */
enum class CatTrick(val days: Int) {
    WAVE(3), SOMERSAULT(7), LEAP(14), SPARKLE(30), COLLAR(60), MEDAL(100);

    companion object {
        fun next(afterBest: Int): CatTrick? = entries.firstOrNull { it.days > afterBest }
    }
}

/** The one place the streak is written. */
class StreakStore(private val store: KeyValueStore, private val today: () -> LocalDate = LocalDate::now) {
    fun load(): StreakRecord = store.getString(KEY)?.let { runCatching { AppJson.decodeFromString<StreakRecord>(it) }.getOrNull() } ?: StreakRecord()

    /** The first day the streak was looked at: before it, nothing was scheduled. */
    @Synchronized
    fun since(): LocalDate = store.getString(SINCE_KEY)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        ?: today().also { store.putString(SINCE_KEY, it.toString()) }

    fun scheduled(alarms: List<Alarm>) = StreakRecord.scheduledBy(alarms, since())

    @Synchronized
    fun recordCompletion(alarms: List<Alarm>) {
        val updated = load().recordingCompletion(today(), scheduled(alarms))
        store.putString(KEY, AppJson.encodeToString(StreakRecord.serializer(), updated))
    }

    /** Spends covers due and saves, so covered days read as covered everywhere. */
    @Synchronized
    fun settle(alarms: List<Alarm>): StreakRecord {
        val current = load()
        val settled = current.settled(today(), scheduled(alarms))
        if (settled != current) store.putString(KEY, AppJson.encodeToString(StreakRecord.serializer(), settled))
        return settled
    }

    companion object {
        const val KEY = "streak.v1"
        const val SINCE_KEY = "streak.since"
    }
}
