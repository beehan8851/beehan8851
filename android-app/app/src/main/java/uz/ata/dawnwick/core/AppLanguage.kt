package uz.ata.dawnwick.core

import android.app.Activity
import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import java.util.Locale

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

    /** Switches to `tag` (`null`: the phone's language) and redraws `activity` in it. */
    fun set(activity: Activity, tag: String?) {
        if (Build.VERSION.SDK_INT >= 33) {
            // Android keeps it and recreates the app's screens itself.
            activity.getSystemService(LocaleManager::class.java)?.applicationLocales =
                if (tag == null) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
        } else {
            activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                if (tag == null) remove(KEY) else putString(KEY, tag)
            }.commit()
            // The application context took its language when the process began; start a
            // new one so notifications and widgets follow too.
            activity.packageManager.getLaunchIntentForPackage(activity.packageName)?.let {
                activity.startActivity(it.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK))
            }
            activity.finish()
            Runtime.getRuntime().exit(0)
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
