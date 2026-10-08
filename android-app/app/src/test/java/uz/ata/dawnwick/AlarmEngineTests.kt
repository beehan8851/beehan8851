package uz.ata.dawnwick

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.ata.dawnwick.alarm.AlarmEngine
import uz.ata.dawnwick.alarm.AlarmRepository
import uz.ata.dawnwick.alarm.AlarmService
import uz.ata.dawnwick.alarm.NextAlarmCalculator
import uz.ata.dawnwick.alarm.ReArmRegistry
import uz.ata.dawnwick.alarm.SaveError
import uz.ata.dawnwick.alarm.SaveResult
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.alarm.model.AlarmDate
import uz.ata.dawnwick.alarm.model.AlarmRecurrence
import uz.ata.dawnwick.alarm.model.AlarmTime
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.Weekday
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.MemoryStore

/** The Swift suites NextAlarmCalculatorTests, AlarmManagerTests and AlarmModelTests, ported. */
class NextAlarmCalculatorTest {
    private val utc = ZoneOffset.UTC
    // Jan 7 2025 06:00 UTC is a Tuesday.
    private fun ref(day: Int = 7, hour: Int = 6) = LocalDateTime.of(2025, 1, day, hour, 0).toInstant(utc)
    private fun at(day: Int, hour: Int) = LocalDateTime.of(2025, 1, day, hour, 0).toInstant(utc)
    private fun next(alarm: Alarm) = NextAlarmCalculator.nextFireTime(alarm, ref(), utc)

    @Test fun disabledAlarmReturnsNull() =
        assertNull(next(Alarm(wallClockTime = AlarmTime(7, 0), isEnabled = false)))

    @Test fun oneTimeFuture() = assertEquals(at(8, 7),
        next(Alarm(wallClockTime = AlarmTime(7, 0), recurrence = AlarmRecurrence.OneTime(AlarmDate(2025, 1, 8)))))

    @Test fun oneTimePast() = assertNull(
        next(Alarm(wallClockTime = AlarmTime(7, 0), recurrence = AlarmRecurrence.OneTime(AlarmDate(2025, 1, 6)))))

    @Test fun repeatingLaterToday() = assertEquals(at(7, 7),
        next(Alarm(wallClockTime = AlarmTime(7, 0), recurrence = AlarmRecurrence.Repeating(setOf(Weekday.TUESDAY)))))

    @Test fun repeatingMissedTodayFiresNextWeek() = assertEquals(at(14, 5),
        next(Alarm(wallClockTime = AlarmTime(5, 0), recurrence = AlarmRecurrence.Repeating(setOf(Weekday.TUESDAY)))))

    @Test fun repeatingNextDay() = assertEquals(at(8, 8),
        next(Alarm(wallClockTime = AlarmTime(8, 0), recurrence = AlarmRecurrence.Repeating(setOf(Weekday.WEDNESDAY)))))

    @Test fun repeatingEmptyDays() = assertNull(
        next(Alarm(wallClockTime = AlarmTime(7, 0), recurrence = AlarmRecurrence.Repeating(emptySet()))))

    @Test fun dailyLaterToday() = assertEquals(at(7, 9), next(Alarm(wallClockTime = AlarmTime(9, 0))))

    @Test fun dailyTomorrowWhenPast() = assertEquals(at(8, 5), next(Alarm(wallClockTime = AlarmTime(5, 0))))

    @Test fun keepsTheWallClockAcrossDaylightSaving() {
        // Berlin springs forward on 30 March 2025: 07:00 is still 07:00 on the clock.
        val berlin = ZoneId.of("Europe/Berlin")
        val before = LocalDateTime.of(2025, 3, 29, 8, 0).atZone(berlin).toInstant()
        val fire = NextAlarmCalculator.nextFireTime(Alarm(wallClockTime = AlarmTime(7, 0)), before, berlin)!!
        assertEquals(LocalDateTime.of(2025, 3, 30, 7, 0), LocalDateTime.ofInstant(fire, berlin))
    }
}

class FakeEngine : AlarmEngine {
    val scheduled = mutableSetOf<String>()
    var fail = false
    override fun schedule(alarm: Alarm) { if (fail) error("refused"); scheduled += alarm.id }
    override fun scheduleReArm(alarm: Alarm, reArmId: String, delayMillis: Long) { if (fail) error("refused"); scheduled += reArmId }
    override fun cancel(id: String) { scheduled -= id }
    override fun pendingIds() = scheduled.toSet()
}

class AlarmServiceTest {
    private val now = LocalDateTime.of(2025, 1, 7, 6, 0).toInstant(ZoneOffset.UTC)
    private val store = MemoryStore()
    private val engine = FakeEngine()
    private val repo = AlarmRepository(store)
    private fun service(premium: Boolean = true) =
        AlarmService(repo, engine, ReArmRegistry(store), { premium }, { now }, { ZoneOffset.UTC })

    @Test fun invalidHour() = assertTrue(service().save(Alarm(wallClockTime = AlarmTime(24, 0))).isValidationFailure())
    @Test fun invalidMinute() = assertTrue(service().save(Alarm(wallClockTime = AlarmTime(7, 60))).isValidationFailure())
    @Test fun emptyRepeatingDays() =
        assertTrue(service().save(Alarm(recurrence = AlarmRecurrence.Repeating(emptySet()))).isValidationFailure())
    @Test fun pastOneTime() =
        assertTrue(service().save(Alarm(recurrence = AlarmRecurrence.OneTime(AlarmDate(2025, 1, 6)))).isValidationFailure())
    @Test fun unconfiguredMission() =
        assertTrue(service().save(Alarm(missions = listOf(MissionConfig.Typing("hi")))).isValidationFailure())
    @Test fun tooQuiet() = assertTrue(service().save(Alarm(volume = 0.1f)).isValidationFailure())

    @Test fun engineFailureAfterPersistIsPartialSuccess() {
        engine.fail = true
        val alarm = Alarm()
        assertTrue(service().save(alarm) is SaveResult.PartialSuccess)
        assertEquals(alarm, repo.alarm(alarm.id))
    }

    @Test fun validSaveIsScheduledAndFetchable() {
        val alarm = Alarm()
        assertTrue(service().save(alarm) is SaveResult.Success)
        assertEquals(listOf(alarm), service().fetchAll())
        assertTrue(alarm.id in engine.scheduled)
    }

    @Test fun deleteRemovesAndCancels() {
        val alarm = Alarm()
        val s = service()
        s.save(alarm)
        s.snooze(alarm, 60_000)
        s.delete(alarm.id)
        assertTrue(s.fetchAll().isEmpty())
        assertTrue(engine.scheduled.isEmpty())
        assertTrue(s.registry.allReArmIds.isEmpty())
    }

    @Test fun reconcileSchedulesMissingAndCancelsOrphans() {
        val alarm = Alarm()
        repo.save(alarm)
        engine.scheduled += "ghost"
        service().reconcile()
        assertEquals(setOf(alarm.id), engine.scheduled)
    }

    @Test fun reconcileDisablesAPastOneTimeAlarm() {
        val alarm = Alarm(recurrence = AlarmRecurrence.OneTime(AlarmDate(2025, 1, 6)))
        repo.save(alarm)
        service().reconcile()
        assertFalse(repo.alarm(alarm.id)!!.isEnabled)
        assertTrue(engine.scheduled.isEmpty())
    }

    @Test fun reconcileKeepsRegisteredReArmsOfEnabledAlarms() {
        val alarm = Alarm()
        val s = service()
        s.save(alarm)
        val snooze = s.snooze(alarm, 60_000)!!
        s.reconcile()
        assertTrue(snooze in engine.scheduled)
        // Switched off: its snooze goes too.
        s.save(alarm.copy(isEnabled = false))
        s.reconcile()
        assertFalse(snooze in engine.scheduled)
    }

    @Test fun editingCancelsTheOldSnooze() {
        val alarm = Alarm()
        val s = service()
        s.save(alarm)
        val snooze = s.snooze(alarm, 60_000)!!
        s.save(alarm.copy(label = "Work"))
        assertFalse(snooze in engine.scheduled)
    }

    @Test fun freeTierAllowsTwoEnabledAlarms() {
        val s = service(premium = false)
        assertTrue(s.save(Alarm()) is SaveResult.Success)
        assertTrue(s.save(Alarm()) is SaveResult.Success)
        assertEquals(SaveResult.Failure(SaveError.FreeAlarmLimit), s.save(Alarm()))
        // An edit of one already on is never blocked.
        val first = s.fetchAll().first()
        assertTrue(s.save(first.copy(label = "Edited")) is SaveResult.Success)
    }

    @Test fun freeTierRefusesANewPremiumMission() {
        val s = service(premium = false)
        assertEquals(SaveResult.Failure(SaveError.PremiumMission), s.save(Alarm(missions = listOf(MissionConfig.Steps(20)))))
        assertTrue(s.save(Alarm(missions = listOf(MissionConfig.Shake(10)))) is SaveResult.Success)
    }

    @Test fun lapsedSubscriptionKeepsItsPremiumMissions() {
        val alarm = Alarm(missions = listOf(MissionConfig.Steps(20)))
        assertTrue(service(premium = true).save(alarm) is SaveResult.Success)
        // Premium ends: the alarm can still be edited without losing the mission it had.
        assertTrue(service(premium = false).save(alarm.copy(label = "Run")) is SaveResult.Success)
    }

    @Test fun onlyMathAndShakeAreFree() {
        val free = uz.ata.dawnwick.alarm.model.MissionKind.entries.filter { !it.isPremium }
        assertEquals(setOf(uz.ata.dawnwick.alarm.model.MissionKind.MATH, uz.ata.dawnwick.alarm.model.MissionKind.SHAKE), free.toSet())
    }

    @Test fun completingAOneTimeAlarmSwitchesItOff() {
        val alarm = Alarm(recurrence = AlarmRecurrence.OneTime(AlarmDate(2025, 1, 8)))
        val s = service()
        s.save(alarm)
        s.completeOccurrence(alarm)
        assertFalse(repo.alarm(alarm.id)!!.isEnabled)
    }

    private fun SaveResult.isValidationFailure() = this is SaveResult.Failure && error is SaveError.Validation
}

class AlarmModelTest {
    @Test fun roundTripsThroughJson() {
        val alarm = Alarm(
            label = "Run",
            wallClockTime = AlarmTime(6, 30),
            recurrence = AlarmRecurrence.Repeating(setOf(Weekday.MONDAY, Weekday.FRIDAY)),
            missions = listOf(MissionConfig.defaultMath, MissionConfig.Shake(15), MissionConfig.Typing("good morning")),
        )
        assertEquals(alarm, AppJson.decodeFromString(Alarm.serializer(), AppJson.encodeToString(Alarm.serializer(), alarm)))
    }

    @Test fun oneCorruptAlarmDoesNotTakeTheListDown() {
        val store = MemoryStore()
        val good = Alarm()
        AlarmRepository(store).save(good)
        val raw = store.getString("alarms.v2")!!
        store.putString("alarms.v2", raw.replace("\"alarms\":[", "\"alarms\":[{\"id\":42},"))
        assertEquals(listOf(good), AlarmRepository(store).fetchAll())
    }

    @Test fun registryFindsOrphans() {
        val entries = mapOf(
            "a" to ReArmRegistry.Entry("alarm1", 0, ReArmRegistry.Kind.SNOOZE),
            "b" to ReArmRegistry.Entry("alarm2", 0, ReArmRegistry.Kind.RE_ARM),
            "t" to ReArmRegistry.Entry("test", Instant.now().toEpochMilli(), ReArmRegistry.Kind.TEST),
        )
        assertEquals(listOf("b"), ReArmRegistry.orphanedReArmIds(entries, setOf("alarm1")))
    }
}
