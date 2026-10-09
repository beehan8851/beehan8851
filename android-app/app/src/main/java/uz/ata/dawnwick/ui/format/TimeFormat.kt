package uz.ata.dawnwick.ui.format

import android.content.Context
import android.text.format.DateFormat
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.AlarmTime
import uz.ata.dawnwick.alarm.model.Weekday

object TimeFormat {
    fun is24h(context: Context) = DateFormat.is24HourFormat(context)

    /** "7:05" or "7:05 AM", as the phone's own clock writes it. */
    fun time(context: Context, t: AlarmTime): String {
        val pattern = if (is24h(context)) "H:mm" else "h:mm a"
        return LocalTime.of(t.hour, t.minute).format(DateTimeFormatter.ofPattern(pattern, Locale.getDefault()))
    }

    /** The big numerals and, on a 12-hour clock, the AM/PM beside them. */
    fun timeParts(context: Context, t: AlarmTime): Pair<String, String?> {
        if (is24h(context)) return LocalTime.of(t.hour, t.minute).format(DateTimeFormatter.ofPattern("H:mm")) to null
        val time = LocalTime.of(t.hour, t.minute)
        return time.format(DateTimeFormatter.ofPattern("h:mm")) to time.format(DateTimeFormatter.ofPattern("a", Locale.getDefault()))
    }

    fun weekdayShort(context: Context, day: Weekday): String =
        context.resources.getStringArray(R.array.weekday_short)[day.number - 1]

    /** The weekday in a round button: as short as it can be and still not mistaken for another. */
    fun weekdayLetter(context: Context, day: Weekday): String =
        context.resources.getStringArray(R.array.weekday_letter)[day.number - 1]

    fun weekdayLong(context: Context, day: Weekday): String =
        context.resources.getStringArray(R.array.weekday_long)[day.number - 1]

    /** "Weekdays", "Every day", "Mon · Wed · Fri", "Once · 8 Oct". */
    fun recurrence(context: Context, r: AlarmRecurrence): String = when (r) {
        AlarmRecurrence.Daily -> context.getString(R.string.recurrence_daily)
        is AlarmRecurrence.OneTime -> context.getString(
            R.string.recurrence_once, r.date.toLocalDate().format(DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())))
        is AlarmRecurrence.Repeating -> when {
            r.days.isEmpty() -> context.getString(R.string.recurrence_no_days)
            r.days == Weekday.all -> context.getString(R.string.recurrence_daily)
            r.days == Weekday.workdays -> context.getString(R.string.recurrence_weekdays)
            r.days == Weekday.weekend -> context.getString(R.string.recurrence_weekends)
            else -> Weekday.displayOrder.filter { it in r.days }.joinToString(" · ") { weekdayShort(context, it) }
        }
    }

    /** "in 7 h 20 min", for how long until an alarm rings. */
    fun until(context: Context, millis: Long): String {
        val minutes = maxOf(0L, millis / 60_000)
        return when {
            millis < 60_000 -> context.getString(R.string.rings_in_under_minute)
            minutes < 60 -> context.getString(R.string.rings_in_minutes, minutes.toInt())
            minutes % 60 == 0L -> context.getString(R.string.rings_in_hours, (minutes / 60).toInt())
            else -> context.getString(R.string.rings_in_hours_minutes, (minutes / 60).toInt(), (minutes % 60).toInt())
        }
    }

    /** A moment as a clock time, "9:30 AM" or "09:30" as the phone is set. */
    fun clock(context: Context, epochMillis: Long): String {
        val t = java.time.Instant.ofEpochMilli(epochMillis).atZone(java.time.ZoneId.systemDefault()).toLocalTime()
        val pattern = if (is24h(context)) "HH:mm" else "h:mm a"
        return t.format(java.time.format.DateTimeFormatter.ofPattern(pattern, java.util.Locale.getDefault()))
    }
}
