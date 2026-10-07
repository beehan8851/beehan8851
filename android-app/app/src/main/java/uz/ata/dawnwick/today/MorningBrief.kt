package uz.ata.dawnwick.today

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore

@Serializable
data class CalendarEvent(val title: String, val startMillis: Long, val location: String? = null)

/** The first timed event still to come today, from the phone's calendars. */
object CalendarReader {
    const val PERMISSION = Manifest.permission.READ_CALENDAR

    fun allowed(context: Context) = ContextCompat.checkSelfPermission(context, PERMISSION) == PackageManager.PERMISSION_GRANTED

    suspend fun firstEventToday(context: Context, nowMillis: Long = System.currentTimeMillis()): CalendarEvent? = withContext(Dispatchers.IO) {
        if (!allowed(context)) return@withContext null
        val zone = ZoneId.systemDefault()
        val dayEnd = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, nowMillis)
            ContentUris.appendId(it, dayEnd)
        }.build()
        val projection = arrayOf(CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.EVENT_LOCATION, CalendarContract.Instances.ALL_DAY)
        runCatching {
            context.contentResolver.query(uri, projection, "${CalendarContract.Instances.ALL_DAY} = 0 AND ${CalendarContract.Instances.BEGIN} >= ?",
                arrayOf(nowMillis.toString()), "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
                if (c.moveToFirst()) CalendarEvent(c.getString(0).orEmpty(), c.getLong(1), c.getString(2)?.takeIf { it.isNotBlank() }) else null
            }
        }.getOrNull()
    }
}

/**
 * The slow parts of Today, kept so the screen shows something at once next time.
 * Each goes stale on its own clock, and a stale part is dropped rather than shown
 * as today's.
 */
@Serializable
data class BriefCache(val weather: WeatherConditions? = null, val event: CalendarEvent? = null) {
    fun usable(nowMillis: Long, zone: ZoneId = ZoneId.systemDefault()): BriefCache {
        val today = LocalDate.now(zone)
        val eventOk = event?.let { it.startMillis >= nowMillis && java.time.Instant.ofEpochMilli(it.startMillis).atZone(zone).toLocalDate() == today } ?: false
        // A reading from the future is a clock that was changed: not trusted either.
        val weatherOk = weather?.let { abs(nowMillis - it.capturedAt) <= WEATHER_SHELF_LIFE } ?: false
        return BriefCache(if (weatherOk) weather else null, if (eventOk) event else null)
    }

    companion object { const val WEATHER_SHELF_LIFE = 3 * 3600_000L }
}

data class Brief(val weather: WeatherConditions?, val weatherProblem: WeatherProblem?, val event: CalendarEvent?)

/** Reads the morning's facts, keeps them, and the day's one line of focus. */
class MorningBriefRepository(private val context: Context, private val store: KeyValueStore) {

    fun cached(nowMillis: Long = System.currentTimeMillis()): Brief {
        val c = loadCache().usable(nowMillis)
        return Brief(c.weather, null, c.event)
    }

    /**
     * Fresh where the source answers, the cached value where it does not. Nothing is
     * asked for here: weather is read only once location has been allowed, from the
     * card's own button.
     */
    suspend fun refresh(nowMillis: Long = System.currentTimeMillis()): Brief = coroutineScope {
        val cached = loadCache().usable(nowMillis)
        val event = async { CalendarReader.firstEventToday(context, nowMillis) }
        var problem: WeatherProblem? = null
        val weather = if (!Locator.allowed(context)) {
            problem = WeatherProblem.PERMISSION
            null
        } else {
            try {
                val location = Locator.current(context)
                val name = async { Locator.placeName(context, location) }
                val json = OpenMeteo.fetch(location.latitude, location.longitude)
                OpenMeteo.parse(json, nowMillis, name.await())
            } catch (e: WeatherException) {
                android.util.Log.w(TAG, "Weather unavailable: ${e.problem}", e.cause)
                problem = e.problem
                null
            } catch (e: Exception) {
                android.util.Log.w(TAG, "Weather failed", e)
                problem = WeatherProblem.NETWORK
                null
            }
        }
        val freshEvent = event.await()
        val brief = Brief(
            weather = weather ?: cached.weather,
            weatherProblem = if (weather == null && cached.weather == null) problem else null,
            // The calendar answered (or was never allowed): believe it, "nothing" included.
            event = if (CalendarReader.allowed(context)) freshEvent else null,
        )
        store.putString(CACHE_KEY, AppJson.encodeToString(BriefCache.serializer(), BriefCache(brief.weather, brief.event)))
        brief
    }

    private fun loadCache() = store.getString(CACHE_KEY)?.let { runCatching { AppJson.decodeFromString<BriefCache>(it) }.getOrNull() } ?: BriefCache()

    fun focus(day: LocalDate = LocalDate.now()): String = store.getString(focusKey(day)).orEmpty()

    fun saveFocus(text: String, day: LocalDate = LocalDate.now()) {
        val t = text.trim()
        if (t.isEmpty()) store.remove(focusKey(day)) else store.putString(focusKey(day), t)
    }

    companion object {
        const val CACHE_KEY = "today.brief.v1"
        private const val TAG = "Dawnwick.Brief"
        /** The day's focus lives under its date, so the wind-down can leave tomorrow's. */
        fun focusKey(day: LocalDate) = "today.focus.$day"
    }
}
