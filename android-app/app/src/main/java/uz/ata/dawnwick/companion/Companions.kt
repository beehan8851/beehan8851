package uz.ata.dawnwick.companion

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import uz.ata.dawnwick.core.KeyValueStore

/**
 * The animal that keeps you company: the cat everyone starts with, and six more.
 * The games stay the cat's; everywhere else the chosen companion stands in for it.
 */
enum class Pet(val key: String, val unlock: Unlock) {
    CAT("cat", Unlock.Free),
    PUPPY("puppy", Unlock.Paid("dawnwick_companion_puppy")),
    CHICK("chick", Unlock.Streak(14)),
    CANARY("canary", Unlock.Paid("dawnwick_companion_canary")),
    LAMB("lamb", Unlock.Paid("dawnwick_companion_lamb")),
    OWL("owl", Unlock.SleepNights(7)),
    HAMSTER("hamster", Unlock.Paid("dawnwick_companion_hamster"));

    val isBird get() = this == CHICK || this == CANARY || this == OWL

    companion object {
        fun of(key: String?) = entries.firstOrNull { it.key == key } ?: CAT
        val productIds get() = entries.mapNotNull { (it.unlock as? Unlock.Paid)?.productId }
    }
}

/** How a companion is had: free, earned by a streak or by tracked nights, or bought. Premium has them all. */
sealed interface Unlock {
    data object Free : Unlock
    data class Streak(val days: Int) : Unlock
    data class SleepNights(val nights: Int) : Unlock
    data class Paid(val productId: String) : Unlock
}

/** What decides whether a companion is open to this person, read in one place. */
data class CompanionProgress(
    val premium: Boolean,
    val bestStreak: Int,
    val nightsTracked: Int,
    val purchased: Set<String>,
    /** Earned once, kept: a streak that later breaks, or nights that age out of the list, take nothing back. */
    val earned: Set<Pet>,
) {
    fun isUnlocked(c: Pet): Boolean = premium || c in earned || when (val u = c.unlock) {
        Unlock.Free -> true
        is Unlock.Streak -> bestStreak >= u.days
        is Unlock.SleepNights -> nightsTracked >= u.nights
        is Unlock.Paid -> u.productId in purchased
    }

    /** How far towards an earned companion, as done / needed; null for the others. */
    fun progress(c: Pet): Pair<Int, Int>? = when (val u = c.unlock) {
        is Unlock.Streak -> minOf(bestStreak, u.days) to u.days
        is Unlock.SleepNights -> minOf(nightsTracked, u.nights) to u.nights
        else -> null
    }

    /** Earned companions newly reached, to keep for good. */
    fun newlyEarned(): Set<Pet> = Pet.entries.filter { c ->
        c !in earned && when (val u = c.unlock) {
            is Unlock.Streak -> bestStreak >= u.days
            is Unlock.SleepNights -> nightsTracked >= u.nights
            else -> false
        }
    }.toSet()
}

/** The chosen companion and the ones earned, kept on the phone. */
class CompanionStore(private val store: KeyValueStore) {
    private val _chosen = MutableStateFlow(Pet.of(store.getString(KEY_CHOSEN)))
    /** What the person picked. Shown only while it is unlocked; see [shown]. */
    val chosen: StateFlow<Pet> = _chosen

    fun choose(c: Pet) {
        store.putString(KEY_CHOSEN, c.key)
        _chosen.value = c
    }

    var earned: Set<Pet>
        get() = store.getString(KEY_EARNED)?.split(',')?.filter { it.isNotBlank() }?.map(Pet::of)?.toSet() ?: emptySet()
        set(value) = store.putString(KEY_EARNED, value.joinToString(",") { it.key })

    /** The companion on screen: the chosen one, or the cat if it is no longer open (Premium ended). */
    fun shown(progress: CompanionProgress): Pet = chosen.value.takeIf(progress::isUnlocked) ?: Pet.CAT

    companion object {
        private const val KEY_CHOSEN = "companion.chosen"
        private const val KEY_EARNED = "companion.earned"
    }
}
