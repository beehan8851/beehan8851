package uz.ata.dawnwick.alarm

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import uz.ata.dawnwick.alarm.model.Alarm
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore

/**
 * The alarm list, the one source of truth. Stored in a versioned envelope; each
 * alarm is read on its own, so one corrupt entry never takes the others with it.
 */
class AlarmRepository(private val store: KeyValueStore) {

    @Serializable
    private data class Envelope(val schemaVersion: Int, val alarms: List<Alarm>)

    @Synchronized
    fun fetchAll(): List<Alarm> {
        val raw = store.getString(KEY) ?: return emptyList()
        val root = runCatching { AppJson.parseToJsonElement(raw) }.getOrNull() ?: return emptyList()
        val items: JsonArray = when (root) {
            is JsonArray -> root
            is JsonObject -> root["alarms"]?.jsonArray ?: return emptyList()
            else -> return emptyList()
        }
        return items.mapNotNull { element ->
            runCatching { AppJson.decodeFromJsonElement<Alarm>(element) }.getOrNull()
        }
    }

    fun alarm(id: String): Alarm? = fetchAll().firstOrNull { it.id == id }

    @Synchronized
    fun save(alarm: Alarm) {
        val all = fetchAll().toMutableList()
        val index = all.indexOfFirst { it.id == alarm.id }
        if (index >= 0) all[index] = alarm else all.add(alarm)
        write(all)
    }

    @Synchronized
    fun delete(id: String) = write(fetchAll().filterNot { it.id == id })

    private fun write(alarms: List<Alarm>) =
        store.putString(KEY, AppJson.encodeToString(Envelope.serializer(), Envelope(SCHEMA_VERSION, alarms)))

    companion object {
        private const val KEY = "alarms.v2"
        const val SCHEMA_VERSION = 2
    }
}
