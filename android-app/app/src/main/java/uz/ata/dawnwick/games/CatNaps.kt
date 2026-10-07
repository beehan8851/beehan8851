package uz.ata.dawnwick.games

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.core.KeyValueStore

/**
 * One Cat Naps puzzle: a square of cells cut into as many cushions as there are rows.
 * A cat goes on every cushion so that each row, each column and each cushion has
 * exactly one, and no two cats touch, not even at a corner. Each puzzle has one answer.
 *
 * Made from a seed, never stored: the same day makes the same puzzle on every phone —
 * on iOS too, which is why the random numbers are our own (`NapRandom`) and every
 * step below draws them in the same order as the Swift original.
 */
data class CatNapPuzzle(val size: Int, val regions: List<Int>, val solution: List<Int>) {
    fun region(row: Int, column: Int) = regions[row * size + column]
    fun isCat(row: Int, column: Int) = solution[row] == column

    /** The kinds of step a person takes, easiest first. */
    enum class Reasoning { SINGLE, LOOKAHEAD, GROUPS }

    fun canBeReasoned() = hardestStep() != null

    /** The hardest kind of step solving it takes; null when it needs a guess. */
    fun hardestStep(): Reasoning? {
        var hardest = Reasoning.SINGLE
        val cellCount = size * size
        val free = BooleanArray(cellCount) { true }
        val cats = mutableListOf<Int>()
        val lines = mutableListOf<List<Int>>()
        for (row in 0 until size) lines += (0 until size).map { row * size + it }
        for (column in 0 until size) lines += (0 until size).map { it * size + column }
        for (region in 0 until size) lines += (0 until cellCount).filter { regions[it] == region }

        fun blocked(cell: Int): List<Int> {
            val row = cell / size
            val column = cell % size
            return (0 until cellCount).filter {
                it / size == row || it % size == column || regions[it] == regions[cell] ||
                    (abs(it / size - row) <= 1 && abs(it % size - column) <= 1)
            }
        }
        fun hasCat(line: List<Int>) = line.any { it in cats }

        while (cats.size < size) {
            var step = false
            for (line in lines) {
                if (hasCat(line)) continue
                val open = line.filter { free[it] }
                if (open.isEmpty()) return null
                if (open.size == 1) {
                    cats += open[0]
                    for (cell in blocked(open[0])) free[cell] = false
                    step = true
                    break
                }
            }
            if (step) continue

            for (cell in 0 until cellCount) {
                if (!free[cell]) continue
                val gone = blocked(cell).toSet()
                val starves = lines.any { line -> cell !in line && !hasCat(line) && line.none { free[it] && it !in gone } }
                if (starves) {
                    free[cell] = false
                    step = true
                    if (hardest < Reasoning.LOOKAHEAD) hardest = Reasoning.LOOKAHEAD
                    break
                }
            }
            if (step) continue

            val open = (0 until size).filter { region -> cats.none { regions[it] == region } }
            search@ for (mask in 1 until (1 shl open.size)) {
                if (Integer.bitCount(mask) >= open.size) continue
                val group = open.indices.filter { mask and (1 shl it) != 0 }.map { open[it] }.toSet()
                val cells = (0 until cellCount).filter { free[it] && regions[it] in group }
                for (byRow in listOf(true, false)) {
                    val taken = cells.map { if (byRow) it / size else it % size }.toSet()
                    if (taken.size != group.size) continue
                    val others = (0 until cellCount).filter {
                        free[it] && regions[it] !in group && (if (byRow) it / size else it % size) in taken
                    }
                    if (others.isNotEmpty()) {
                        for (cell in others) free[cell] = false
                        step = true
                        hardest = Reasoning.GROUPS
                        break@search
                    }
                }
            }
            if (!step) return null
        }
        return hardest
    }

    companion object {
        /** The puzzle for `seed`: one answer, reached by reasoning alone, needing no harder step than `steps` allows. */
        fun generate(size: Int, seed: ULong, steps: ClosedRange<Reasoning> = Reasoning.SINGLE..Reasoning.GROUPS): CatNapPuzzle {
            val random = NapRandom(seed)
            while (true) {
                val cats = placeCats(size, random)
                val regions = growCushions(size, cats, random)
                if (!makeUnique(size, regions, cats, random)) continue
                val puzzle = CatNapPuzzle(size, regions.toList(), cats)
                val hardest = puzzle.hardestStep()
                if (hardest != null && hardest in steps) return puzzle
            }
        }

        private fun placeCats(size: Int, random: NapRandom): List<Int> {
            val columns = mutableListOf<Int>()
            val used = mutableSetOf<Int>()
            fun place(row: Int): Boolean {
                if (row == size) return true
                for (column in random.shuffled((0 until size).toList())) {
                    if (column in used) continue
                    val above = columns.lastOrNull()
                    if (above != null && abs(above - column) < 2) continue
                    columns += column
                    used += column
                    if (place(row + 1)) return true
                    columns.removeAt(columns.lastIndex)
                    used -= column
                }
                return false
            }
            place(0)
            return columns
        }

        private fun growCushions(size: Int, cats: List<Int>, random: NapRandom): IntArray {
            val regions = IntArray(size * size) { -1 }
            cats.forEachIndexed { row, column -> regions[row * size + column] = row }
            val appetite = (0 until size).map { 1 + random.int(6) }
            val total = appetite.sum()
            var left = size * size - size
            while (left > 0) {
                var pick = random.int(total)
                var region = 0
                while (pick >= appetite[region]) { pick -= appetite[region]; region += 1 }
                val edge = mutableListOf<Int>()
                for (cell in 0 until size * size) {
                    if (regions[cell] != -1) continue
                    if (neighbours(cell, size).any { regions[it] == region }) edge += cell
                }
                if (edge.isEmpty()) continue
                regions[edge[random.int(edge.size)]] = region
                left -= 1
            }
            return regions
        }

        private fun makeUnique(size: Int, regions: IntArray, cats: List<Int>, random: NapRandom): Boolean {
            val catCells = cats.mapIndexed { row, column -> row * size + column }.toSet()
            repeat(size * size * 2) {
                val other = solutions(size, regions.toList(), 2).firstOrNull { it != cats } ?: return true
                val rows = random.shuffled((0 until size).filter { other[it] != cats[it] })
                var moved = false
                for (row in rows) {
                    val cell = row * size + other[row]
                    if (cell in catCells) continue
                    val from = regions[cell]
                    val choices = neighbours(cell, size).map { regions[it] }.toSet() - from
                    for (to in random.shuffled(choices.sorted())) {
                        regions[cell] = to
                        if (isConnected(from, regions.toList(), size)) { moved = true; break }
                        regions[cell] = from
                    }
                    if (moved) break
                }
                if (!moved) return false
            }
            return false
        }

        /** Every answer to a board, up to `limit`. */
        fun solutions(size: Int, regions: List<Int>, limit: Int = 2): List<List<Int>> {
            val found = mutableListOf<List<Int>>()
            val columns = mutableListOf<Int>()
            var usedColumns = 0
            var usedRegions = 0
            fun place(row: Int) {
                if (found.size >= limit) return
                if (row == size) { found += columns.toList(); return }
                for (column in 0 until size) {
                    val region = regions[row * size + column]
                    if (usedColumns and (1 shl column) != 0 || usedRegions and (1 shl region) != 0) continue
                    val above = columns.lastOrNull()
                    if (above != null && abs(above - column) < 2) continue
                    columns += column
                    usedColumns = usedColumns or (1 shl column)
                    usedRegions = usedRegions or (1 shl region)
                    place(row + 1)
                    columns.removeAt(columns.lastIndex)
                    usedColumns = usedColumns and (1 shl column).inv()
                    usedRegions = usedRegions and (1 shl region).inv()
                }
            }
            place(0)
            return found
        }

        fun neighbours(cell: Int, size: Int): List<Int> {
            val row = cell / size
            val column = cell % size
            val result = mutableListOf<Int>()
            if (row > 0) result += cell - size
            if (row < size - 1) result += cell + size
            if (column > 0) result += cell - 1
            if (column < size - 1) result += cell + 1
            return result
        }

        fun isConnected(region: Int, regions: List<Int>, size: Int): Boolean {
            val cells = regions.indices.filter { regions[it] == region }
            val first = cells.firstOrNull() ?: return false
            val seen = mutableSetOf(first)
            val queue = ArrayDeque(listOf(first))
            while (queue.isNotEmpty()) {
                val cell = queue.removeLast()
                for (next in neighbours(cell, size)) {
                    if (regions[next] == region && next !in seen) { seen += next; queue += next }
                }
            }
            return seen.size == cells.size
        }
    }
}

/** SplitMix64: small, fast, and the same numbers everywhere for the same seed. */
class NapRandom(seed: ULong) {
    private var state = seed

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    /** 0 until `bound`: the high half of the 128-bit product, as Swift's `multipliedFullWidth`. */
    fun int(bound: Int): Int = mulHigh(next(), bound.toULong()).toInt()

    fun <T> shuffled(items: List<T>): List<T> {
        val list = items.toMutableList()
        if (list.size <= 1) return list
        for (i in list.size - 1 downTo 1) {
            val j = int(i + 1)
            val t = list[i]; list[i] = list[j]; list[j] = t
        }
        return list
    }

    private fun mulHigh(a: ULong, b: ULong): ULong {
        val aLo = a and 0xFFFFFFFFuL
        val aHi = a shr 32
        val bLo = b and 0xFFFFFFFFuL
        val bHi = b shr 32
        val lolo = aLo * bLo
        val hilo = aHi * bLo
        val lohi = aLo * bHi
        val hihi = aHi * bHi
        val cross = (lolo shr 32) + (hilo and 0xFFFFFFFFuL) + lohi
        return hihi + (hilo shr 32) + (cross shr 32)
    }
}

/** How hard a puzzle is: a bigger board, and harder steps to solve it. */
enum class CatNapLevel(val size: Int, val steps: ClosedRange<CatNapPuzzle.Reasoning>) {
    EASY(5, CatNapPuzzle.Reasoning.SINGLE..CatNapPuzzle.Reasoning.SINGLE),
    MEDIUM(7, CatNapPuzzle.Reasoning.SINGLE..CatNapPuzzle.Reasoning.LOOKAHEAD),
    HARD(8, CatNapPuzzle.Reasoning.GROUPS..CatNapPuzzle.Reasoning.GROUPS);

    val next get() = entries.getOrNull(ordinal + 1)
}

/** Which puzzles are whose day. Puzzle 1 was 1 October 2026; three a day since, the same for everyone. */
object CatNapDay {
    val FIRST_DAY: LocalDate = LocalDate.of(2026, 10, 1)
    /** The number an unlimited puzzle goes by: it belongs to no day. */
    const val UNLIMITED = 0

    fun number(date: LocalDate = LocalDate.now()) = max(1, ChronoUnit.DAYS.between(FIRST_DAY, date).toInt() + 1)
    fun date(number: Int): LocalDate = FIRST_DAY.plusDays((number - 1).toLong())

    fun puzzle(number: Int, level: CatNapLevel): CatNapPuzzle {
        val day = number.toLong().toULong() * 0x2545F4914F6CDD1DuL
        val seed = day xor 0xCA700005EEDuL xor ((level.ordinal + 1).toULong() * 0x9E3779B97F4A7C15uL)
        return CatNapPuzzle.generate(level.size, seed, level.steps)
    }

    fun puzzle(seed: ULong, level: CatNapLevel) = CatNapPuzzle.generate(level.size, seed, level.steps)
}

/** A board left half done, to come back to. */
@Serializable
data class CatNapProgress(val number: Int, val level: Int, val cells: List<Int>, val seconds: Double, val hints: Int)

/**
 * A game of Cat Naps under way: what is on each cell, the clock, and whether every cat
 * is asleep. A cat put too close to another wakes up, and so does the one it woke.
 */
class CatNapGame(val number: Int, val level: CatNapLevel, val puzzle: CatNapPuzzle, saved: CatNapProgress? = null) {
    enum class Cell { EMPTY, MARK, CAT }

    var cells: List<Cell>; private set
    var hints = 0; private set
    var solved = false; private set
    var placedAt: Map<Int, Long> = emptyMap(); private set
    var clashing: Set<Int> = emptySet(); private set
    var awake: Set<Int> = emptySet(); private set

    private val history = mutableListOf<List<Cell>>()
    private var banked: Double
    private var runningSince: Long? = null

    val size get() = puzzle.size
    val canUndo get() = history.isNotEmpty() && !solved
    val catCount get() = cells.count { it == Cell.CAT }
    val isUntouched get() = cells.all { it == Cell.EMPTY }

    init {
        val count = puzzle.size * puzzle.size
        if (saved != null && saved.number == number && saved.level == level.ordinal && saved.cells.size == count) {
            cells = saved.cells.map { Cell.entries.getOrElse(it) { Cell.EMPTY } }
            banked = saved.seconds
            hints = saved.hints
        } else {
            cells = List(count) { Cell.EMPTY }
            banked = 0.0
        }
        refresh()
    }

    fun elapsed(now: Long) = banked + (runningSince?.let { (now - it) / 1000.0 } ?: 0.0)

    fun resume(now: Long) { if (runningSince == null && !solved) runningSince = now }

    fun pause(now: Long) {
        val since = runningSince ?: return
        banked += (now - since) / 1000.0
        runningSince = null
    }

    /** A tap: empty, then ruled out, then a cat, then empty again. */
    fun tap(index: Int, now: Long): Cell {
        if (solved || index !in cells.indices) return cells.getOrElse(index) { Cell.EMPTY }
        history += cells
        val next = when (cells[index]) { Cell.EMPTY -> Cell.MARK; Cell.MARK -> Cell.CAT; Cell.CAT -> Cell.EMPTY }
        set(index, next, now)
        return next
    }

    fun beginStroke() { if (!solved) history += cells }

    fun paint(index: Int, cell: Cell, now: Long) {
        if (solved || cell == Cell.CAT || index !in cells.indices || cells[index] == Cell.CAT || cells[index] == cell) return
        set(index, cell, now)
    }

    fun undo() {
        if (solved || history.isEmpty()) return
        cells = history.removeAt(history.lastIndex)
        refresh()
    }

    fun clear() {
        if (solved || isUntouched) return
        history += cells
        cells = List(cells.size) { Cell.EMPTY }
        placedAt = emptyMap()
        refresh()
    }

    /** Wakes a cat that is in the wrong place, or, if none is, puts one where it belongs. */
    fun hint(now: Long): Int? {
        if (solved) return null
        val n = size
        val wrong = cells.indices.firstOrNull { cells[it] == Cell.CAT && !puzzle.isCat(it / n, it % n) }
        val (target, cell) = if (wrong != null) wrong to Cell.MARK else {
            val row = (0 until n).firstOrNull { cells[it * n + puzzle.solution[it]] != Cell.CAT } ?: return null
            (row * n + puzzle.solution[row]) to Cell.CAT
        }
        history += cells
        hints += 1
        set(target, cell, now)
        return target
    }

    private fun set(index: Int, cell: Cell, now: Long) {
        cells = cells.toMutableList().also { it[index] = cell }
        placedAt = if (cell == Cell.CAT) placedAt + (index to now) else placedAt - index
        refresh()
        if (catCount == size && clashing.isEmpty()) {
            pause(now)
            solved = true
        }
    }

    private fun refresh() {
        val n = size
        val cats = cells.indices.filter { cells[it] == Cell.CAT }
        val clash = mutableSetOf<Int>()
        val woken = mutableSetOf<Int>()
        val keys: List<(Int) -> Int> = listOf({ it / n }, { it % n }, { puzzle.regions[it] })
        for (key in keys) {
            for ((value, group) in cats.groupBy(key)) {
                if (group.size > 1) {
                    woken += group
                    clash += cells.indices.filter { key(it) == value }
                }
            }
        }
        for (a in cats) for (b in cats) {
            if (b > a && abs(a / n - b / n) <= 1 && abs(a % n - b % n) <= 1) { woken += listOf(a, b); clash += listOf(a, b) }
        }
        clashing = clash
        awake = woken
    }

    fun progress(now: Long) = CatNapProgress(number, level.ordinal, cells.map { it.ordinal }, elapsed(now), hints)
}

/** The puzzles solved on this device, the boards left half done, and the unlimited puzzles. */
class CatNapRecord(private val store: KeyValueStore) {
    @Serializable
    data class Solve(val seconds: Int, val hints: Int, val onTheDay: Boolean)

    @Serializable
    data class UnlimitedStats(val solved: Int = 0, val bestSeconds: Int? = null)

    private val solvesSerializer = MapSerializer(String.serializer(), Solve.serializer())
    private val progressSerializer = ListSerializer(CatNapProgress.serializer())
    private val statsSerializer = MapSerializer(String.serializer(), UnlimitedStats.serializer())

    private fun key(number: Int, level: CatNapLevel) = "$number.${level.ordinal}"

    private fun all(): Map<String, Solve> =
        store.getString(SOLVES)?.let { runCatching { AppJson.decodeFromString(solvesSerializer, it) }.getOrNull() } ?: emptyMap()

    fun solve(number: Int, level: CatNapLevel) = all()[key(number, level)]

    fun solves(number: Int): Map<CatNapLevel, Solve> {
        val stored = all()
        return CatNapLevel.entries.mapNotNull { l -> stored[key(number, l)]?.let { l to it } }.toMap()
    }

    /** Keeps the quicker time and the fewer hints; once solved on the day, always so. Whether it beat an earlier time. */
    fun submit(number: Int, level: CatNapLevel, seconds: Int, hints: Int, onTheDay: Boolean): Boolean {
        val stored = all().toMutableMap()
        val earlier = stored[key(number, level)]
        stored[key(number, level)] = Solve(
            min(seconds, earlier?.seconds ?: Int.MAX_VALUE),
            min(hints, earlier?.hints ?: Int.MAX_VALUE),
            onTheDay || earlier?.onTheDay == true,
        )
        store.putString(SOLVES, AppJson.encodeToString(solvesSerializer, stored))
        return earlier?.let { seconds < it.seconds } ?: false
    }

    /** Days in a row with a puzzle of the day solved that day, up to today — or yesterday while today's are open. */
    fun streak(today: Int): Int {
        val stored = all()
        fun solvedOnTheDay(n: Int) = CatNapLevel.entries.any { stored[key(n, it)]?.onTheDay == true }
        var day = if (solvedOnTheDay(today)) today else today - 1
        var count = 0
        while (day >= 1 && solvedOnTheDay(day)) { count += 1; day -= 1 }
        return count
    }

    private fun allProgress(): List<CatNapProgress> =
        store.getString(PROGRESS)?.let { runCatching { AppJson.decodeFromString(progressSerializer, it) }.getOrNull() } ?: emptyList()

    fun progress(number: Int, level: CatNapLevel) = allProgress().firstOrNull { it.number == number && it.level == level.ordinal }

    fun save(progress: CatNapProgress) {
        val kept = (allProgress().filterNot { it.number == progress.number && it.level == progress.level } + progress)
            .sortedWith(compareByDescending<CatNapProgress> { it.number }.thenByDescending { it.level })
            .take(PROGRESS_KEPT)
        store.putString(PROGRESS, AppJson.encodeToString(progressSerializer, kept))
    }

    fun forget(number: Int, level: CatNapLevel) {
        store.putString(PROGRESS, AppJson.encodeToString(progressSerializer, allProgress().filterNot { it.number == number && it.level == level.ordinal }))
    }

    // Unlimited: puzzles from a random seed rather than a date; progress kept under puzzle 0.

    fun unlimitedSeed(level: CatNapLevel): ULong? = store.getString("$SEED.${level.ordinal}")?.toULongOrNull()

    fun newUnlimitedSeed(level: CatNapLevel): ULong {
        var seed: ULong
        do { seed = kotlin.random.Random.nextLong().toULong() } while (seed == 0uL)
        store.putString("$SEED.${level.ordinal}", seed.toString())
        forget(CatNapDay.UNLIMITED, level)
        return seed
    }

    private fun allStats(): Map<String, UnlimitedStats> =
        store.getString(STATS)?.let { runCatching { AppJson.decodeFromString(statsSerializer, it) }.getOrNull() } ?: emptyMap()

    fun stats(level: CatNapLevel) = allStats()["${level.ordinal}"] ?: UnlimitedStats()

    /** Counts the solve, keeps the best time, and lets the next one be new. Whether it was a best. */
    fun submitUnlimited(level: CatNapLevel, seconds: Int): Boolean {
        val all = allStats().toMutableMap()
        val stats = all["${level.ordinal}"] ?: UnlimitedStats()
        val best = stats.bestSeconds?.let { seconds < it } ?: true
        all["${level.ordinal}"] = UnlimitedStats(stats.solved + 1, min(seconds, stats.bestSeconds ?: Int.MAX_VALUE))
        store.putString(STATS, AppJson.encodeToString(statsSerializer, all))
        store.remove("$SEED.${level.ordinal}")
        forget(CatNapDay.UNLIMITED, level)
        return best
    }

    fun freeTriesLeft() = max(0, FREE_TRIES - store.getInt(TRIES, 0))
    fun useFreeTry() = store.putInt(TRIES, store.getInt(TRIES, 0) + 1)

    fun lastLevel() = CatNapLevel.entries.getOrElse(store.getInt(LEVEL, 0)) { CatNapLevel.EASY }
    fun setLastLevel(level: CatNapLevel) = store.putInt(LEVEL, level.ordinal)

    companion object {
        private const val SOLVES = "game.naps.solves"
        private const val PROGRESS = "game.naps.progress"
        private const val SEED = "game.naps.unlimited.seed"
        private const val STATS = "game.naps.unlimited.stats"
        private const val TRIES = "game.naps.unlimited.freeTries"
        private const val LEVEL = "game.naps.level"
        private const val PROGRESS_KEPT = 9
        /** Unlimited puzzles a free account may start, once, to see what Premium is. */
        const val FREE_TRIES = 3
    }
}
