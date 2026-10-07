package uz.ata.dawnwick.missions

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sqrt
import kotlin.random.Random
import uz.ata.dawnwick.alarm.model.StrokePoint

/**
 * How alike two drawings are: both centred and scaled to the same size, drawn as
 * lines three cells thick on a 48×48 grid, and compared as intersection over union. Where it starts,
 * which way it goes and the order of the strokes make no difference.
 */
object DrawSimilarity {
    private const val GRID = 48

    /** Enough of a match to turn the alarm off. */
    const val THRESHOLD = 0.33

    fun score(reference: List<List<StrokePoint>>, candidate: List<List<StrokePoint>>): Double {
        if (reference.isEmpty() || candidate.isEmpty()) return 0.0
        val a = normalize(reference)
        val b = normalize(candidate)
        if (a.isEmpty() || b.isEmpty()) return 0.0
        return iou(rasterize(a), rasterize(b))
    }

    /** One centre and one scale for every stroke, so the shape keeps its proportions. */
    private fun normalize(strokes: List<List<StrokePoint>>): List<List<StrokePoint>> {
        val all = strokes.flatten()
        if (all.size <= 1) return strokes
        val cx = all.sumOf { it.x } / all.size
        val cy = all.sumOf { it.y } / all.size
        val maxDist = all.maxOf { hypot(it.x - cx, it.y - cy) }
        if (maxDist <= 0) return strokes
        return strokes.map { s -> s.map { StrokePoint((it.x - cx) / maxDist, (it.y - cy) / maxDist) } }
    }

    /** Each stroke as an unbroken line: the gaps between touch samples filled in. */
    private fun rasterize(strokes: List<List<StrokePoint>>): BooleanArray {
        val grid = BooleanArray(GRID * GRID)
        fun paint(x: Double, y: Double) {
            val px = (((x + 1.0) / 2.0) * (GRID - 1)).toInt().coerceIn(0, GRID - 1)
            val py = (((y + 1.0) / 2.0) * (GRID - 1)).toInt().coerceIn(0, GRID - 1)
            // Lines a few cells thick: a finger at 7 am wobbles, and with one-cell
            // lines the same triangle drawn a little taller scored 0.07.
            for (dy in -1..1) for (dx in -1..1) {
                val gx = px + dx
                val gy = py + dy
                if (gx in 0 until GRID && gy in 0 until GRID) grid[gy * GRID + gx] = true
            }
        }
        val step = 2.0 / GRID
        for (stroke in strokes) {
            stroke.forEachIndexed { i, p ->
                paint(p.x, p.y)
                val next = stroke.getOrNull(i + 1) ?: return@forEachIndexed
                val dx = next.x - p.x
                val dy = next.y - p.y
                val dist = sqrt(dx * dx + dy * dy)
                if (dist <= 0) return@forEachIndexed
                val steps = max(1, (dist / step).toInt())
                for (s in 1 until steps) {
                    val t = s.toDouble() / steps
                    paint(p.x + dx * t, p.y + dy * t)
                }
            }
        }
        return grid
    }

    private fun iou(a: BooleanArray, b: BooleanArray): Double {
        var inter = 0
        var union = 0
        for (i in a.indices) {
            if (a[i] && b[i]) inter++
            if (a[i] || b[i]) union++
        }
        return if (union > 0) inter.toDouble() / union else 0.0
    }
}

/**
 * "Catch the cat" as a mission: catch it so many times and the alarm is off. No
 * score and no clock of its own — the host's five minutes are the only limit — and
 * the cat is slower than in the game, for someone who is not awake yet. A tap that
 * misses only startles it into jumping. Times are milliseconds.
 */
class CatchMission(required: Int, private val random: Random = Random.Default) {
    val required = max(1, required)
    var caught = 0; private set
    /** Where the cat sits, 0–1 in both directions. */
    var x = 0.5; private set
    var y = 0.5; private set
    /** Counts every jump, so the view can animate each one. */
    var jumps = 0; private set
    var jumpsAt: Long? = null; private set
    var startledUntil: Long? = null; private set
    var started = false; private set

    val isDone get() = caught >= required

    /** Generous at first, a little quicker with each catch. */
    val stayMillis: Long get() = (max(1.0, 1.9 - caught * 0.08) * 1000).toLong()

    fun isStartled(now: Long) = startledUntil?.let { now < it } ?: false

    fun start(now: Long) {
        if (started) return
        started = true
        jumpsAt = now + stayMillis
    }

    /** The cat was tapped. Returns whether it counted. */
    fun catchCat(now: Long): Boolean {
        if (!started || isDone) return false
        caught++
        startledUntil = null
        if (isDone) jumpsAt = null else jump(now)
        return true
    }

    fun miss(now: Long) {
        if (!started || isDone) return
        startledUntil = now + STARTLE_MILLIS
        jump(now)
    }

    /** Moves time on: the cat jumps when its stay is up. */
    fun tick(now: Long) {
        val at = jumpsAt ?: return
        if (!started || isDone || now < at) return
        jump(now)
    }

    /** Somewhere new, well away from where it was. */
    private fun jump(now: Long) {
        var nx = x
        var ny = y
        for (attempt in 0 until 12) {
            nx = 0.1 + random.nextDouble() * 0.8
            ny = 0.12 + random.nextDouble() * 0.76
            if (hypot(nx - x, ny - y) > 0.32) break
        }
        x = nx
        y = ny
        jumps++
        jumpsAt = now + stayMillis
    }

    companion object {
        const val STARTLE_MILLIS = 700L
    }
}

/**
 * Jumps from the accelerometer: total acceleration past 3.2 g (about 2.2 g above
 * gravity) — more than a quick lift of the phone — at most one per 0.8 s.
 */
class JumpDetector(private val thresholdG: Double = 3.2, private val cooldownMillis: Long = 800) {
    private var last = Long.MIN_VALUE / 2

    /** One reading in g; true when it is a new jump. */
    fun onReading(g: Double, now: Long): Boolean {
        if (g <= thresholdG || now - last <= cooldownMillis) return false
        last = now
        return true
    }
}
