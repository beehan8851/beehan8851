package uz.ata.dawnwick.core

import android.content.Context
import android.content.SharedPreferences
import kotlinx.serialization.json.Json

/** The app's one JSON setup: tolerant of fields it does not know, so old builds read new data. */
val AppJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    coerceInputValues = true
}

/**
 * Key-value storage the alarm engine writes through. Writes are committed before
 * they return: a receiver woken for an alarm may be killed the moment it finishes,
 * and an alarm whose snooze was "saved later" is an alarm that never rings again.
 */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun getInt(key: String, default: Int = 0): Int
    fun putInt(key: String, value: Int)
    fun getBoolean(key: String, default: Boolean = false): Boolean
    fun putBoolean(key: String, value: Boolean)
    fun remove(key: String)
}

class PrefsStore(private val prefs: SharedPreferences) : KeyValueStore {
    constructor(context: Context) : this(context.getSharedPreferences("dawnwick", Context.MODE_PRIVATE))

    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun putString(key: String, value: String) { prefs.edit().putString(key, value).commit() }
    override fun getInt(key: String, default: Int) = prefs.getInt(key, default)
    override fun putInt(key: String, value: Int) { prefs.edit().putInt(key, value).commit() }
    override fun getBoolean(key: String, default: Boolean) = prefs.getBoolean(key, default)
    override fun putBoolean(key: String, value: Boolean) { prefs.edit().putBoolean(key, value).commit() }
    override fun remove(key: String) { prefs.edit().remove(key).commit() }
}

/** A store that lives as long as it does: tests and previews. */
class MemoryStore : KeyValueStore {
    private val values = mutableMapOf<String, Any>()
    override fun getString(key: String) = values[key] as? String
    override fun putString(key: String, value: String) { values[key] = value }
    override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
    override fun putInt(key: String, value: Int) { values[key] = value }
    override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}
