package uz.ata.dawnwick.sleep

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * The sleep the phone or a watch already records, from Health Connect — Android's
 * Apple Health. Read only, never asked for on its own: the card's button asks.
 */
class HealthSleep(private val context: Context) {
    enum class State { UNAVAILABLE, NOT_CONNECTED, CONNECTED }

    val permission = HealthPermission.getReadPermission(SleepSessionRecord::class)

    private fun client(): HealthConnectClient? =
        if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) HealthConnectClient.getOrCreate(context) else null

    suspend fun state(): State {
        val c = client() ?: return State.UNAVAILABLE
        return if (permission in runCatching { c.permissionController.getGrantedPermissions() }.getOrDefault(emptySet())) State.CONNECTED else State.NOT_CONNECTED
    }

    fun requestContract() = PermissionController.createRequestPermissionResultContract()

    /**
     * The last `days` nights, by the day each ended: time asleep where the stages say
     * so, otherwise the whole session.
     */
    suspend fun history(days: Int = 7, zone: ZoneId = ZoneId.systemDefault()): List<SleepEntry> {
        val c = client() ?: return emptyList()
        if (state() != State.CONNECTED) return emptyList()
        val start = LocalDate.now(zone).minusDays(days.toLong()).atStartOfDay(zone).toInstant()
        val records = runCatching {
            c.readRecords(ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(start, Instant.now()))).records
        }.getOrDefault(emptyList())
        val asleepStages = setOf(
            SleepSessionRecord.STAGE_TYPE_SLEEPING, SleepSessionRecord.STAGE_TYPE_LIGHT,
            SleepSessionRecord.STAGE_TYPE_DEEP, SleepSessionRecord.STAGE_TYPE_REM,
        )
        return records.groupBy { it.endTime.atZone(zone).toLocalDate() }.map { (day, nights) ->
            val millis = nights.sumOf { r ->
                val staged = r.stages.filter { it.stage in asleepStages }.sumOf { it.endTime.toEpochMilli() - it.startTime.toEpochMilli() }
                if (staged > 0) staged else r.endTime.toEpochMilli() - r.startTime.toEpochMilli()
            }
            SleepEntry(day, millis)
        }.sortedByDescending { it.date }
    }
}
