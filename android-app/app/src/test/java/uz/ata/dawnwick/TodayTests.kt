package uz.ata.dawnwick

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.ata.dawnwick.alarm.model.AlarmDate
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.Weekday
import uz.ata.dawnwick.streak.CatTrick
import uz.ata.dawnwick.streak.DayOutcome
import uz.ata.dawnwick.streak.StreakDays
import uz.ata.dawnwick.streak.StreakRecord
import uz.ata.dawnwick.streak.occursOn
import uz.ata.dawnwick.today.BriefCache
import uz.ata.dawnwick.today.CalendarEvent
import uz.ata.dawnwick.today.OpenMeteo
import uz.ata.dawnwick.today.WeatherConditions

class StreakTests {
    private val every: (LocalDate) -> Boolean = { true }
    private val weekdaysOnly: (LocalDate) -> Boolean = { it.dayOfWeek != DayOfWeek.SATURDAY && it.dayOfWeek != DayOfWeek.SUNDAY }
    private val mon = LocalDate.of(2026, 10, 5) // a Monday

    private fun wins(vararg days: LocalDate, hadAlarm: (LocalDate) -> Boolean = every) =
        days.fold(StreakRecord()) { r, d -> r.recordingCompletion(d, hadAlarm) }

    @Test fun consecutiveWinsCount() {
        val r = wins(mon, mon.plusDays(1), mon.plusDays(2))
        assertEquals(3, r.currentStreak)
        assertEquals(3, r.bestStreak)
        assertEquals(3, r.liveStreak(mon.plusDays(3), every))
    }

    @Test fun sameDayTwiceCountsOnce() = assertEquals(1, wins(mon, mon).currentStreak)

    @Test fun missedDayResetsButBestStays() {
        val r = wins(mon, mon.plusDays(1), mon.plusDays(3))
        assertEquals(1, r.currentStreak)
        assertEquals(2, r.bestStreak)
    }

    @Test fun liveStreakDropsOnceAMissedDayIsOver() {
        val r = wins(mon, mon.plusDays(1))
        assertEquals(2, r.liveStreak(mon.plusDays(2), every)) // today still to play for
        assertEquals(0, r.liveStreak(mon.plusDays(3), every))
    }

    @Test fun restDaysDoNotBreakIt() {
        val fri = mon.plusDays(4)
        val nextMon = mon.plusDays(7)
        val r = wins(fri, nextMon, hadAlarm = weekdaysOnly)
        assertEquals(2, r.currentStreak)
    }

    @Test fun seventhMorningEarnsACoverThatSavesAMiss() {
        val week = (0L until 7).map { mon.plusDays(it) }.toTypedArray()
        val r = wins(*week)
        assertEquals(1, r.covers)
        // Day 8 missed, day 9 won: the cover is spent, the streak goes on.
        val after = r.recordingCompletion(mon.plusDays(8), every)
        assertEquals(8, after.currentStreak)
        assertEquals(0, after.covers)
        assertTrue(after.isCovered(mon.plusDays(7)))
    }

    @Test fun coversAreKeptWhenNotEnough() {
        val r = wins(*(0L until 7).map { mon.plusDays(it) }.toTypedArray())
        val after = r.recordingCompletion(mon.plusDays(9), every) // two missed, one cover
        assertEquals(1, after.currentStreak)
        assertEquals(1, after.covers)
    }

    @Test fun coversTopOutAtTwo() {
        val r = wins(*(0L until 21).map { mon.plusDays(it) }.toTypedArray())
        assertEquals(StreakRecord.MAX_COVERS, r.covers)
    }

    @Test fun recurrenceOccursOnTheRightDays() {
        assertTrue(AlarmRecurrence.Daily.occursOn(mon))
        assertTrue(AlarmRecurrence.Repeating(setOf(Weekday.entries.first { it.number == 2 })).occursOn(mon)) // Monday
        assertTrue(!AlarmRecurrence.Repeating(setOf(Weekday.entries.first { it.number == 1 })).occursOn(mon)) // Sunday
        assertTrue(AlarmRecurrence.OneTime(AlarmDate(2026, 10, 5)).occursOn(mon))
    }

    @Test fun weekStartsOnTheLocalesFirstDay() {
        val week = StreakDays.week(mon.plusDays(2), StreakRecord(), emptyList(), locale = Locale.UK)
        assertEquals(mon, week.first().date)
        assertEquals(DayOutcome.TODAY, week[2].outcome)
        assertEquals(DayOutcome.REST, week[0].outcome)
        assertEquals(DayOutcome.UPCOMING, week[6].outcome)
    }

    @Test fun daysBeforeTheAppWereNotMissed() {
        val daily = listOf(uz.ata.dawnwick.alarm.model.Alarm.testAlarm("a", uz.ata.dawnwick.alarm.model.AlarmSound.entries.first()).copy(recurrence = AlarmRecurrence.Daily))
        val week = StreakDays.week(mon.plusDays(3), StreakRecord(), daily, since = mon.plusDays(1), locale = Locale.UK)
        assertEquals(DayOutcome.REST, week[0].outcome)   // before the app
        assertEquals(DayOutcome.REST, week[1].outcome)   // the day it was set up
        assertEquals(DayOutcome.MISSED, week[2].outcome)
    }

    @Test fun nextTrickFollowsTheBest() {
        assertEquals(CatTrick.WAVE, CatTrick.next(0))
        assertEquals(CatTrick.LEAP, CatTrick.next(7))
        assertNull(CatTrick.next(100))
    }
}

class OpenMeteoTests {
    private val json = """
        {"current":{"temperature_2m":14.6,"weather_code":2,"is_day":1,"relative_humidity_2m":48,"wind_speed_10m":9.4},
         "hourly":{"time":[1000,4600,8200,11800],"temperature_2m":[10.0,11.0,null,13.0],"weather_code":[1,2,3],
                   "precipitation_probability":[0,20,30,40],"is_day":[0,1,1,1]},
         "daily":{"temperature_2m_max":[19.2,20.0],"temperature_2m_min":[7.1,8.0],"precipitation_probability_max":[35,10]},
         "extra":"ignored"}
    """.trimIndent()

    @Test fun parsesCurrentDailyAndHourly() {
        val w = OpenMeteo.parse(json, nowMillis = 3_000_000, placeName = "Tashkent")
        assertEquals(14.6, w.temperature, 0.0)
        assertEquals(19.2, w.high, 0.0)
        assertEquals(7.1, w.low, 0.0)
        assertEquals(0.35, w.precipitationChance, 1e-9)
        assertEquals(0.48, w.humidity!!, 1e-9)
        assertEquals("Tashkent", w.placeName)
        // Past hour dropped, null temperature skipped, missing code (short array) skipped.
        assertEquals(listOf(4600L), w.hourly.map { it.epochSeconds })
        assertEquals(0.2, w.hourly.first().precipitationChance, 1e-9)
    }

    @Test fun missingDailyFallsBackToNow() {
        val w = OpenMeteo.parse("""{"current":{"temperature_2m":3.0,"weather_code":71}}""", 0, null)
        assertEquals(3.0, w.high, 0.0)
        assertTrue(w.hourly.isEmpty())
    }
}

class BriefCacheTests {
    private val zone = ZoneId.of("Asia/Tashkent")
    private fun weather(at: Long) = WeatherConditions(10.0, 12.0, 5.0, 0, true, 0.0, capturedAt = at)

    @Test fun weatherKeepsForThreeHoursOnly() {
        val now = 1_800_000_000_000
        assertNotNull(BriefCache(weather(now - 2 * 3600_000)).usable(now, zone).weather)
        assertNull(BriefCache(weather(now - 4 * 3600_000)).usable(now, zone).weather)
        // From the future: a clock that was changed.
        assertNull(BriefCache(weather(now + 4 * 3600_000)).usable(now, zone).weather)
    }

    @Test fun eventThatHasBegunIsDropped() {
        val now = System.currentTimeMillis()
        assertNull(BriefCache(event = CalendarEvent("Standup", now - 60_000)).usable(now, ZoneId.systemDefault()).event)
    }
}
