package uz.ata.dawnwick.games

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random
import uz.ata.dawnwick.core.KeyValueStore

/** A point in a game's own space. */
data class Pt(val x: Double, val y: Double)

/** Seconds from `from` to `to`, both in milliseconds. */
private fun since(from: Long, to: Long) = (to - from) / 1000.0
private fun Long.after(seconds: Double) = this + (seconds * 1000).toLong()

/**
 * "Catch the cat": thirty seconds, a cat that will not sit still. Tap it before it
 * jumps away; every catch makes the next jump come sooner. Five catches in a row
 * start a combo that is worth double. A tap that misses gives the cat a fright: it
 * bolts somewhere else.
 *
 * The rules only — no views, no clock of its own. The screen calls `tick` and reports
 * taps; tests drive it with fixed times and a seeded generator. Times are in ms.
 */
class CatchGame(private val random: Random = Random.Default, private val slow: Boolean = false) {
    enum class Phase { READY, PLAYING, OVER }

    data class Caught(val point: Pt, val points: Int, val index: Int)

    var phase = Phase.READY; private set
    var score = 0; private set
    var combo = 0; private set
    var bestCombo = 0; private set
    var catches = 0; private set
    /** Where the cat sits, 0–1 in both directions of the play area. */
    var position = Pt(0.5, 0.5); private set
    /** Counts every jump, so the view can animate each one. */
    var jumps = 0; private set
    var startledUntil: Long? = null; private set
    var lastCatch: Caught? = null; private set
    var startedAt: Long? = null; private set
    var jumpsAt: Long? = null; private set

    /** How long the cat stays put: generous at first, quick by the end. */
    val stayDuration get() = if (slow) 60.0 else max(0.55, 1.5 - catches * 0.045)
    val roundLength get() = if (slow) 300.0 else ROUND_LENGTH
    val isOnCombo get() = combo >= COMBO_THRESHOLD

    fun isStartled(now: Long) = startledUntil?.let { now < it } ?: false

    fun remaining(now: Long): Double = startedAt?.let { max(0.0, roundLength - since(it, now)) } ?: roundLength

    fun start(now: Long) {
        phase = Phase.PLAYING
        score = 0; combo = 0; bestCombo = 0; catches = 0
        lastCatch = null; startledUntil = null
        startedAt = now
        position = Pt(0.5, 0.5)
        jumpsAt = now.after(stayDuration)
    }

    /** The cat was tapped. Returns the points it earned. */
    fun catchCat(now: Long): Int {
        if (phase != Phase.PLAYING || remaining(now) <= 0) return 0
        combo += 1
        catches += 1
        startledUntil = null
        bestCombo = max(bestCombo, combo)
        val points = if (combo > COMBO_THRESHOLD) 2 else 1
        score += points
        lastCatch = Caught(position, points, catches)
        jump(now)
        return points
    }

    /** A tap that found no cat: the combo is gone, and the cat, startled, bolts. */
    fun miss(now: Long) {
        if (phase != Phase.PLAYING || remaining(now) <= 0) return
        combo = 0
        startledUntil = now.after(STARTLE_LENGTH)
        jump(now)
    }

    fun tick(now: Long) {
        if (phase != Phase.PLAYING) return
        if (remaining(now) <= 0) { phase = Phase.OVER; jumpsAt = null; return }
        val at = jumpsAt
        if (at != null && now >= at) { combo = 0; jump(now) }
    }

    /** Somewhere new, well away from where it was, and never under the screen's edges. */
    private fun jump(now: Long) {
        var next = position
        for (i in 0 until 12) {
            next = Pt(0.12 + random.nextDouble() * 0.76, 0.12 + random.nextDouble() * 0.76)
            if (hypot(next.x - position.x, next.y - position.y) > 0.32) break
        }
        position = next
        jumps += 1
        jumpsAt = now.after(stayDuration)
    }

    companion object {
        const val ROUND_LENGTH = 30.0
        const val COMBO_THRESHOLD = 5
        const val STARTLE_LENGTH = 0.7
    }
}

/** The best score of each game, kept on this device. */
class GameRecord(private val store: KeyValueStore, private val key: String) {
    fun best() = store.getInt(key, 0)

    /** Stores `score` if it beats the record. Returns whether it did. */
    fun submit(score: Int): Boolean {
        if (score <= best()) return false
        store.putInt(key, score)
        return true
    }

    companion object {
        fun catch(store: KeyValueStore) = GameRecord(store, "game.catch.best")
        fun laser(store: KeyValueStore) = GameRecord(store, "game.laser.best")
        fun boxes(store: KeyValueStore) = GameRecord(store, "game.box.best")
    }
}

/**
 * "Laser": a finger on the board is a laser dot; the cat runs after it, drops into a
 * crouch when it is close, and pounces at where the dot is heading. Every pounce that
 * lands on nothing is a point; three in a row and each counts double. A pounce that
 * lands on the dot is the cat's: no point, the run is over.
 *
 * Lift the finger and the dot is gone: the cat sits and looks for it. The cat gets
 * quicker, crouches for less and reaches further with every point. The board is in
 * dp; the screen sets its size, calls `tick` and reports the finger.
 */
class LaserGame(private val random: Random = Random.Default, private val slow: Boolean = false) {
    enum class Phase { READY, PLAYING, OVER }

    sealed interface Cat {
        data object Waiting : Cat
        data object Chasing : Cat
        data class Crouching(val until: Long) : Cat
        data class Pouncing(val from: Pt, val to: Pt, val start: Long) : Cat
        data class Landed(val caught: Boolean, val until: Long) : Cat
    }

    data class Dodge(val point: Pt, val points: Int, val index: Int)

    var phase = Phase.READY; private set
    var cat: Cat = Cat.Waiting; private set
    var score = 0; private set
    var combo = 0; private set
    var bestCombo = 0; private set
    var dodges = 0; private set
    var caught = 0; private set
    var position = Pt(0.0, 0.0); private set
    /** −1 facing left, 1 facing right. */
    var facing = -1.0; private set
    var dot: Pt? = null; private set
    var dotVelocity = Pt(0.0, 0.0); private set
    var pounces = 0; private set
    var lastDodge: Dodge? = null; private set
    var startedAt: Long? = null; private set

    private var boardW = 360.0
    private var boardH = 560.0
    private var lastMove: Pair<Pt, Long>? = null
    private var lastTick: Long? = null

    val runSpeed get() = min(520.0, 300 + score * 9.0)
    val catchRadius get() = min(78.0, 50 + score * 1.2)

    private fun crouchLength(): Double {
        if (slow) return 3.0
        val longest = max(0.42, 0.85 - score * 0.018)
        return longest * 0.55 + random.nextDouble() * longest * 0.45
    }

    private val lead get() = min(FLIGHT, 0.12 + score * 0.012)

    val roundLength get() = if (slow) 300.0 else ROUND_LENGTH
    fun remaining(now: Long): Double = startedAt?.let { max(0.0, roundLength - since(it, now)) } ?: roundLength

    val isOnCombo get() = combo >= COMBO_THRESHOLD

    val strikePoint get() = strike(position)

    /** Where the cat is drawn at `now`, and how high off the floor, 0–1. */
    fun catPosition(now: Long): Pair<Pt, Double> {
        val c = cat as? Cat.Pouncing ?: return position to 0.0
        val p = (since(c.start, now) / FLIGHT).coerceIn(0.0, 1.0)
        return Pt(c.from.x + (c.to.x - c.from.x) * p, c.from.y + (c.to.y - c.from.y) * p) to sin(PI * p)
    }

    fun setBoard(w: Double, h: Double) {
        if (w <= HALF_LENGTH * 2 || h <= HALF_HEIGHT * 2) return
        val fresh = phase != Phase.PLAYING && position == Pt(0.0, 0.0)
        boardW = w; boardH = h
        if (fresh) position = Pt(w / 2, h * 0.62)
        position = clamped(position)
    }

    fun start(now: Long) {
        phase = Phase.PLAYING
        cat = Cat.Waiting
        score = 0; combo = 0; bestCombo = 0; dodges = 0; caught = 0
        lastDodge = null; dot = null; dotVelocity = Pt(0.0, 0.0); lastMove = null
        startedAt = now; lastTick = now
        position = Pt(boardW / 2, boardH * 0.62)
    }

    /** The finger is on the board at `point`. */
    fun pointDot(point: Pt, now: Long) {
        if (phase != Phase.PLAYING) return
        val p = Pt(point.x.coerceIn(0.0, boardW), point.y.coerceIn(0.0, boardH))
        val last = lastMove
        if (last != null) {
            val dt = since(last.second, now)
            if (dt > 0.004) {
                val vx = (p.x - last.first.x) / dt
                val vy = (p.y - last.first.y) / dt
                val k = 0.45
                dotVelocity = Pt(dotVelocity.x + (vx - dotVelocity.x) * k, dotVelocity.y + (vy - dotVelocity.y) * k)
                lastMove = p to now
            }
        } else {
            dotVelocity = Pt(0.0, 0.0)
            lastMove = p to now
        }
        dot = p
        if (cat == Cat.Waiting) cat = Cat.Chasing
    }

    fun liftDot() {
        dot = null
        dotVelocity = Pt(0.0, 0.0)
        lastMove = null
        if (cat == Cat.Chasing || cat is Cat.Crouching) cat = Cat.Waiting
    }

    fun tick(now: Long) {
        if (phase != Phase.PLAYING) return
        val dt = since(lastTick ?: now, now).coerceIn(0.0, 0.1)
        lastTick = now
        if (remaining(now) <= 0) {
            if (cat is Cat.Pouncing) land(now)
            phase = Phase.OVER
            return
        }
        lastMove?.let { if (since(it.second, now) > 0.08) dotVelocity = Pt(0.0, 0.0) }

        when (val c = cat) {
            Cat.Waiting -> Unit
            Cat.Chasing -> {
                val d = dot ?: run { cat = Cat.Waiting; return }
                face(d)
                val paws = strikePoint
                if (hypot(d.x - paws.x, d.y - paws.y) < POUNCE_RANGE) {
                    cat = Cat.Crouching(now.after(crouchLength()))
                } else {
                    val goal = middle(d)
                    val dx = goal.x - position.x
                    val dy = goal.y - position.y
                    val distance = hypot(dx, dy)
                    if (distance > 0.5) {
                        val step = min(distance, runSpeed * dt)
                        position = clamped(Pt(position.x + dx / distance * step, position.y + dy / distance * step))
                    }
                }
            }
            is Cat.Crouching -> {
                val d = dot ?: run { cat = Cat.Waiting; return }
                face(d)
                if (now >= c.until) spring(now, d)
            }
            is Cat.Pouncing -> if (since(c.start, now) >= FLIGHT) land(now)
            is Cat.Landed -> if (now >= c.until) cat = if (dot == null) Cat.Waiting else Cat.Chasing
        }
    }

    private fun spring(now: Long, d: Pt) {
        val aim = Pt(d.x + dotVelocity.x * lead, d.y + dotVelocity.y * lead)
        val paws = strikePoint
        if (hypot(aim.x - paws.x, aim.y - paws.y) > LONGEST_POUNCE) { cat = Cat.Chasing; return }
        val landing = clamped(middle(aim))
        val reached = strike(landing)
        if (hypot(reached.x - aim.x, reached.y - aim.y) >= 12) { cat = Cat.Crouching(now.after(0.25)); return }
        cat = Cat.Pouncing(position, landing, now)
        pounces += 1
    }

    private fun land(now: Long) {
        val c = cat as? Cat.Pouncing ?: return
        position = c.to
        val paws = strikePoint
        val d = dot
        if (d != null && hypot(d.x - paws.x, d.y - paws.y) <= catchRadius) {
            caught += 1
            combo = 0
            cat = Cat.Landed(true, now.after(0.9))
            return
        }
        cat = Cat.Landed(false, now.after(0.35))
        if (d == null) return
        combo += 1
        dodges += 1
        bestCombo = max(bestCombo, combo)
        val points = if (combo > COMBO_THRESHOLD) 2 else 1
        score += points
        lastDodge = Dodge(paws, points, dodges)
    }

    private fun face(d: Pt) {
        val dx = d.x - position.x
        if (abs(dx) > 24) facing = if (dx < 0) -1.0 else 1.0
    }

    private fun strike(m: Pt) = Pt(m.x + PAWS_DX * -facing, m.y + PAWS_DY)
    private fun middle(paws: Pt) = Pt(paws.x - PAWS_DX * -facing, paws.y - PAWS_DY)
    private fun clamped(p: Pt) = Pt(p.x.coerceIn(HALF_LENGTH, boardW - HALF_LENGTH), p.y.coerceIn(HALF_HEIGHT, boardH - HALF_HEIGHT))

    companion object {
        const val ROUND_LENGTH = 30.0
        const val COMBO_THRESHOLD = 3
        const val FLIGHT = 0.3
        const val POUNCE_RANGE = 170.0
        const val LONGEST_POUNCE = 230.0
        const val HALF_LENGTH = 75.0
        const val HALF_HEIGHT = 46.0
        const val PAWS_DX = -56.0
        const val PAWS_DY = 34.0
    }
}

/**
 * "Which box?": the cat sits in one of a row of boxes, ducks down, the lids close and
 * the boxes change places; tap the one it is in. Every find makes the next round
 * quicker and longer, and in time adds a box. Three wrong boxes and the game is over.
 * A round is a script played from timestamps.
 */
class BoxGame(private val random: Random = Random.Default, private val slow: Boolean = false) {
    enum class Phase { READY, PLAYING, OVER }

    sealed interface Step {
        data class Showing(val until: Long) : Step
        data class Hiding(val until: Long) : Step
        data class Shuffling(val start: Long) : Step
        data object Guessing : Step
        data class Revealing(val chosen: Int, val until: Long) : Step
    }

    data class Swap(val a: Int, val b: Int)

    /** One box's place: fractional mid-swap, and `arc` −1…1, how far it swung out of line. */
    data class Spot(val place: Double, val arc: Double)

    var phase = Phase.READY; private set
    var step: Step = Step.Guessing; private set
    var score = 0; private set
    var lives = STARTING_LIVES; private set
    var round = 0; private set
    var count = 3; private set
    /** `places[box]` is its place in the row, 0 at the left. */
    var places = listOf(0, 1, 2); private set
    var catBox = 0; private set
    var swaps: List<Swap> = emptyList(); private set
    var swapLength = 0.5; private set
    private var startPlaces = listOf(0, 1, 2)
    var lastGuessRight = false; private set

    val shuffleLength get() = swaps.size * swapLength
    val catPlace get() = places[catBox]

    fun start(now: Long) {
        phase = Phase.PLAYING
        score = 0
        lives = STARTING_LIVES
        round = 0
        nextRound(now)
    }

    /** The tap. Whether it found the cat, or null when it is not the time. */
    fun choose(box: Int, now: Long): Boolean? {
        if (phase != Phase.PLAYING || step != Step.Guessing || box !in 0 until count) return null
        val right = box == catBox
        lastGuessRight = right
        if (right) score += 1 else lives -= 1
        step = Step.Revealing(box, now.after(if (right) FOUND_LENGTH else MISSED_LENGTH))
        return right
    }

    fun tick(now: Long) {
        if (phase != Phase.PLAYING) return
        when (val s = step) {
            is Step.Showing -> if (now >= s.until) step = Step.Hiding(now.after(HIDE_LENGTH))
            is Step.Hiding -> if (now >= s.until) step = Step.Shuffling(now)
            is Step.Shuffling -> if (since(s.start, now) >= shuffleLength) {
                places = apply(swaps, startPlaces)
                step = Step.Guessing
            }
            Step.Guessing -> Unit
            is Step.Revealing -> if (now >= s.until) { if (lives <= 0) phase = Phase.OVER else nextRound(now) }
        }
    }

    fun layout(now: Long): List<Spot> {
        val s = step
        if (s !is Step.Shuffling || swapLength <= 0) return places.map { Spot(it.toDouble(), 0.0) }
        val elapsed = max(0.0, since(s.start, now))
        val done = min(swaps.size, (elapsed / swapLength).toInt())
        val settled = apply(swaps.take(done), startPlaces)
        if (done >= swaps.size) return settled.map { Spot(it.toDouble(), 0.0) }
        val swap = swaps[done]
        val p = (elapsed - done * swapLength) / swapLength
        val eased = 0.5 - 0.5 * cos(PI * p)
        val swing = sin(PI * p)
        return settled.map { place ->
            when (place) {
                swap.a -> Spot(swap.a + (swap.b - swap.a) * eased, swing)
                swap.b -> Spot(swap.b + (swap.a - swap.b) * eased, -swing)
                else -> Spot(place.toDouble(), 0.0)
            }
        }
    }

    /** Which swap is under way, counting from 1; 0 when none is. */
    fun swapNumber(now: Long): Int {
        val s = step as? Step.Shuffling ?: return 0
        if (swapLength <= 0) return 0
        val done = (max(0.0, since(s.start, now)) / swapLength).toInt()
        return if (done < swaps.size) done + 1 else 0
    }

    private fun nextRound(now: Long) {
        round += 1
        count = boxes(score)
        places = (0 until count).toList()
        startPlaces = places
        catBox = random.nextInt(count)
        swapLength = if (slow) 1.5 else swapLength(score)
        swaps = makeSwaps(swapCount(score))
        step = Step.Showing(now.after(SHOW_LENGTH))
    }

    /** Random pairs of places, the cat's box in at least every other one, never the same pair twice running. */
    private fun makeSwaps(n: Int): List<Swap> {
        val result = mutableListOf<Swap>()
        var catAt = places[catBox]
        for (i in 0 until n) {
            var swap: Swap
            do {
                val a = if (i % 2 == 0 || random.nextBoolean()) catAt else random.nextInt(count)
                var b = random.nextInt(count - 1)
                if (b >= a) b += 1
                swap = Swap(min(a, b), max(a, b))
            } while (swap == result.lastOrNull())
            if (catAt == swap.a) catAt = swap.b else if (catAt == swap.b) catAt = swap.a
            result += swap
        }
        return result
    }

    companion object {
        const val STARTING_LIVES = 3
        const val SHOW_LENGTH = 1.1
        const val HIDE_LENGTH = 0.55
        const val FOUND_LENGTH = 1.2
        const val MISSED_LENGTH = 1.7

        fun boxes(score: Int) = if (score < 4) 3 else if (score < 9) 4 else 5
        fun swapCount(score: Int) = min(14, 4 + score / 2)
        fun swapLength(score: Int) = max(0.2, 0.5 - score * 0.022)

        fun apply(swaps: List<Swap>, places: List<Int>): List<Int> {
            val p = places.toMutableList()
            for (s in swaps) for (i in p.indices) {
                if (p[i] == s.a) p[i] = s.b else if (p[i] == s.b) p[i] = s.a
            }
            return p
        }
    }
}
