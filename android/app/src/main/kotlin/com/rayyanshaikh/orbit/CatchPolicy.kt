package com.rayyanshaikh.orbit

/** One held-app window synced from Flutter. */
data class CatchSession(
    val attemptId: String,
    val from: Long,
    val until: Long,
    val packages: List<String>,
)

/**
 * Which apps are held right now. Pro holds every chosen app. A free person
 * holds one app on one alarm, and only once the catch is switched on. The
 * clamp lives here as well as in Flutter, so edited preferences cannot unlock
 * more than the plan allows.
 */
object CatchPolicy {
    fun heldPackages(
        sessions: List<CatchSession>,
        entitled: Boolean,
        freeCatch: Boolean,
        now: Long,
    ): Set<String> {
        val open = sessions
            .filter { it.from <= now && it.until > now && it.packages.isNotEmpty() }
            .sortedWith(compareBy<CatchSession> { it.from }.thenBy { it.attemptId })
        if (entitled) return open.flatMap { it.packages }.toSet()
        if (!freeCatch) return emptySet()
        return open.firstOrNull()?.packages?.take(1)?.toSet().orEmpty()
    }

    /** The attempt whose hold covers [packageName], for counting reaches. */
    fun holdingAttempt(
        sessions: List<CatchSession>,
        packageName: String,
        entitled: Boolean,
        freeCatch: Boolean,
        now: Long,
    ): String? {
        if (packageName !in heldPackages(sessions, entitled, freeCatch, now)) return null
        return sessions
            .filter { it.from <= now && it.until > now && packageName in it.packages }
            .minWithOrNull(compareBy<CatchSession> { it.from }.thenBy { it.attemptId })
            ?.attemptId
    }
}
