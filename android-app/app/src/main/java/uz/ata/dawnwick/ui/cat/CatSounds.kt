package uz.ata.dawnwick.ui.cat

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import uz.ata.dawnwick.R

/**
 * The cat's voice outside an alarm: a short mrrp when it is tapped — three takes a
 * little apart in pitch, never the same twice running — and the purr while it is
 * stroked. Both play as sonification, so they follow the media volume and never
 * take the alarm's stream.
 */
object CatSounds {
    private lateinit var app: Context
    private var pool: SoundPool? = null
    private val takes = IntArray(3)
    private var last = -1
    private var purr: MediaPlayer? = null
    private val main = Handler(Looper.getMainLooper())
    private var fade: Runnable? = null

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    fun init(context: Context) {
        app = context.applicationContext
    }

    private fun ensurePool(): SoundPool? {
        if (!::app.isInitialized) return null
        pool?.let { return it }
        return SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attributes).build().also { p ->
            takes[0] = p.load(app, R.raw.mrrp1, 1)
            takes[1] = p.load(app, R.raw.mrrp2, 1)
            takes[2] = p.load(app, R.raw.mrrp3, 1)
            pool = p
        }
    }

    fun mrrp() {
        val p = ensurePool() ?: return
        val choice = (0 until 3).filter { it != last }.random()
        last = choice
        p.play(takes[choice], 0.5f, 0.5f, 1, 0, 1f)
    }

    fun purrStart() {
        if (!::app.isInitialized) return
        fade?.let(main::removeCallbacks)
        val player = purr ?: MediaPlayer.create(app, R.raw.purr, attributes, 0)?.apply { isLooping = true; setVolume(0f, 0f) }
        purr = player ?: return
        if (!player.isPlaying) { player.seekTo(0); player.start() }
        ramp(player, to = 0.55f, millis = 400)
    }

    fun purrStop() {
        val player = purr ?: return
        ramp(player, to = 0f, millis = 600) { runCatching { player.pause() } }
    }

    private var level = 0f
    private fun ramp(player: MediaPlayer, to: Float, millis: Long, then: (() -> Unit)? = null) {
        fade?.let(main::removeCallbacks)
        val from = level
        val steps = 12
        var i = 0
        val r = object : Runnable {
            override fun run() {
                i++
                level = from + (to - from) * i / steps
                runCatching { player.setVolume(level, level) }
                if (i < steps) main.postDelayed(this, millis / steps) else then?.invoke()
            }
        }
        fade = r
        main.post(r)
    }
}
