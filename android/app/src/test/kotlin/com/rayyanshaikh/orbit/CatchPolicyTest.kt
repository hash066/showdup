package com.rayyanshaikh.orbit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CatchPolicyTest {
    private val now = 10_000L
    private val sessions = listOf(
        CatchSession("late", from = 5_000, until = 20_000, packages = listOf("reels", "tube")),
        CatchSession("early", from = 1_000, until = 20_000, packages = listOf("chat", "feed")),
        CatchSession("future", from = 15_000, until = 30_000, packages = listOf("games")),
        CatchSession("over", from = 0, until = 9_000, packages = listOf("old")),
    )

    @Test fun proHoldsEveryOpenApp() {
        assertEquals(
            setOf("chat", "feed", "reels", "tube"),
            CatchPolicy.heldPackages(sessions, entitled = true, freeCatch = false, now = now),
        )
    }

    @Test fun freeHoldsOnlyTheFirstAppOfTheEarliestAlarm() {
        assertEquals(
            setOf("chat"),
            CatchPolicy.heldPackages(sessions, entitled = false, freeCatch = true, now = now),
        )
    }

    @Test fun freeHoldsNothingUntilTheCatchShips() {
        assertTrue(CatchPolicy.heldPackages(sessions, entitled = false, freeCatch = false, now = now).isEmpty())
    }

    @Test fun reachesCountAgainstTheHoldingAttemptOnly() {
        assertEquals("early", CatchPolicy.holdingAttempt(sessions, "chat", false, true, now))
        assertNull(CatchPolicy.holdingAttempt(sessions, "feed", false, true, now))
        assertEquals("late", CatchPolicy.holdingAttempt(sessions, "reels", true, false, now))
        assertNull(CatchPolicy.holdingAttempt(sessions, "games", true, false, now))
    }
}
