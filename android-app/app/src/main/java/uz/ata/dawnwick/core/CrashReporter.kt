package uz.ata.dawnwick.core

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File
import uz.ata.dawnwick.BuildConfig
import uz.ata.dawnwick.R

/**
 * Keeps the last crash on the phone and shows it the next time the app opens, so a
 * tester without a computer can still send the developer exactly what went wrong.
 *
 * A crash while the app is starting would happen again on every launch, so then the
 * next launch skips starting and only shows the report ([startupCrashPending]). A crash
 * later on leaves starting alone — alarms keep ringing — and the report waits for the
 * app to be opened.
 */
object CrashReporter {
    private const val FILE = "last_crash.txt"
    private const val STARTUP = "startup: true"

    @Volatile private var starting = false

    fun install(context: Context) {
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                val file = File(app.filesDir, FILE)
                // The first crash is the one that matters; what follows from it is noise.
                if (!file.exists()) file.writeText(report(thread, error))
            }
            previous?.uncaughtException(thread, error)
        }
    }

    fun startupBegins() { starting = true }
    fun startupEnds() { starting = false }

    fun pending(context: Context): String? = File(context.filesDir, FILE).takeIf { it.exists() }?.let { runCatching { it.readText() }.getOrNull() }

    fun startupCrashPending(context: Context) = pending(context)?.lineSequence()?.any { it == STARTUP } == true

    fun clear(context: Context) { File(context.filesDir, FILE).delete() }

    private fun report(thread: Thread, error: Throwable) = buildString {
        appendLine("Dawnwick ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}, ${if (BuildConfig.DEBUG) "debug" else "release"})")
        appendLine("Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}")
        appendLine("thread: ${thread.name}")
        if (starting) appendLine(STARTUP)
        appendLine()
        append(error.stackTraceToString())
    }
}

/** The last crash, in words a developer can use: copy it, share it, or carry on. Plain views, no app state. */
class CrashActivity : Activity() {
    override fun attachBaseContext(base: android.content.Context) = super.attachBaseContext(AppLanguage.wrap(base))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val report = CrashReporter.pending(this) ?: run { restart(); return }
        val pad = (16 * resources.displayMetrics.density).toInt()
        val column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(pad, pad * 2, pad, pad) }
        column.addView(TextView(this).apply { text = getString(R.string.crash_title); textSize = 22f; setTypeface(typeface, Typeface.BOLD) })
        column.addView(TextView(this).apply { text = getString(R.string.crash_body); textSize = 15f; setPadding(0, pad / 2, 0, pad) })
        fun button(label: Int, onClick: () -> Unit) = column.addView(Button(this).apply { text = getString(label); setOnClickListener { onClick() } },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        button(R.string.crash_copy) {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Dawnwick crash", report))
            Toast.makeText(this, R.string.crash_copied, Toast.LENGTH_SHORT).show()
        }
        button(R.string.crash_share) {
            startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, report), null))
        }
        button(R.string.crash_continue) { CrashReporter.clear(this); restart() }
        column.addView(TextView(this).apply {
            text = report; textSize = 11f; typeface = Typeface.MONOSPACE; setTextIsSelectable(true); setPadding(0, pad, 0, 0)
        })
        setContentView(ScrollView(this).apply { addView(column) })
    }

    /** Starts afresh in a new process, so an app that skipped starting starts properly. */
    private fun restart() {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        }
        finish()
        Runtime.getRuntime().exit(0)
    }
}
