package uz.ata.dawnwick

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.MemoryStore
import uz.ata.dawnwick.sleep.BedtimeReminder
import uz.ata.dawnwick.sleep.BreathPacer
import uz.ata.dawnwick.sleep.SleepEntry
import uz.ata.dawnwick.sleep.SleepHistory
import uz.ata.dawnwick.sleep.SleepRepository
import uz.ata.dawnwick.sleep.SleepSession
import uz.ata.dawnwick.sleep.SleepSound
import uz.ata.dawnwick.sleep.WindDownNote
import uz.ata.dawnwick.today.MorningBriefRepository

class SleepTests {
    private val zone = ZoneId.of("Asia/Tashkent")
    private fun at(y: Int, mo: Int, d: Int, h: Int, mi: Int = 0) = LocalDateTime.of(y, mo, d, h, mi).atZone(zone).toInstant()

    @Test fun pacerBreathesInForFourOutForSix() {
        val p = BreathPacer()
        assertEquals(BreathPacer.Phase.IN, p.moment(1.0).phase)
        assertEquals(BreathPacer.Phase.OUT, p.moment(5.0).phase)
        assertEquals(-1.0, p.moment(0.0).breath, 1e-9)
        assertEquals(1.0, p.moment(4.0).breath, 1e-9)
        assertEquals(2, p.moment(10.5).index)
        assertEquals(300.0, p.wholeBreaths(5), 1e-9)
    }

    @Test fun noteGoesToTheMorningOfTheNextAlarm() {
        val now = at(2026, 10, 6, 22)
        assertEquals(LocalDate.of(2026, 10, 7), WindDownNote.morning(now, at(2026, 10, 7, 7), zone))
        assertEquals(LocalDate.of(2026, 10, 7), WindDownNote.morning(now, null, zone))
        assertEquals(LocalDate.of(2026, 10, 7), WindDownNote.morning(at(2026, 10, 7, 1), null, zone))
    }

    @Test fun noteIsAddedUnderTheFocus() {
        val store = MemoryStore()
        val day = LocalDate.of(2026, 10, 7)
        store.putString(MorningBriefRepository.focusKey(day), "Report")
        assertTrue(WindDownNote.park(" Call mum ", store, null, at(2026, 10, 6, 22), zone))
        assertEquals("Report\nCall mum", store.getString(MorningBriefRepository.focusKey(day)))
        assertFalse(WindDownNote.park("   ", store, null, at(2026, 10, 6, 22), zone))
    }

    @Test fun historyKeepsTheLongerFigurePerNight() {
        val session = SleepSession(startMillis = at(2026, 10, 6, 23).toEpochMilli(), endMillis = at(2026, 10, 7, 7).toEpochMilli())
        val shorter = SleepEntry(LocalDate.of(2026, 10, 7), 6 * 3600_000L)
        val merged = SleepHistory.merge(listOf(session), listOf(shorter), zone)
        assertEquals(1, merged.size)
        assertEquals(8 * 3600_000L, merged[0].durationMillis)
        assertTrue(merged[0].tracked)
        val longer = SleepEntry(LocalDate.of(2026, 10, 7), 9 * 3600_000L)
        assertFalse(SleepHistory.merge(listOf(session), listOf(longer), zone)[0].tracked)
    }

    @Test fun repositoryKeepsThirtyNewestFirst() {
        val repo = SleepRepository(MemoryStore())
        repeat(35) { repo.saveCompleted(SleepSession(id = "s$it", startMillis = it.toLong(), endMillis = it + 1L)) }
        val all = repo.loadCompleted()
        assertEquals(30, all.size)
        assertEquals("s34", all.first().id)
        repo.saveActive(SleepSession(id = "a", startMillis = 1))
        assertEquals("a", repo.loadActive()?.id)
        repo.clearActive()
        assertNull(repo.loadActive())
    }

    @Test fun removedSoundsReadAsNone() {
        val json = """{"id":"x","startMillis":1,"soundUsed":"rain"}"""
        assertEquals(SleepSound.NONE, AppJson.decodeFromString(SleepSession.serializer(), json).soundUsed)
    }

    @Test fun reminderIsClamped() = assertEquals(BedtimeReminder(true, 23, 59), BedtimeReminder(true, 47, 99).clamped())

}
