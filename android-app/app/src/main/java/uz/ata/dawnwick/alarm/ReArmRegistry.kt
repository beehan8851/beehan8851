package uz.ata.dawnwick.alarm

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore

/**
 * Every transient alarm id the app creates — a snooze, an escape or persistence
 * re-arm, the wake check's auto-fail, the test alarm — mapped back to the alarm it
 * belongs to. Disabling, editing, deleting or completing an alarm must cancel every
 * one of them, or a snoozed copy rings on under an id nobody remembers.
 */
class ReArmRegistry(private val store: KeyValueStore) {

    @Serializable
    enum class Kind { SNOOZE, RE_ARM, WAKE_CHECK, TEST }

    @Serializable
    data class Entry(val originalId: String, val fireAtMillis: Long, val kind: Kind)

    private val serializer = MapSerializer(String.serializer(), Entry.serializer())

    val entries: Map<String, Entry> get() = load()
    val allReArmIds: Set<String> get() = load().keys

    fun entry(reArmId: String): Entry? = load()[reArmId]

    fun reArmIds(originalId: String, kind: Kind? = null): List<String> =
        load().filter { it.value.originalId == originalId && (kind == null || it.value.kind == kind) }.keys.toList()

    /** True when `originalId` came from the test flow and so lives in no list. */
    fun isTestOriginal(originalId: String) = load().values.any { it.originalId == originalId && it.kind == Kind.TEST }

    @Synchronized
    fun register(reArmId: String, originalId: String, fireAtMillis: Long, kind: Kind) =
        store(load() + (reArmId to Entry(originalId, fireAtMillis, kind)))

    @Synchronized
    fun remove(reArmId: String) {
        val all = load()
        if (reArmId in all) store(all - reArmId)
    }

    @Synchronized
    fun removeAll(originalId: String): List<String> {
        val all = load()
        val ids = all.filterValues { it.originalId == originalId }.keys
        if (ids.isNotEmpty()) store(all - ids)
        return ids.toList()
    }

    /** Forgets entries more than `STALE_GRACE` past their time; returns them to cancel. */
    @Synchronized
    fun prune(nowMillis: Long = System.currentTimeMillis()): List<String> {
        val all = load()
        val stale = all.filterValues { nowMillis - it.fireAtMillis > STALE_GRACE_MILLIS }.keys
        if (stale.isNotEmpty()) store(all - stale)
        return stale.toList()
    }

    private fun load(): Map<String, Entry> =
        store.getString(KEY)?.let { runCatching { AppJson.decodeFromString(serializer, it) }.getOrNull() } ?: emptyMap()

    private fun store(map: Map<String, Entry>) = store.putString(KEY, AppJson.encodeToString(serializer, map))

    companion object {
        private const val KEY = "rearm.registry.v1"
        const val STALE_GRACE_MILLIS = 30 * 60 * 1000L

        /**
         * The transient ids whose alarm is gone or switched off. Test entries have no
         * alarm to check against; they go only once stale.
         */
        fun orphanedReArmIds(entries: Map<String, Entry>, activeOriginalIds: Set<String>, nowMillis: Long = System.currentTimeMillis()): List<String> =
            entries.mapNotNull { (id, entry) ->
                if (entry.kind == Kind.TEST) {
                    if (nowMillis - entry.fireAtMillis > STALE_GRACE_MILLIS) id else null
                } else if (entry.originalId in activeOriginalIds) null else id
            }
    }
}
