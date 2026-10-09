package uz.ata.dawnwick.alarm.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MathDifficulty { EASY, MEDIUM, HARD }

@Serializable
enum class MemoryDifficulty(val columns: Int, val highlightCount: Int) {
    EASY(3, 3), MEDIUM(4, 5), HARD(5, 7)
}

/** A point of a drawing, 0–1 in both directions. */
@Serializable
data class StrokePoint(val x: Double, val y: Double)

/**
 * What turns an alarm off, with its settings. The case is the kind of mission; its
 * values are what the person chose for it.
 */
@Serializable
sealed interface MissionConfig {
    val kind: MissionKind

    @Serializable @SerialName("math")
    data class Math(val difficulty: MathDifficulty, val rounds: Int) : MissionConfig {
        override val kind get() = MissionKind.MATH
    }

    @Serializable @SerialName("shake")
    data class Shake(val targetCount: Int) : MissionConfig {
        override val kind get() = MissionKind.SHAKE
    }

    @Serializable @SerialName("steps")
    data class Steps(val targetCount: Int) : MissionConfig {
        override val kind get() = MissionKind.STEPS
    }

    @Serializable @SerialName("qrCode")
    data class QrCode(val registeredCode: String?) : MissionConfig {
        override val kind get() = MissionKind.QR_CODE
    }

    @Serializable @SerialName("memory")
    data class Memory(val difficulty: MemoryDifficulty, val rounds: Int) : MissionConfig {
        override val kind get() = MissionKind.MEMORY
    }

    @Serializable @SerialName("typing")
    data class Typing(val phrase: String) : MissionConfig {
        override val kind get() = MissionKind.TYPING
    }

    @Serializable @SerialName("draw")
    data class Draw(val referenceStrokes: List<List<StrokePoint>>?) : MissionConfig {
        override val kind get() = MissionKind.DRAW
    }

    @Serializable @SerialName("jump")
    data class Jump(val targetCount: Int) : MissionConfig {
        override val kind get() = MissionKind.JUMP
    }

    @Serializable @SerialName("catchCat")
    data class CatchCat(val catches: Int) : MissionConfig {
        override val kind get() = MissionKind.CATCH_CAT
    }

    /** Whether it has what it needs to run at wake time. */
    val isConfigured: Boolean
        get() = when (this) {
            is QrCode -> registeredCode != null
            is Typing -> phrase.trim().length >= TYPING_MINIMUM_LENGTH
            is Draw -> referenceStrokes != null
            else -> true
        }

    companion object {
        /** A phrase shorter than this is a tap, not a mission. */
        const val TYPING_MINIMUM_LENGTH = 6

        val defaultMath: MissionConfig get() = Math(MathDifficulty.MEDIUM, 3)
    }
}

enum class MissionKind {
    MATH, SHAKE, STEPS, QR_CODE, MEMORY, TYPING, DRAW, JUMP, CATCH_CAT;

    val defaultConfig: MissionConfig
        get() = when (this) {
            MATH -> MissionConfig.defaultMath
            SHAKE -> MissionConfig.Shake(10)
            STEPS -> MissionConfig.Steps(20)
            QR_CODE -> MissionConfig.QrCode(null)
            MEMORY -> MissionConfig.Memory(MemoryDifficulty.EASY, 1)
            TYPING -> MissionConfig.Typing("")
            DRAW -> MissionConfig.Draw(null)
            JUMP -> MissionConfig.Jump(5)
            CATCH_CAT -> MissionConfig.CatchCat(8)
        }

    /**
     * Math and Shake stay free: a free account must still be able to build an alarm
     * that wakes someone, and neither needs hardware or a setup step.
     */
    val isPremium: Boolean get() = this != MATH && this != SHAKE

    /** Missions that need a setup flow before they work at alarm time. */
    val requiresSetup: Boolean get() = this == QR_CODE || this == DRAW
}
