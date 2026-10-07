package uz.ata.dawnwick.ring

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import uz.ata.dawnwick.R
import uz.ata.dawnwick.alarm.model.AlarmSound

/**
 * The alarm's tones, made as the iOS app makes them — the same notes, envelopes
 * and loop lengths — and looped until stopped. The cat's meow is a recording.
 *
 * Played on the alarm stream, so the alarm volume decides how loud, not the media
 * volume: the alarm rings with the phone on silent and Do Not Disturb on.
 */
object ToneSynth {
    const val SAMPLE_RATE = 44_100

    fun samples(sound: AlarmSound): ShortArray = when (sound) {
        AlarmSound.DEFAULT, AlarmSound.MEOW -> classic()
        AlarmSound.GENTLE -> gentle()
        AlarmSound.RISE -> rise()
        AlarmSound.PULSE -> pulse()
        AlarmSound.CHIME -> chime()
        AlarmSound.DIGITAL -> digital()
    }

    private fun n(ms: Int) = ms * SAMPLE_RATE / 1000

    /** Classic two-beep: A5, 120 ms, 80 ms apart, 1.02 s loop. */
    private fun classic(): ShortArray {
        val beep = n(120); val short = n(80); val long = n(700)
        val buf = ShortArray(beep * 2 + short + long)
        tone(buf, 0, beep, 880.0, 1f, 0.18)
        tone(buf, beep + short, beep, 880.0, 1f, 0.18)
        return buf
    }

    /** Ascending bell chime C5 → E5 → G5, 2.4 s loop. */
    private fun gentle(): ShortArray {
        val note = n(360); val gap = n(60); val rest = n(1080)
        val freqs = doubleArrayOf(523.25, 659.25, 783.99)
        val buf = ShortArray(freqs.size * (note + gap) + rest)
        freqs.forEachIndexed { i, f -> bell(buf, i * (note + gap), note, f, 0.84f) }
        return buf
    }

    /** E4 → G4 → B4 → E5 → B5, each shorter and louder, 1.75 s loop. */
    private fun rise(): ShortArray {
        val freqs = doubleArrayOf(329.63, 392.00, 493.88, 659.25, 987.77)
        val lens = intArrayOf(n(165), n(148), n(130), n(112), n(95))
        val gap = n(82); val rest = n(580)
        val buf = ShortArray(lens.sum() + freqs.size * gap + rest)
        var at = 0
        for (i in freqs.indices) {
            tone(buf, at, lens[i], freqs[i], (0.76 + 0.06 * i).toFloat(), 0.14)
            at += lens[i] + gap
        }
        return buf
    }

    /** Three deep thuds on A3, 2.55 s loop. */
    private fun pulse(): ShortArray {
        val thump = n(195); val gap = n(285); val rest = n(885)
        val buf = ShortArray(3 * (thump + gap) + rest)
        for (i in 0 until 3) thump(buf, i * (thump + gap), thump, 220.0)
        return buf
    }

    /** Two warm bell strikes a fifth apart, A4 → E5. */
    private fun chime(): ShortArray {
        val s1 = n(550); val gap = n(250); val s2 = n(450); val rest = n(1200)
        val buf = ShortArray(s1 + gap + s2 + rest)
        bell(buf, 0, s1, 440.0, 1f)
        bell(buf, s1 + gap, s2, 659.25, 0.88f)
        return buf
    }

    /** The digital clock's three-beep burst at 1 kHz. */
    private fun digital(): ShortArray {
        val beep = n(72); val gap = n(48); val rest = n(472)
        val buf = ShortArray(3 * beep + 2 * gap + rest)
        for (i in 0 until 3) square(buf, i * (beep + gap), beep, 1000.0)
        return buf
    }

    private fun put(buf: ShortArray, i: Int, v: Double) {
        buf[i] = (v * 32767).roundToInt().coerceIn(-32768, 32767).toShort()
    }

    private fun tone(buf: ShortArray, offset: Int, len: Int, freq: Double, vol: Float, h2: Double) {
        val ramp = min(len / 10, n(7))
        val norm = 1.0 + h2
        for (i in 0 until len) {
            if (offset + i >= buf.size) break
            val env = when { i < ramp -> i.toDouble() / ramp; i > len - ramp -> (len - i).toDouble() / ramp; else -> 1.0 }
            val t = (offset + i).toDouble() / SAMPLE_RATE
            val wave = (sin(2 * PI * freq * t) + h2 * sin(2 * PI * freq * 2 * t)) / norm
            put(buf, offset + i, vol * env * wave)
        }
    }

    private fun bell(buf: ShortArray, offset: Int, len: Int, freq: Double, vol: Float) {
        val attack = min(len / 14, n(16))
        for (i in 0 until len) {
            if (offset + i >= buf.size) break
            val env = if (i < attack) i.toDouble() / attack else exp(-3.8 * (i - attack) / maxOf(1, len - attack))
            val t = (offset + i).toDouble() / SAMPLE_RATE
            val f1 = sin(2 * PI * freq * t)
            val f2 = 0.38 * exp(-3.0 * i / len) * sin(2 * PI * freq * 2 * t)
            val f3 = 0.14 * exp(-6.5 * i / len) * sin(2 * PI * freq * 3 * t)
            put(buf, offset + i, vol * env * (f1 + f2 + f3) / 1.52)
        }
    }

    private fun thump(buf: ShortArray, offset: Int, len: Int, freq: Double) {
        for (i in 0 until len) {
            if (offset + i >= buf.size) break
            val env = exp(-5.5 * i / len)
            put(buf, offset + i, env * sin(2 * PI * freq * (offset + i) / SAMPLE_RATE))
        }
    }

    private fun square(buf: ShortArray, offset: Int, len: Int, freq: Double) {
        val ramp = min(len / 8, n(4))
        for (i in 0 until len) {
            if (offset + i >= buf.size) break
            val env = when { i < ramp -> i.toDouble() / ramp; i > len - ramp -> (len - i).toDouble() / ramp; else -> 1.0 }
            val t = (offset + i).toDouble() / SAMPLE_RATE
            val wave = (sin(2 * PI * freq * t) + 0.33 * sin(2 * PI * freq * 3 * t) + 0.20 * sin(2 * PI * freq * 5 * t)) / 1.53
            put(buf, offset + i, env * wave)
        }
    }
}

/**
 * Plays one alarm sound in a loop. `alarmStream`: on the alarm stream (ringing);
 * otherwise on the media stream (a preview in the editor, which must not blare at
 * alarm volume in a quiet room).
 */
class TonePlayer(private val context: Context, private val alarmStream: Boolean) {
    private var track: AudioTrack? = null
    private var media: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var fade: Runnable? = null

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(if (alarmStream) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** `volume` 0–1 of the stream; with `fadeInSeconds` it starts near silent and rises. */
    fun play(sound: AlarmSound, volume: Float, fadeInSeconds: Int = 0) {
        stop()
        val target = volume.coerceIn(0f, 1f)
        val start = if (fadeInSeconds > 0) 0.05f else target
        // The designed recordings the iOS app ships, where there is one; Default is
        // synthesised there too.
        val file = when (sound) {
            AlarmSound.MEOW -> R.raw.meow
            AlarmSound.GENTLE -> R.raw.tone_gentle
            AlarmSound.RISE -> R.raw.tone_rise
            AlarmSound.PULSE -> R.raw.tone_pulse
            AlarmSound.CHIME -> R.raw.tone_chime
            AlarmSound.DIGITAL -> R.raw.tone_digital
            AlarmSound.DEFAULT -> null
        }
        if (file != null) {
            media = MediaPlayer().apply {
                setAudioAttributes(attributes)
                val fd = context.resources.openRawResourceFd(file)
                setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
                fd.close()
                isLooping = true
                prepare()
                setVolume(start, start)
                start()
            }
        } else {
            val samples = ToneSynth.samples(sound)
            track = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(ToneSynth.SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(samples.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
                .apply {
                    write(samples, 0, samples.size)
                    setLoopPoints(0, samples.size, -1)
                    setVolume(start)
                    play()
                }
        }
        if (fadeInSeconds > 0) rampTo(target, fadeInSeconds * 1000L)
    }

    private fun setVolume(v: Float) {
        track?.setVolume(v)
        media?.setVolume(v, v)
    }

    private fun rampTo(target: Float, durationMillis: Long) {
        val steps = 40
        val from = 0.05f
        var step = 0
        val runnable = object : Runnable {
            override fun run() {
                step++
                setVolume(from + (target - from) * step / steps)
                if (step < steps) handler.postDelayed(this, durationMillis / steps)
            }
        }
        fade = runnable
        handler.postDelayed(runnable, durationMillis / steps)
    }

    fun stop() {
        fade?.let { handler.removeCallbacks(it) }
        fade = null
        track?.runCatching { stop(); release() }
        track = null
        media?.runCatching { stop(); release() }
        media = null
    }

    companion object {
        /**
         * Makes sure the alarm stream is loud enough to wake: never below the share the
         * alarm asks for. Returns the volume to put back afterwards.
         */
        fun raiseAlarmStream(context: Context, share: Float): Int {
            val audio = context.getSystemService(AudioManager::class.java)
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val current = audio.getStreamVolume(AudioManager.STREAM_ALARM)
            val wanted = (max * share.coerceIn(0.3f, 1f)).roundToInt().coerceIn(1, max)
            if (current < wanted) runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, wanted, 0) }
            return current
        }

        fun restoreAlarmStream(context: Context, volume: Int) {
            runCatching { context.getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM, volume, 0) }
        }
    }
}
