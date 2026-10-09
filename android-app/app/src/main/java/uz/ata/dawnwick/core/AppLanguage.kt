package uz.ata.dawnwick.core

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import android.content.res.Resources
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * The app's own language, apart from the phone's. Android 13 and later keep it for the
 * app themselves (it is also in the phone's Settings › Apps › Dawnwick › Language);
 * before that the app keeps it and puts it on every context it starts with ([wrap]).
 */
object AppLanguage {
    /** Every language the app speaks, by tag, each named in itself. `null` is the phone's language. */
    val all: List<Pair<String, String>> = listOf(
        "en" to "English",
        "uz" to "O'zbekcha",
        "ru" to "Русский",
        "de" to "Deutsch",
        "es" to "Español",
        "fr" to "Français",
        "it" to "Italiano",
        "pt-BR" to "Português (Brasil)",
        "tr" to "Türkçe",
        "ja" to "日本語",
        "ko" to "한국어",
        "zh-Hans" to "简体中文",
        "zh-Hant" to "繁體中文",
    )

    private const val PREFS = "dawnwick_language"
    private const val KEY = "tag"

    /** The chosen language's tag, one of [all]'s, or `null` for the phone's. */
    fun current(context: Context): String? {
        val tag = if (Build.VERSION.SDK_INT >= 33) {
            context.getSystemService(LocaleManager::class.java)?.applicationLocales?.takeUnless { it.isEmpty }?.get(0)?.toLanguageTag()
        } else {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        } ?: return null
        // Settings may hand back a fuller tag ("uz-UZ", "zh-Hans-CN"): match the longest of ours it starts with.
        return all.map { it.first }.filter { tag.equals(it, true) || tag.startsWith("$it-", true) }.maxByOrNull { it.length }
            ?: all.map { it.first }.firstOrNull { Locale.forLanguageTag(it).language == Locale.forLanguageTag(tag).language }
    }

    fun name(tag: String?) = all.firstOrNull { it.first == tag }?.second

    /**
     * The screen as it was just before a switch. The app's root lays it over the new
     * language and lets it melt away, blurring as it fades, instead of a cut.
     */
    val veil = MutableStateFlow<ImageBitmap?>(null)

    /** Bumped when the language changes in place before Android 13, so the screen reads its words again. */
    val revision = MutableStateFlow(0)

    /**
     * Switches to `tag` (`null`: the phone's language) without restarting anything:
     * the main screen handles the change itself (`configChanges` in the manifest).
     */
    fun set(activity: Activity, tag: String?) {
        // The screen copied from the GPU's own frame (a software redraw would miss the blur),
        // then the switch once the copy is in hand.
        val view = activity.window.decorView
        if (view.width > 0 && view.height > 0) {
            val shot = android.graphics.Bitmap.createBitmap(view.width, view.height, android.graphics.Bitmap.Config.ARGB_8888)
            val started = runCatching {
                android.view.PixelCopy.request(activity.window, shot, { result ->
                    if (result == android.view.PixelCopy.SUCCESS) veil.value = shot.asImageBitmap()
                    apply(activity, tag)
                }, android.os.Handler(android.os.Looper.getMainLooper()))
            }.isSuccess
            if (started) return
        }
        apply(activity, tag)
    }

    private fun apply(activity: Activity, tag: String?) {
        if (Build.VERSION.SDK_INT >= 33) {
            // Android keeps it, and tells the screen through onConfigurationChanged.
            activity.getSystemService(LocaleManager::class.java)?.applicationLocales =
                if (tag == null) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
        } else {
            activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                if (tag == null) remove(KEY) else putString(KEY, tag)
            }.apply()
            val locales = if (tag == null) Resources.getSystem().configuration.locales else LocaleList(Locale.forLanguageTag(tag))
            Locale.setDefault(locales[0])
            // This screen's words and the app's (notifications, widgets) both, in place.
            for (resources in listOf(activity.resources, activity.applicationContext.resources)) {
                val config = Configuration(resources.configuration).apply { setLocales(locales) }
                @Suppress("DEPRECATION") resources.updateConfiguration(config, resources.displayMetrics)
            }
            revision.value++
        }
    }

    /** Before Android 13: `base` in the chosen language. From 13 on, Android does this itself. */
    fun wrap(base: Context): Context {
        if (Build.VERSION.SDK_INT >= 33) return base
        // Runs before anything else, so a language must never stop the app from starting.
        return runCatching {
            val tag = base.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return base
            val locale = Locale.forLanguageTag(tag)
            Locale.setDefault(locale)
            base.createConfigurationContext(Configuration(base.resources.configuration).apply { setLocales(LocaleList(locale)) })
        }.getOrDefault(base)
    }
}
