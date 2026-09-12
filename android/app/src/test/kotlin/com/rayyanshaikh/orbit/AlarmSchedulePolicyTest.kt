package com.rayyanshaikh.orbit

import org.junit.Assert.assertEquals
import org.junit.Test

class AlarmSchedulePolicyTest {
 @Test fun `gaps escalate and never drop below five minutes`() {
  assertEquals(1_200_000L, AlarmSchedulePolicy.gapMs(20, 1))
  assertEquals(900_000L, AlarmSchedulePolicy.gapMs(20, 2))
  assertEquals(720_000L, AlarmSchedulePolicy.gapMs(20, 3))
  assertEquals(540_000L, AlarmSchedulePolicy.gapMs(20, 4))
  assertEquals(360_000L, AlarmSchedulePolicy.gapMs(20, 5))
  assertEquals(300_000L, AlarmSchedulePolicy.gapMs(5, 5))
 }

 @Test fun `deadline is earliest of window end and two hours`() {
  assertEquals(8_200_000L, AlarmSchedulePolicy.deadline(1_000_000L, 20_000_000L))
  assertEquals(5_000_000L, AlarmSchedulePolicy.deadline(1_000_000L, 5_000_000L))
 }
}
