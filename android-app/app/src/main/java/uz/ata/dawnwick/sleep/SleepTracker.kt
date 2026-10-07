package uz.ata.dawnwick.sleep

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import kotlin.math.log10
import kotlin.math.sqrt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import uz.ata.dawnwick.MainActivity
import uz.ata.dawnwick.R
import uz.ata.dawnwick.core.KeyValueStore
import uz.ata.dawnwick.graph

/** A looping sleep sound that fades in over two seconds and out over one. */
class SleepAudio(private val context: Context) {
    private var player: MediaPlayer? = null
    var current: SleepSound = SleepSound.NONE; private set
    private val main = Handler(Looper.getMainLooper())
    private var fade: Runnable? = null
    private var level = 0f

    val isPlaying get() = player?.isPlaying == true

    fun play(sound: SleepSound) {
        if (sound == SleepSound.NONE) { stop(); return }
        if (sound == current && isPlaying) return
        stopImmediate()
        val res = if (sound == SleepSound.WHITE_NOISE) R.raw.white_noise else R.raw.brown_noise
        val attrs = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
        player = MediaPlayer.create(context, res, attrs, 0)?.apply {
            isLooping = true
            setVolume(0f, 0f)
            start()
        }
        current = sound
        ramp(1f, 2000)
    }

    fun stop() {
        val p = player ?: return
        ramp(0f, 1000) { if (player === p) stopImmediate() }
    }

    fun stopImmediate() {
        fade?.let(main::removeCallbacks)
        runCatching { player?.stop() }
        player?.release()
        player = null
        current = SleepSound.NONE
        level = 0f
    }

    private fun ramp(to: Float, millis: Long, then: (() -> Unit)? = null) {
        fade?.let(main::removeCallbacks)
        val from = level
        val steps = 20
        var i = 0
        val r = object : Runnable {
            override fun run() {
                i++
                level = from + (to - from) * i / steps
                runCatching { player?.setVolume(level, level) }
                if (i < steps) main.postDelayed(this, millis / steps) else then?.invoke()
            }
        }
        fade = r
        main.post(r)
    }
}

/**
 * The room's loudness from the microphone, as a level now and then: nothing is kept
 * but the numbers. Every two seconds; anything over -40 dBFS — a quiet room
 * disturbed — is an event, at most one a minute.
 */
class NoiseMonitor(private val context: Context) {
    private val _level = MutableStateFlow(-160f)
    val level: StateFlow<Float> = _level.asStateFlow()
    private val _events = MutableStateFlow<List<NoiseEvent>>(emptyList())
    val events: StateFlow<List<NoiseEvent>> = _events.asStateFlow()
    @Volatile private var running = false
    private var thread: Thread? = null
    private var lastEvent = 0L

    val allowed get() = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    val isMonitoring get() = running

    @SuppressLint("MissingPermission")
    fun start() {
        if (running || !allowed) return
        val rate = 8000
        val size = maxOf(AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT), rate / 5 * 2)
        val record = runCatching { AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size) }.getOrNull() ?: return
        if (record.state != AudioRecord.STATE_INITIALIZED) { record.release(); return }
        running = true
        thread = Thread {
            val buf = ShortArray(rate / 5)
            var sum = 0.0
            var count = 0L
            var windowStart = System.currentTimeMillis()
            runCatching { record.startRecording() }
            while (running) {
                val n = record.read(buf, 0, buf.size)
                if (n > 0) for (i in 0 until n) { val v = buf[i].toDouble(); sum += v * v; count++ }
                val now = System.currentTimeMillis()
                if (now - windowStart >= 2000 && count > 0) {
                    val rms = sqrt(sum / count)
                    val db = if (rms <= 0.0) -160f else (20 * log10(rms / 32768.0)).toFloat()
                    _level.value = db
                    if (db > EVENT_THRESHOLD_DB && now - lastEvent >= 60_000) {
                        lastEvent = now
                        _events.value = _events.value + NoiseEvent(now, db)
                    }
                    sum = 0.0; count = 0; windowStart = now
                }
            }
            runCatching { record.stop() }
            record.release()
        }.apply { name = "dawnwick-noise"; start() }
    }

    fun stop() {
        running = false
        thread = null
        _level.value = -160f
    }

    fun reset() {
        stop()
        _events.value = emptyList()
        lastEvent = 0
    }

    companion object { const val EVENT_THRESHOLD_DB = -40f }
}

/**
 * The night: a session started and stopped by hand, the sound, the listening, and
 * a foreground service so the system leaves all three alone until morning. Survives
 * the app being killed: the active session is saved and picked up again, though the
 * sound and the microphone are not restarted — the person is asleep.
 */
class SleepTracker(private val context: Context, private val store: KeyValueStore) {
    val repository = SleepRepository(store)
    val audio = SleepAudio(context)
    val noise = NoiseMonitor(context)

    private val _active = MutableStateFlow<SleepSession?>(null)
    val active: StateFlow<SleepSession?> = _active.asStateFlow()
    var isRestored = false; private set

    var selectedSound: SleepSound
        get() = SleepSound.of(store.getString(SOUND_KEY))
        set(value) {
            store.putString(SOUND_KEY, value.raw)
            if (_active.value != null) audio.play(value)
        }

    /** Off unless turned on: it holds the microphone open all night. */
    var noiseMonitoring: Boolean
        get() = store.getBoolean(NOISE_KEY, false)
        set(value) = store.putBoolean(NOISE_KEY, value)

    init {
        repository.loadActive()?.takeIf { it.isActive }?.let { s ->
            if (System.currentTimeMillis() - s.startMillis <= MAX_RESTORABLE_MILLIS) {
                _active.value = s
                isRestored = true
            } else {
                // Discarded, not closed at the cap: nobody knows when this person woke,
                // and a made-up fourteen-hour night would sit in their history as fact.
                repository.clearActive()
            }
        }
    }

    fun start() {
        if (_active.value != null) return
        val session = SleepSession(startMillis = System.currentTimeMillis(), soundUsed = selectedSound)
        _active.value = session
        isRestored = false
        noise.reset()
        repository.saveActive(session)
        val wantsNoise = noiseMonitoring && noise.allowed
        SleepService.start(context, wantsNoise)
        if (selectedSound != SleepSound.NONE) audio.play(selectedSound)
        if (wantsNoise) noise.start()
    }

    /** Ends tonight's session, saves it and returns it. */
    fun stop(): SleepSession? {
        val session = _active.value ?: return null
        val done = session.copy(endMillis = System.currentTimeMillis(), noiseEvents = noise.events.value)
        audio.stop()
        noise.stop()
        repository.saveCompleted(done)
        repository.clearActive()
        _active.value = null
        isRestored = false
        SleepService.stop(context)
        return done
    }

    /** Microphone allowed while tracking: listening starts now. */
    fun microphoneGranted() {
        noiseMonitoring = true
        if (_active.value != null) { SleepService.start(context, true); noise.start() }
    }

    companion object {
        const val SOUND_KEY = "sleep.sound"
        const val NOISE_KEY = "sleep.noise"
        const val MAX_RESTORABLE_MILLIS = 14 * 3600_000L
    }
}

/** Keeps the night running: an ongoing notification with the time asleep. */
class SleepService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || graph.sleep.active.value == null) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val listening = intent?.getBooleanExtra(EXTRA_MIC, false) == true && graph.sleep.noise.allowed
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            if (listening && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        runCatching { ServiceCompat.startForeground(this, ID, notification(this), type) }
        return START_STICKY
    }

    companion object {
        private const val ID = 4401
        private const val CHANNEL = "sleep"
        private const val ACTION_STOP = "uz.ata.dawnwick.SLEEP_STOP"
        private const val EXTRA_MIC = "mic"

        fun start(context: Context, listening: Boolean) {
            ContextCompat.startForegroundService(context, Intent(context, SleepService::class.java).putExtra(EXTRA_MIC, listening))
        }

        fun stop(context: Context) {
            runCatching { context.startService(Intent(context, SleepService::class.java).setAction(ACTION_STOP)) }
        }

        private fun notification(context: Context): Notification {
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.channel_sleep), NotificationManager.IMPORTANCE_LOW))
            val start = context.graph.sleep.active.value?.startMillis ?: System.currentTimeMillis()
            val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_TAB, 2),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            return NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_alarm)
                .setContentTitle(context.getString(R.string.sleep_tracking_title))
                .setContentText(context.getString(R.string.sleep_tracking_body))
                .setWhen(start).setUsesChronometer(true).setShowWhen(true)
                .setOngoing(true).setSilent(true)
                .setContentIntent(open)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .build()
        }
    }
}
