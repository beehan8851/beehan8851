package uz.ata.dawnwick

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.ata.dawnwick.companion.Pet
import uz.ata.dawnwick.companion.CompanionProgress
import uz.ata.dawnwick.companion.CompanionStore
import uz.ata.dawnwick.core.MemoryStore

class CompanionTests {
    private fun progress(
        premium: Boolean = false, best: Int = 0, nights: Int = 0,
        purchased: Set<String> = emptySet(), earned: Set<Pet> = emptySet(),
    ) = CompanionProgress(premium, best, nights, purchased, earned)

    @Test fun theCatIsAlwaysOpen() = assertTrue(progress().isUnlocked(Pet.CAT))

    @Test fun freeAccountHasOnlyTheCat() {
        val p = progress()
        assertEquals(listOf(Pet.CAT), Pet.entries.filter(p::isUnlocked))
    }

    @Test fun premiumOpensEveryone() {
        val p = progress(premium = true)
        assertTrue(Pet.entries.all(p::isUnlocked))
    }

    @Test fun chickComesWithAFourteenMorningStreak() {
        assertFalse(progress(best = 13).isUnlocked(Pet.CHICK))
        assertTrue(progress(best = 14).isUnlocked(Pet.CHICK))
        assertEquals(13 to 14, progress(best = 13).progress(Pet.CHICK))
        assertEquals(14 to 14, progress(best = 40).progress(Pet.CHICK))
    }

    @Test fun owlComesWithSevenTrackedNights() {
        assertFalse(progress(nights = 6).isUnlocked(Pet.OWL))
        assertTrue(progress(nights = 7).isUnlocked(Pet.OWL))
    }

    @Test fun aPurchaseOpensOnlyItsCompanion() {
        val p = progress(purchased = setOf("dawnwick_companion_puppy"))
        assertTrue(p.isUnlocked(Pet.PUPPY))
        assertFalse(p.isUnlocked(Pet.LAMB))
    }

    @Test fun earnedCompanionsStayEarned() {
        val reached = progress(best = 14, nights = 7)
        assertEquals(setOf(Pet.CHICK, Pet.OWL), reached.newlyEarned())
        // The streak broke and the nights aged out, but what was earned is kept.
        val later = progress(best = 0, nights = 0, earned = setOf(Pet.CHICK, Pet.OWL))
        assertTrue(later.isUnlocked(Pet.CHICK))
        assertTrue(later.isUnlocked(Pet.OWL))
        assertTrue(later.newlyEarned().isEmpty())
    }

    @Test fun aLockedChoiceShowsTheCatButIsRemembered() {
        val store = CompanionStore(MemoryStore())
        store.choose(Pet.PUPPY)
        assertEquals(Pet.PUPPY, store.shown(progress(premium = true)))
        // Premium ended: the cat is back on screen, and the puppy returns with Premium.
        assertEquals(Pet.CAT, store.shown(progress()))
        assertEquals(Pet.PUPPY, store.chosen.value)
    }

    @Test fun storeKeepsChoiceAndEarned() {
        val backing = MemoryStore()
        CompanionStore(backing).apply { choose(Pet.OWL); earned = setOf(Pet.OWL, Pet.CHICK) }
        val again = CompanionStore(backing)
        assertEquals(Pet.OWL, again.chosen.value)
        assertEquals(setOf(Pet.OWL, Pet.CHICK), again.earned)
    }

    @Test fun everyPaidCompanionHasItsOwnProduct() {
        assertEquals(4, Pet.productIds.size)
        assertEquals(Pet.productIds.size, Pet.productIds.toSet().size)
    }
}
