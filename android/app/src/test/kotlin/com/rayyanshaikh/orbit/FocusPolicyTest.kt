package com.rayyanshaikh.orbit

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FocusPolicyTest {
    @Test fun tenContinuousSecondsResetsExactlyOnce() {
        val openedAt = 1_000L
        assertFalse(FocusPolicy.shouldReset(openedAt, 10_999L, false))
        assertTrue(FocusPolicy.shouldReset(openedAt, 11_000L, false))
        assertFalse(FocusPolicy.shouldReset(openedAt, 20_000L, true))
    }

    @Test fun distractedTimeNeverAdvancesCleanProgress() {
        assertEquals(0.0, FocusPolicy.progress(1_000L, 16_000L, 10_000L, true), 0.0)
        assertEquals(0.5, FocusPolicy.progress(1_000L, 6_000L, 10_000L, false), 0.0)
        assertEquals(1.0, FocusPolicy.progress(1_000L, 20_000L, 10_000L, false), 0.0)
    }
}
