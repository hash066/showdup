package com.rayyanshaikh.orbit

import kotlin.math.max
import kotlin.math.min

object AlarmSchedulePolicy {
 const val MAX_PULSES = 6
 const val MAX_ESCALATION_MS = 7_200_000L
 private val factors = doubleArrayOf(1.0, .75, .60, .45, .30)

 fun gapMs(baseMinutes: Long, nextIndex: Int): Long {
  val factor = factors[(nextIndex - 1).coerceIn(0, factors.lastIndex)]
  return max(300_000L, (baseMinutes * 60_000L * factor).toLong())
 }

 fun deadline(firstFiredAt: Long, windowEndAt: Long): Long =
  if (firstFiredAt > 0) min(windowEndAt, firstFiredAt + MAX_ESCALATION_MS)
  else windowEndAt
}
