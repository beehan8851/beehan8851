package uz.ata.dawnwick

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.ata.dawnwick.core.AppJson
import uz.ata.dawnwick.alarm.model.MissionConfig
import uz.ata.dawnwick.alarm.model.StrokePoint
import uz.ata.dawnwick.missions.CatchMission
import uz.ata.dawnwick.missions.DrawSimilarity
import uz.ata.dawnwick.missions.JumpDetector

class DrawSimilarityTests {
    private fun circle(cx: Double, cy: Double, r: Double, start: Double = 0.0, reverse: Boolean = false) =
        (0..64).map { i ->
            val a = start + (if (reverse) -1 else 1) * 2 * PI * i / 64
            StrokePoint(cx + r * cos(a), cy + r * sin(a))
        }

    private fun line(x0: Double, y0: Double, x1: Double, y1: Double) = (0..20).map { StrokePoint(x0 + (x1 - x0) * it / 20, y0 + (y1 - y0) * it / 20) }

    @Test fun sameShapeElsewhereAndLargerMatches() {
        val score = DrawSimilarity.score(listOf(circle(100.0, 100.0, 50.0)), listOf(circle(300.0, 220.0, 120.0, start = 1.3, reverse = true)))
        assertTrue("score $score", score >= DrawSimilarity.THRESHOLD)
    }

    @Test fun strokeOrderDoesNotMatter() {
        val cross = listOf(line(0.0, 0.0, 100.0, 100.0), line(100.0, 0.0, 0.0, 100.0))
        val score = DrawSimilarity.score(cross, cross.reversed().map { it.reversed() })
        assertTrue("score $score", score > 0.9)
    }

    /** The same triangle, drawn wider at night and taller in the morning. */
    @Test fun sameShapeInOtherProportionsMatches() {
        val night = listOf(line(300.0, 1000.0, 540.0, 650.0), line(540.0, 650.0, 780.0, 1000.0), line(780.0, 1000.0, 300.0, 1000.0))
        val morning = listOf(line(320.0, 1450.0, 540.0, 1050.0), line(540.0, 1050.0, 760.0, 1450.0), line(760.0, 1450.0, 320.0, 1450.0))
        val score = DrawSimilarity.score(night, morning)
        assertTrue("score $score", score >= DrawSimilarity.THRESHOLD)
        assertTrue(DrawSimilarity.score(night, listOf(circle(540.0, 1200.0, 200.0))) < DrawSimilarity.THRESHOLD)
    }

    @Test fun differentShapeFails() {
        val score = DrawSimilarity.score(listOf(circle(100.0, 100.0, 50.0)), listOf(line(0.0, 0.0, 200.0, 0.0)))
        assertTrue("score $score", score < DrawSimilarity.THRESHOLD)
    }

    @Test fun emptyScoresZero() {
        assertEquals(0.0, DrawSimilarity.score(emptyList(), listOf(circle(0.0, 0.0, 1.0))), 0.0)
    }
}

class CatchMissionTests {
    @Test fun nothingCountsBeforeStart() {
        val m = CatchMission(3, Random(1))
        assertFalse(m.catchCat(0))
        assertEquals(0, m.caught)
    }

    @Test fun catchesUntilDone() {
        val m = CatchMission(3, Random(1))
        m.start(0)
        repeat(3) { assertTrue(m.catchCat(it * 100L)) }
        assertTrue(m.isDone)
        assertNull(m.jumpsAt)
        assertFalse(m.catchCat(1000))
        assertEquals(3, m.caught)
    }

    @Test fun jumpsWhenStayIsUp() {
        val m = CatchMission(5, Random(2))
        m.start(0)
        m.tick(m.stayMillis - 1)
        assertEquals(0, m.jumps)
        m.tick(m.stayMillis)
        assertEquals(1, m.jumps)
    }

    @Test fun missStartlesAndJumpsWithoutCounting() {
        val m = CatchMission(5, Random(3))
        m.start(0)
        m.miss(100)
        assertEquals(0, m.caught)
        assertEquals(1, m.jumps)
        assertTrue(m.isStartled(100 + CatchMission.STARTLE_MILLIS - 1))
        assertFalse(m.isStartled(100 + CatchMission.STARTLE_MILLIS))
    }

    @Test fun staysOnTheBoardAndGetsQuicker() {
        val m = CatchMission(20, Random(4))
        m.start(0)
        val first = m.stayMillis
        repeat(19) {
            m.catchCat(it.toLong())
            assertTrue(m.x in 0.1..0.9 && m.y in 0.12..0.88)
        }
        assertTrue(m.stayMillis < first)
        assertTrue(m.stayMillis >= 1000)
    }

    @Test fun requiresAtLeastOne() = assertEquals(1, CatchMission(0).required)
}

class JumpDetectorTests {
    @Test fun countsHardLandingsOncePerCooldown() {
        val d = JumpDetector()
        assertFalse(d.onReading(1.0, 0))
        assertTrue(d.onReading(3.5, 100))
        assertFalse(d.onReading(3.9, 500))
        assertTrue(d.onReading(3.4, 1000))
    }

    @Test fun ignoresQuickLifts() = assertFalse(JumpDetector().onReading(2.5, 0))
}

class MissionStorageTests {
    @Test fun setUpMissionsSurviveARoundTrip() {
        val missions: List<MissionConfig> = listOf(
            MissionConfig.QrCode("kitchen-42"),
            MissionConfig.Draw(listOf(listOf(StrokePoint(1.0, 2.0), StrokePoint(3.0, 4.0)))),
            MissionConfig.Steps(30), MissionConfig.Jump(8), MissionConfig.CatchCat(6),
        )
        val json = AppJson.encodeToString(kotlinx.serialization.builtins.ListSerializer(MissionConfig.serializer()), missions)
        val back = AppJson.decodeFromString(kotlinx.serialization.builtins.ListSerializer(MissionConfig.serializer()), json)
        assertEquals(missions, back)
        assertTrue(back.all { it.isConfigured })
    }
}
