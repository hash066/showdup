package com.rayyanshaikh.orbit

object FocusPolicy {
    const val GRACE_MS = 10_000L

    fun shouldReset(
        distractingSince: Long,
        now: Long,
        resetApplied: Boolean,
        graceMs: Long = GRACE_MS,
    ): Boolean = distractingSince > 0L && !resetApplied && now - distractingSince >= graceMs

    fun progress(cleanSince: Long, now: Long, targetMs: Long, distracted: Boolean): Double {
        if (distracted || targetMs <= 0L) return 0.0
        return ((now - cleanSince).coerceAtLeast(0L).toDouble() / targetMs).coerceIn(0.0, 1.0)
    }
}
