package uz.ata.dawnwick

import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.ata.dawnwick.core.MemoryStore
import uz.ata.dawnwick.games.BoxGame
import uz.ata.dawnwick.games.CatNapDay
import uz.ata.dawnwick.games.CatNapGame
import uz.ata.dawnwick.games.CatNapLevel
import uz.ata.dawnwick.games.CatNapPuzzle
import uz.ata.dawnwick.games.CatNapRecord
import uz.ata.dawnwick.games.CatchGame
import uz.ata.dawnwick.games.GameRecord
import uz.ata.dawnwick.games.LaserGame
import uz.ata.dawnwick.games.Pt

private const val T0 = 1_000_000_000L
private fun at(seconds: Double) = T0 + (seconds * 1000).toLong()

class CatchGameTests {
    private fun playing() = CatchGame(Random(42)).also { it.start(T0) }

    @Test fun `a catch scores and moves the cat`() {
        val game = playing()
        val before = game.position
        assertEquals(1, game.catchCat(at(0.5)))
        assertEquals(1, game.score)
        assertNotEquals(before, game.position)
        assertEquals(1, game.jumps)
    }

    @Test fun `after five in a row every catch counts double`() {
        val game = playing()
        for (i in 0 until 5) game.catchCat(at(i * 0.2))
        assertEquals(5, game.score)
        assertEquals(2, game.catchCat(at(1.2)))
        assertEquals(7, game.score)
        assertTrue(game.isOnCombo)
    }

    @Test fun `a miss costs the combo and startles the cat briefly`() {
        val game = playing()
        game.catchCat(at(0.2)); game.catchCat(at(0.4))
        game.miss(at(0.6))
        assertEquals(0, game.combo)
        assertEquals(2, game.score)
        assertEquals(2, game.bestCombo)
        assertTrue(game.isStartled(at(0.7)))
        assertFalse(game.isStartled(at(0.6 + CatchGame.STARTLE_LENGTH + 0.01)))
    }

    @Test fun `a cat left alone jumps away and breaks the run`() {
        val game = playing()
        game.catchCat(at(0.1))
        val jumps = game.jumps
        game.tick(at(0.1 + game.stayDuration + 0.01))
        assertEquals(jumps + 1, game.jumps)
        assertEquals(0, game.combo)
    }

    @Test fun `it gets quicker, the round ends at thirty, the cat stays on the board`() {
        val game = playing()
        val first = game.stayDuration
        for (i in 0 until 60) {
            game.catchCat(at(i * 0.1))
            assertTrue(game.position.x in 0.12..0.88 && game.position.y in 0.12..0.88)
        }
        assertTrue(game.stayDuration < first && game.stayDuration >= 0.55)
        game.tick(at(30.01))
        assertEquals(CatchGame.Phase.OVER, game.phase)
        assertEquals(0, game.catchCat(at(30.5)))
    }

    @Test fun `only a better score becomes the record`() {
        val record = GameRecord.catch(MemoryStore())
        assertTrue(record.submit(12))
        assertFalse(record.submit(9))
        assertEquals(12, record.best())
    }
}

class LaserGameTests {
    private val step = 1.0 / 60
    private fun playing() = LaserGame(Random(7)).also { it.setBoard(360.0, 560.0); it.start(T0) }

    private fun run(game: LaserGame, seconds: Double, each: (Long) -> Unit = {}) {
        var t = 0.0
        while (t < seconds && game.phase == LaserGame.Phase.PLAYING) {
            val now = at(t)
            each(now)
            game.tick(now)
            t += step
        }
    }

    @Test fun `with no dot the cat sits and waits`() {
        val game = playing()
        run(game, 2.0)
        assertEquals(LaserGame.Cat.Waiting, game.cat)
        assertEquals(0, game.pounces)
    }

    @Test fun `a dot held still under its nose is caught and scores nothing`() {
        val game = playing()
        val dot = Pt(game.strikePoint.x - 40, game.strikePoint.y)
        run(game, 3.0) { game.pointDot(dot, it) }
        assertTrue(game.pounces >= 1)
        assertTrue(game.caught >= 1)
        assertEquals(0, game.score)
    }

    @Test fun `a dot that is gone when the paws come down is a point`() {
        val game = playing()
        var dot = Pt(100.0, 380.0)
        var moved = false
        run(game, 4.0) { now ->
            if (game.cat is LaserGame.Cat.Pouncing && !moved) { dot = Pt(300.0, 120.0); moved = true }
            game.pointDot(dot, now)
        }
        assertTrue(moved)
        assertTrue(game.dodges >= 1 && game.score >= 1)
    }

    @Test fun `after three dodges in a row each one counts double`() {
        val game = playing()
        val spots = listOf(Pt(70.0, 140.0), Pt(290.0, 470.0))
        var dot = spots[0]
        var handled = 0
        run(game, 25.0) { now ->
            val c = game.cat
            if (c is LaserGame.Cat.Pouncing && handled < game.pounces) {
                handled = game.pounces
                dot = spots.maxBy { hypot(it.x - c.to.x, it.y - c.to.y) }
            }
            if (game.dodges < 4) game.pointDot(dot, now) else game.liftDot()
        }
        assertEquals(4, game.dodges)
        assertEquals(0, game.caught)
        assertEquals(5, game.score)
        assertEquals(4, game.bestCombo)
    }

    @Test fun `a pounce that lands after the finger lifts is worth nothing`() {
        val game = playing()
        var lifted = false
        run(game, 4.0) { now ->
            if (game.cat is LaserGame.Cat.Pouncing) lifted = true
            if (lifted) game.liftDot() else game.pointDot(Pt(100.0, 380.0), now)
        }
        assertTrue(lifted)
        assertEquals(0, game.score)
        assertEquals(0, game.caught)
        assertEquals(LaserGame.Cat.Waiting, game.cat)
    }

    @Test fun `a dot in a corner it cannot reach is not jumped at, and the round ends`() {
        val game = playing()
        run(game, 5.0) { game.pointDot(Pt(4.0, 6.0), it) }
        assertEquals(0, game.pounces)
        val other = playing()
        run(other, LaserGame.ROUND_LENGTH + 1)
        assertEquals(LaserGame.Phase.OVER, other.phase)
    }
}

class BoxGameTests {
    private fun playing(seed: Int = 3) = BoxGame(Random(seed)).also { it.start(T0) }

    private fun untilGuessing(game: BoxGame, from: Long): Long {
        var now = from
        repeat(5000) {
            if (game.step == BoxGame.Step.Guessing) return now
            now += 1000 / 60
            game.tick(now)
        }
        return now
    }

    private fun pastReveal(game: BoxGame, from: Long): Long {
        val now = from + ((BoxGame.MISSED_LENGTH + 0.05) * 1000).toLong()
        game.tick(now)
        return now
    }

    @Test fun `a round shows, hides, shuffles and waits, and the cat is where the swaps took it`() {
        for (seed in 1..20) {
            val game = playing(seed)
            assertTrue(game.step is BoxGame.Step.Showing)
            assertEquals(BoxGame.swapCount(0), game.swaps.size)
            val expected = BoxGame.apply(game.swaps, (0 until game.count).toList())[game.catBox]
            untilGuessing(game, T0)
            assertEquals(BoxGame.Step.Guessing, game.step)
            assertEquals(expected, game.catPlace)
        }
    }

    @Test fun `mid-swap the two boxes are on their way, one in front and one behind`() {
        val game = playing()
        var now = T0
        while (game.step !is BoxGame.Step.Shuffling) { now += 10; game.tick(now) }
        val spots = game.layout(now + (game.swapLength * 500).toLong())
        val swap = game.swaps[0]
        val moving = spots.filter { it.arc != 0.0 }
        assertEquals(2, moving.size)
        assertTrue(moving.all { abs(it.place - (swap.a + swap.b) / 2.0) < 0.02 })
        assertEquals(setOf(true, false), moving.map { it.arc > 0 }.toSet())
    }

    @Test fun `every swap moves two places and the cat's box is in most of them`() {
        val game = playing()
        assertTrue(game.swaps.all { it.a != it.b })
        var catAt = game.places[game.catBox]
        var withCat = 0
        for (s in game.swaps) {
            if (s.a == catAt || s.b == catAt) withCat++
            if (catAt == s.a) catAt = s.b else if (catAt == s.b) catAt = s.a
        }
        assertTrue(withCat * 2 >= game.swaps.size)
    }

    @Test fun `the right box scores once, three wrong boxes end the game`() {
        val game = playing()
        assertNull(game.choose(game.catBox, T0))
        var now = untilGuessing(game, T0)
        assertEquals(true, game.choose(game.catBox, now))
        assertEquals(1, game.score)
        assertNull(game.choose(game.catBox, now))
        now = pastReveal(game, now)
        for (miss in 1..3) {
            now = untilGuessing(game, now)
            assertEquals(false, game.choose((game.catBox + 1) % game.count, now))
            assertEquals(BoxGame.STARTING_LIVES - miss, game.lives)
            now = pastReveal(game, now)
        }
        assertEquals(BoxGame.Phase.OVER, game.phase)
    }

    @Test fun `finds add boxes and speed`() {
        assertEquals(3, BoxGame.boxes(3)); assertEquals(4, BoxGame.boxes(4)); assertEquals(5, BoxGame.boxes(9))
        assertTrue(BoxGame.swapLength(10) < BoxGame.swapLength(0))
        assertEquals(0.2, BoxGame.swapLength(100), 1e-9)
        assertEquals(14, BoxGame.swapCount(100))
        val game = playing()
        var now = T0
        repeat(4) {
            now = untilGuessing(game, now)
            game.choose(game.catBox, now)
            now = pastReveal(game, now)
        }
        assertEquals(4, game.score)
        assertEquals(4, game.count)
        assertEquals(listOf(0, 1, 2, 3), game.places)
    }
}

class CatNapTests {
    @Test fun `the same day makes the same puzzle as on iOS`() {
        // Pinned from the iOS tests: if these differ, the two apps disagree on puzzle 1.
        assertEquals(listOf(4, 1, 3, 0, 2), CatNapDay.puzzle(1, CatNapLevel.EASY).solution)
        assertEquals(listOf(1, 1, 0, 0, 0, 1, 1, 1, 1, 0), CatNapDay.puzzle(1, CatNapLevel.EASY).regions.take(10))
        assertEquals(listOf(3, 5, 1, 4, 2, 6, 0), CatNapDay.puzzle(1, CatNapLevel.MEDIUM).solution)
        assertEquals(listOf(1, 6, 4, 2, 0, 7, 5, 3), CatNapDay.puzzle(1, CatNapLevel.HARD).solution)
        assertEquals(listOf(0, 0, 0, 1, 1, 1, 1, 1, 0, 2), CatNapDay.puzzle(1, CatNapLevel.HARD).regions.take(10))
        assertNotEquals(CatNapDay.puzzle(4, CatNapLevel.MEDIUM), CatNapDay.puzzle(5, CatNapLevel.MEDIUM))
    }

    @Test fun `every puzzle has one answer and is as hard as its level says`() {
        for (number in 1..8) for (level in CatNapLevel.entries) {
            val p = CatNapDay.puzzle(number, level)
            assertEquals("puzzle $number $level", listOf(p.solution), CatNapPuzzle.solutions(p.size, p.regions, 3))
            val hardest = p.hardestStep()!!
            when (level) {
                CatNapLevel.EASY -> assertEquals(CatNapPuzzle.Reasoning.SINGLE, hardest)
                CatNapLevel.MEDIUM -> assertTrue(hardest <= CatNapPuzzle.Reasoning.LOOKAHEAD)
                CatNapLevel.HARD -> assertEquals(CatNapPuzzle.Reasoning.GROUPS, hardest)
            }
            for (region in 0 until p.size) assertTrue(CatNapPuzzle.isConnected(region, p.regions, p.size))
        }
    }

    @Test fun `puzzle 1 is 1 October 2026`() {
        assertEquals(1, CatNapDay.number(LocalDate.of(2026, 10, 1)))
        assertEquals(32, CatNapDay.number(LocalDate.of(2026, 11, 1)))
        assertEquals(1, CatNapDay.number(LocalDate.of(2026, 9, 20)))
        assertEquals(LocalDate.of(2026, 11, 1), CatNapDay.date(32))
    }

    private fun game() = CatNapGame(1, CatNapLevel.MEDIUM, CatNapDay.puzzle(1, CatNapLevel.MEDIUM))

    @Test fun `taps cycle, clashes wake, a stroke undoes in one go`() {
        val game = game()
        assertEquals(CatNapGame.Cell.MARK, game.tap(0, T0))
        assertEquals(CatNapGame.Cell.CAT, game.tap(0, T0))
        game.tap(4, T0); game.tap(4, T0)
        assertEquals(setOf(0, 4), game.awake)
        assertTrue((0 until game.size).all { it in game.clashing })
        game.undo(); game.undo()
        game.tap(game.size + 1, T0); game.tap(game.size + 1, T0)
        assertTrue(0 in game.awake && game.size + 1 in game.awake)

        val g2 = game()
        g2.tap(2, T0); g2.tap(2, T0)
        g2.beginStroke()
        for (i in 0 until 4) g2.paint(i, CatNapGame.Cell.MARK, T0)
        assertEquals(CatNapGame.Cell.CAT, g2.cells[2])
        assertEquals(CatNapGame.Cell.MARK, g2.cells[3])
        g2.undo()
        assertEquals(CatNapGame.Cell.EMPTY, g2.cells[0])
    }

    @Test fun `the last cat in place solves it and stops the clock`() {
        val game = game()
        game.resume(T0)
        game.puzzle.solution.forEachIndexed { row, column ->
            assertFalse(game.solved)
            game.tap(row * game.size + column, T0)
            game.tap(row * game.size + column, at(row.toDouble()))
        }
        assertTrue(game.solved)
        assertEquals((game.size - 1).toDouble(), game.elapsed(at(100.0)), 1e-6)
    }

    @Test fun `hints wake a misplaced cat first, then place the right ones`() {
        val game = game()
        val wrong = (0 until game.size).first { it != game.puzzle.solution[0] }
        game.tap(wrong, T0); game.tap(wrong, T0)
        assertEquals(wrong, game.hint(T0))
        assertEquals(game.puzzle.solution[0], game.hint(T0))
        repeat(game.size - 1) { game.hint(T0) }
        assertTrue(game.solved)
    }

    @Test fun `records, streaks, progress and unlimited`() {
        val record = CatNapRecord(MemoryStore())
        assertFalse(record.submit(3, CatNapLevel.HARD, 90, 1, true))
        assertTrue(record.submit(3, CatNapLevel.HARD, 70, 0, false))
        assertEquals(CatNapRecord.Solve(70, 0, true), record.solve(3, CatNapLevel.HARD))
        record.submit(4, CatNapLevel.EASY, 50, 0, true)
        record.submit(2, CatNapLevel.MEDIUM, 50, 0, false)
        assertEquals(2, record.streak(4))
        assertEquals(2, record.streak(5))
        assertEquals(0, record.streak(6))

        val game = game()
        game.resume(T0); game.tap(5, T0); game.pause(at(42.0))
        record.save(game.progress(at(42.0)))
        val back = CatNapGame(1, CatNapLevel.MEDIUM, game.puzzle, record.progress(1, CatNapLevel.MEDIUM))
        assertEquals(game.cells, back.cells)
        assertEquals(42.0, back.elapsed(T0), 1e-6)
        assertNull(record.progress(1, CatNapLevel.EASY))

        record.newUnlimitedSeed(CatNapLevel.EASY)
        assertTrue(record.submitUnlimited(CatNapLevel.EASY, 40))
        assertNull(record.unlimitedSeed(CatNapLevel.EASY))
        assertFalse(record.submitUnlimited(CatNapLevel.EASY, 55))
        assertEquals(CatNapRecord.UnlimitedStats(2, 40), record.stats(CatNapLevel.EASY))
        assertEquals(3, record.freeTriesLeft())
        repeat(5) { record.useFreeTry() }
        assertEquals(0, record.freeTriesLeft())
        assertEquals(CatNapLevel.EASY, record.lastLevel())
    }
}
