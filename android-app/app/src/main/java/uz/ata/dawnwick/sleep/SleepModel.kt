package uz.ata.dawnwick.sleep

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToLong
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore
import uz.ata.dawnwick.today.MorningBriefRepository

/**
 * The sounds that can play while falling asleep. White and brown noise are
 * mathematical definitions, so a generated file is the real thing; rain would be a
 * recording, and a synthesised one sounds like one — so there is none.
 */
@Serializable(with = SleepSoundSerializer::class)
enum class SleepSound(val raw: String) {
    NONE("none"), WHITE_NOISE("white_noise"), BROWN_NOISE("brown_noise");

    companion object {
        /** Unknown values (sounds since removed) read as none rather than losing the night. */
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: NONE
    }
}

object SleepSoundSerializer : KSerializer<SleepSound> {
    override val descriptor = PrimitiveSerialDescriptor("SleepSound", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: SleepSound) = encoder.encodeString(value.raw)
    override fun deserialize(decoder: Decoder) = SleepSound.of(decoder.decodeString())
}

@Serializable
data class NoiseEvent(val timestampMillis: Long, val peakDecibels: Float)

@Serializable
data class SleepSession(
    val id: String = UUID.randomUUID().toString(),
    val startMillis: Long,
    val endMillis: Long? = null,
    val noiseEvents: List<NoiseEvent> = emptyList(),
    val soundUsed: SleepSound = SleepSound.NONE,
) {
    val durationMillis: Long? get() = endMillis?.let { it - startMillis }
    val isActive get() = endMillis == null
}

/** One night from Health Connect: when it ended, and how long was asleep. */
data class SleepEntry(val date: LocalDate, val durationMillis: Long)

/**
 * The active session (so a killed app can pick it up again) and the last 30 that
 * finished, newest first.
 */
class SleepRepository(private val store: KeyValueStore) {
    fun saveActive(session: SleepSession) = store.putString(ACTIVE, AppJson.encodeToString(SleepSession.serializer(), session))
    fun loadActive(): SleepSession? = store.getString(ACTIVE)?.let { runCatching { AppJson.decodeFromString(SleepSession.serializer(), it) }.getOrNull() }
    fun clearActive() = store.remove(ACTIVE)

    fun saveCompleted(session: SleepSession) {
        val list = loadCompleted().filterNot { it.id == session.id }.toMutableList()
        list.add(0, session)
        store.putString(COMPLETED, AppJson.encodeToString(kotlinx.serialization.builtins.ListSerializer(SleepSession.serializer()), list.take(30)))
    }

    fun loadCompleted(): List<SleepSession> = store.getString(COMPLETED)?.let {
        runCatching { AppJson.decodeFromString(kotlinx.serialization.builtins.ListSerializer(SleepSession.serializer()), it) }.getOrNull()
    } ?: emptyList()

    companion object {
        const val ACTIVE = "sleep.active.v1"
        const val COMPLETED = "sleep.completed.v1"
    }
}

/**
 * The rhythm of a wind-down: in for four, out for six — six breaths a minute, the
 * out-breath longer, the pattern that slows the heart.
 */
data class BreathPacer(val inhale: Double = 4.0, val exhale: Double = 6.0) {
    val cycle get() = inhale + exhale

    enum class Phase { IN, OUT }

    /** `breath` is -1 (all out) to 1 (all in), eased at both ends; `index` counts phases. */
    data class Moment(val phase: Phase, val progress: Double, val breath: Double, val index: Int)

    fun moment(elapsed: Double): Moment {
        val t = max(elapsed, 0.0)
        val cycles = (t / cycle).toInt()
        val within = t - cycles * cycle
        return if (within < inhale) {
            val p = within / inhale
            Moment(Phase.IN, p, -cos(p * PI), cycles * 2)
        } else {
            val p = (within - inhale) / exhale
            Moment(Phase.OUT, p, cos(p * PI), cycles * 2 + 1)
        }
    }

    /** A length rounded to whole breaths, so a session never ends half-way through one. */
    fun wholeBreaths(minutes: Int): Double = max(1.0, (minutes * 60 / cycle).roundToLong().toDouble()) * cycle
}

/**
 * What was on someone's mind at bedtime, left for the morning: written into that
 * morning's Focus on Today, so the thought has somewhere to be that is not their head.
 */
object WindDownNote {
    /** The day the next alarm rings when it is within a day; otherwise tomorrow — or today, before five. */
    fun morning(now: Instant, nextAlarm: Instant?, zone: ZoneId = ZoneId.systemDefault()): LocalDate {
        if (nextAlarm != null && nextAlarm.isAfter(now) && nextAlarm.toEpochMilli() - now.toEpochMilli() < 24 * 3600_000L) {
            return nextAlarm.atZone(zone).toLocalDate()
        }
        val local = now.atZone(zone)
        return if (local.hour < 5) local.toLocalDate() else local.toLocalDate().plusDays(1)
    }

    /** Adds the note under anything already there. False when there was nothing to save. */
    fun park(text: String, store: KeyValueStore, nextAlarm: Instant?, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean {
        val note = text.trim()
        if (note.isEmpty()) return false
        val key = MorningBriefRepository.focusKey(morning(now, nextAlarm, zone))
        val existing = store.getString(key)?.trim().orEmpty()
        store.putString(key, if (existing.isEmpty()) note else "$existing\n$note")
        return true
    }
}

/** The nightly wind-down reminder, as stored. Clamped, so a bad store cannot ask for hour 47. */
@Serializable
data class BedtimeReminder(val isEnabled: Boolean = false, val hour: Int = 22, val minute: Int = 30) {
    fun clamped() = copy(hour = hour.coerceIn(0, 23), minute = minute.coerceIn(0, 59))
}

/** One night in the history, from whichever source recorded it. */
data class DaySleepSummary(val date: LocalDate, val durationMillis: Long?, val tracked: Boolean)

object SleepHistory {
    /**
     * Both sources by the day the night ended. For a given night the longer figure
     * wins: a phone on a night stand under-reports against a watch, and the other way
     * round, so the longer one is the less wrong.
     */
    fun merge(sessions: List<SleepSession>, health: List<SleepEntry>, zone: ZoneId = ZoneId.systemDefault()): List<DaySleepSummary> {
        val byDay = mutableMapOf<LocalDate, DaySleepSummary>()
        for (e in health) byDay[e.date] = DaySleepSummary(e.date, e.durationMillis, tracked = false)
        for (s in sessions) {
            val d = s.durationMillis ?: continue
            val end = s.endMillis ?: continue
            val day = Instant.ofEpochMilli(end).atZone(zone).toLocalDate()
            val existing = byDay[day]?.durationMillis
            if (existing != null && existing >= d) continue
            byDay[day] = DaySleepSummary(day, d, tracked = true)
        }
        return byDay.values.sortedByDescending { it.date }
    }

    /** Last night: the longest night that ended today, from either source. */
    fun lastNight(sessions: List<SleepSession>, health: List<SleepEntry>, today: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault()): Long? =
        merge(sessions, health, zone).firstOrNull { it.date == today }?.durationMillis
}

/** "7h 40m". */
fun formatSleep(millis: Long, hoursMinutes: (Int, Int) -> String): String {
    val minutes = max(0L, millis / 60_000).toInt()
    return hoursMinutes(minutes / 60, minutes % 60)
}
