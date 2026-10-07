package uz.ata.dawnwick.today

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import uz.ata.dawnwick.core.AppJson

/** One hour of the forecast. Temperatures are Celsius; chances 0–1. */
@Serializable
data class HourlyPoint(val epochSeconds: Long, val temperature: Double, val code: Int, val isDay: Boolean, val precipitationChance: Double)

/** The weather now and for the day, as read from Open-Meteo. */
@Serializable
data class WeatherConditions(
    val temperature: Double,
    val high: Double,
    val low: Double,
    /** WMO 4677 weather code. */
    val code: Int,
    val isDay: Boolean,
    val precipitationChance: Double,
    val humidity: Double? = null,
    /** km/h */
    val windSpeed: Double? = null,
    val hourly: List<HourlyPoint> = emptyList(),
    val placeName: String? = null,
    val capturedAt: Long,
)

/** Why there is no weather — only a refused permission is the person's to fix. */
enum class WeatherProblem { PERMISSION, LOCATION, NETWORK }

class WeatherException(val problem: WeatherProblem, cause: Throwable? = null) : Exception(problem.name, cause)

/**
 * Open-Meteo: keyless, so the Today screen has weather without an account. The
 * licence asks for a credit line, which the detail screen carries.
 */
object OpenMeteo {
    @Serializable
    private data class Response(val current: Current, val hourly: Hourly? = null, val daily: Daily? = null)

    @Serializable
    private data class Current(
        @SerialName("temperature_2m") val temperature: Double,
        @SerialName("weather_code") val code: Int,
        @SerialName("is_day") val isDay: Int = 1,
        @SerialName("relative_humidity_2m") val humidity: Int? = null,
        @SerialName("wind_speed_10m") val wind: Double? = null,
    )

    @Serializable
    private data class Hourly(
        val time: List<Long> = emptyList(),
        @SerialName("temperature_2m") val temperature: List<Double?> = emptyList(),
        @SerialName("weather_code") val code: List<Int?> = emptyList(),
        @SerialName("precipitation_probability") val precipitation: List<Int?>? = null,
        @SerialName("is_day") val isDay: List<Int?>? = null,
    )

    @Serializable
    private data class Daily(
        @SerialName("temperature_2m_max") val max: List<Double?> = emptyList(),
        @SerialName("temperature_2m_min") val min: List<Double?> = emptyList(),
        @SerialName("precipitation_probability_max") val precipitation: List<Int?>? = null,
    )

    fun url(latitude: Double, longitude: Double) = "https://api.open-meteo.com/v1/forecast" +
        "?latitude=$latitude&longitude=$longitude" +
        "&current=temperature_2m,weather_code,is_day,relative_humidity_2m,wind_speed_10m" +
        "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
        "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max" +
        // Absolute seconds: the offset-less local times timezone=auto gives otherwise
        // are easy to misread.
        "&temperature_unit=celsius&timezone=auto&timeformat=unixtime&forecast_days=2"

    /**
     * The response as conditions. The hourly arrays are zipped by index, defending
     * against short or mismatched ones, past hours dropped and 24 kept.
     */
    fun parse(json: String, nowMillis: Long, placeName: String?): WeatherConditions {
        val r = AppJson.decodeFromString<Response>(json)
        val cutoff = nowMillis / 1000 - 30 * 60
        val hourly = r.hourly?.let { h ->
            h.time.indices.mapNotNull { i ->
                val t = h.time[i]
                val temp = h.temperature.getOrNull(i) ?: return@mapNotNull null
                val code = h.code.getOrNull(i) ?: return@mapNotNull null
                if (t < cutoff) return@mapNotNull null
                HourlyPoint(t, temp, code, h.isDay?.getOrNull(i) != 0, (h.precipitation?.getOrNull(i) ?: 0) / 100.0)
            }.take(24)
        }.orEmpty()
        val c = r.current
        return WeatherConditions(
            temperature = c.temperature,
            high = r.daily?.max?.firstOrNull() ?: c.temperature,
            low = r.daily?.min?.firstOrNull() ?: c.temperature,
            code = c.code,
            isDay = c.isDay == 1,
            precipitationChance = (r.daily?.precipitation?.firstOrNull() ?: 0) / 100.0,
            humidity = c.humidity?.let { it / 100.0 },
            windSpeed = c.wind,
            hourly = hourly,
            placeName = placeName,
            capturedAt = nowMillis,
        )
    }

    suspend fun fetch(latitude: Double, longitude: Double): String = withContext(Dispatchers.IO) {
        val connection = URL(url(latitude, longitude)).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            if (connection.responseCode !in 200..299) throw WeatherException(WeatherProblem.NETWORK)
            connection.inputStream.bufferedReader().use { it.readText() }
        } catch (e: WeatherException) {
            throw e
        } catch (e: Exception) {
            throw WeatherException(WeatherProblem.NETWORK, e)
        } finally {
            connection.disconnect()
        }
    }
}

/** Where the phone is, roughly — a kilometre is plenty for the weather. */
object Locator {
    const val PERMISSION = Manifest.permission.ACCESS_COARSE_LOCATION

    fun allowed(context: Context) = ContextCompat.checkSelfPermission(context, PERMISSION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    suspend fun current(context: Context): Location {
        if (!allowed(context)) throw WeatherException(WeatherProblem.PERMISSION)
        val lm = context.getSystemService(LocationManager::class.java)
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.FUSED_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            .filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
        // A fix from the last quarter of an hour is as good as a new one.
        providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .filter { System.currentTimeMillis() - it.time < 15 * 60_000 }
            .maxByOrNull { it.time }?.let { return it }
        val active = providers.filter { it != LocationManager.PASSIVE_PROVIDER }
        if (active.isEmpty()) throw WeatherException(WeatherProblem.LOCATION)
        // Every provider at once, the first fix wins: on one phone only the network
        // answers indoors, on another only GPS has anything at all.
        val fresh = withTimeoutOrNull(15_000) {
            suspendCancellableCoroutine<Location?> { cont ->
                val signals = mutableListOf<CancellationSignal>()
                var pending = active.size
                val lock = Any()
                fun deliver(location: Location?) = synchronized(lock) {
                    pending--
                    if (!cont.isActive) return@synchronized
                    if (location != null) { signals.forEach { it.cancel() }; cont.resume(location) }
                    else if (pending == 0) cont.resume(null)
                }
                cont.invokeOnCancellation { synchronized(lock) { signals.forEach { it.cancel() } } }
                val executor = Executors.newSingleThreadExecutor()
                for (provider in active) {
                    runCatching {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val signal = CancellationSignal().also { synchronized(lock) { signals += it } }
                            lm.getCurrentLocation(provider, signal, executor) { deliver(it) }
                        } else {
                            @Suppress("DEPRECATION")
                            lm.requestSingleUpdate(provider, { deliver(it) }, context.mainLooper)
                        }
                    }.onFailure { deliver(null) }
                }
            }
        }
        // Any older fix beats none: the weather a few hours and a few streets away.
        return fresh ?: providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
            ?: throw WeatherException(WeatherProblem.LOCATION)
    }

    /** The town, as a person would say it. Never throws: a name is not worth a failed fetch. */
    suspend fun placeName(context: Context, location: Location): String? = withContext(Dispatchers.IO) {
        if (!Geocoder.isPresent()) return@withContext null
        runCatching {
            val geocoder = Geocoder(context, Locale.getDefault())
            val address = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                withTimeoutOrNull(8_000) {
                    suspendCancellableCoroutine { cont ->
                        geocoder.getFromLocation(location.latitude, location.longitude, 1, object : Geocoder.GeocodeListener {
                            override fun onGeocode(addresses: MutableList<android.location.Address>) { cont.resume(addresses.firstOrNull()) }
                            override fun onError(errorMessage: String?) { cont.resume(null) }
                        })
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                geocoder.getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
            }
            address?.locality ?: address?.subAdminArea ?: address?.adminArea
        }.getOrNull()
    }
}
