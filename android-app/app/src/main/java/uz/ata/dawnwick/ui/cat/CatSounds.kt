package uz.ata.dawnwick.ui.cat

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import uz.ata.dawnwick.R
import uz.ata.dawnwick.companion.Pet
import uz.ata.dawnwick.graph

/** Each companion's recordings: the alarm call, three short answers to a tap, and the calm loop. */
object PetVoices {
    fun alarm(pet: Pet) = when (pet) {
        Pet.CAT -> R.raw.meow
        Pet.PUPPY -> R.raw.pet_puppy_alarm
        Pet.CHICK -> R.raw.pet_chick_alarm
        Pet.CANARY -> R.raw.pet_canary_alarm
        Pet.LAMB -> R.raw.pet_lamb_alarm
        Pet.OWL -> R.raw.pet_owl_alarm
        Pet.HAMSTER -> R.raw.pet_hamster_alarm
    }

    fun taps(pet: Pet) = when (pet) {
        Pet.CAT -> listOf(R.raw.mrrp1, R.raw.mrrp2, R.raw.mrrp3)
        Pet.PUPPY -> listOf(R.raw.pet_puppy_tap1, R.raw.pet_puppy_tap2, R.raw.pet_puppy_tap3)
        Pet.CHICK -> listOf(R.raw.pet_chick_tap1, R.raw.pet_chick_tap2, R.raw.pet_chick_tap3)
        Pet.CANARY -> listOf(R.raw.pet_canary_tap1, R.raw.pet_canary_tap2, R.raw.pet_canary_tap3)
        Pet.LAMB -> listOf(R.raw.pet_lamb_tap1, R.raw.pet_lamb_tap2, R.raw.pet_lamb_tap3)
        Pet.OWL -> listOf(R.raw.pet_owl_tap1, R.raw.pet_owl_tap2, R.raw.pet_owl_tap3)
        Pet.HAMSTER -> listOf(R.raw.pet_hamster_tap1, R.raw.pet_hamster_tap2, R.raw.pet_hamster_tap3)
    }

    fun calm(pet: Pet) = when (pet) {
        Pet.CAT -> R.raw.purr
        Pet.PUPPY -> R.raw.pet_puppy_calm
        Pet.CHICK -> R.raw.pet_chick_calm
        Pet.CANARY -> R.raw.pet_canary_calm
        Pet.LAMB -> R.raw.pet_lamb_calm
        Pet.OWL -> R.raw.pet_owl_calm
        Pet.HAMSTER -> R.raw.pet_hamster_calm
    }
}

/**
 * The cat's voice outside an alarm: a short mrrp when it is tapped — three takes a
 * little apart in pitch, never the same twice running — and the purr while it is
 * stroked. Both play as sonification, so they follow the media volume and never
 * take the alarm's stream.
 */
object CatSounds {
    private lateinit var app: Context
    private var pool: SoundPool? = null
    /** Whose voice is loaded; another companion chosen means loading theirs. */
    private var voice: Pet? = null
    private var purrVoice: Pet? = null
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

    private fun current(): Pet = app.graph.companion.value

    private fun ensurePool(): SoundPool? {
        if (!::app.isInitialized) return null
        val pet = current()
        pool?.let { if (voice == pet) return it; it.release(); pool = null }
        return SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attributes).build().also { p ->
            PetVoices.taps(pet).forEachIndexed { i, res -> takes[i] = p.load(app, res, 1) }
            pool = p
            voice = pet
        }
    }

    /** One answer from `pet`, for hearing a companion before choosing it. */
    fun preview(pet: Pet) {
        if (!::app.isInitialized) return
        runCatching {
            MediaPlayer.create(app, PetVoices.taps(pet).first(), attributes, 0)?.apply {
                setVolume(0.7f, 0.7f)
                setOnCompletionListener { it.release() }
                start()
            }
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
        val pet = current()
        if (purrVoice != pet) { purr?.release(); purr = null; level = 0f }
        val player = purr ?: MediaPlayer.create(app, PetVoices.calm(pet), attributes, 0)?.apply { isLooping = true; setVolume(0f, 0f) }
        purr = player ?: return
        purrVoice = pet
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
