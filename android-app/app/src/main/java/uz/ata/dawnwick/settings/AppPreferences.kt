package uz.ata.dawnwick.settings

import uz.ata.dawnwick.alarm.model.AlarmSound
import uz.ata.dawnwick.core.KeyValueStore

/** System, light or dark: the app's look, whatever the phone's. */
enum class Appearance { SYSTEM, LIGHT, DARK }

/** The person's settings that are not an alarm. */
class AppPreferences(private val store: KeyValueStore) {
    private val _appearance = kotlinx.coroutines.flow.MutableStateFlow(
        store.getString("prefs.appearance")?.let { runCatching { Appearance.valueOf(it) }.getOrNull() } ?: Appearance.SYSTEM,
    )
    val appearanceFlow: kotlinx.coroutines.flow.StateFlow<Appearance> = _appearance

    var appearance: Appearance
        get() = _appearance.value
        set(value) { store.putString("prefs.appearance", value.name); _appearance.value = value }

    var defaultSound: AlarmSound
        get() = store.getString("prefs.defaultSound")?.let { runCatching { AlarmSound.valueOf(it) }.getOrNull() } ?: AlarmSound.DEFAULT
        set(value) = store.putString("prefs.defaultSound", value.name)

    var hapticsEnabled: Boolean
        get() = store.getBoolean("prefs.haptics", true)
        set(value) = store.putBoolean("prefs.haptics", value)

    var onboardingCompleted: Boolean
        get() = store.getBoolean("prefs.onboardingCompleted", false)
        set(value) = store.putBoolean("prefs.onboardingCompleted", value)
}
