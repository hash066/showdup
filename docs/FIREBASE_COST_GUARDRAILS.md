# Firebase cost guardrails

ShowdUp's local commitments, alarms, verification evidence, history, pet and
overlay must continue to work when Firebase is unavailable. Firebase is used
only for authentication and invite-only weekly battles.

## Operating target

- Absolute owner budget: USD 10 per month.
- Initial engineering ceiling: 25,000 daily active battle users.
- Launch ceiling: 1,000 daily active battle users until seven days of measured
  production usage confirms the assumptions below.
- Functions fail closed when their scaling or request limits are reached. The
  Android-local product continues working.

The 25,000-user ceiling is deliberately conservative. It is not a promise that
Firebase will charge exactly USD 10: Firestore has no user-configurable hard
monthly spend cap, and billing reports and cap enforcement can be delayed.

## Cost model

The planning case assumes each daily active battle user:

- opens the app once;
- resolves one eligible attempt;
- belongs to a battle of at most ten people; and
- can receive one leaderboard document update for each connected member.

The conservative upper estimate is 27 reads and 3 writes per daily active user:
six server reads and three server writes for an outcome, up to eleven initial
battle/score listener reads, and up to ten score-update listener reads. At
25,000 daily active battle users, this is about 675,000 reads and 75,000 writes
per day. Using the Iowa Standard edition reference prices and subtracting the
daily no-cost quota gives approximately USD 7.11 per 30-day month for those
operations. Function invocations remain below the two-million monthly no-cost
tier in this scenario. Storage, data transfer, deployment artifacts, retries,
transaction contention and unusual listener behavior are extra.

At the same deliberately pessimistic usage pattern, the Firestore operation
estimate reaches USD 10 near 34,000 daily active battle users. ShowdUp therefore
uses 25,000—not 34,000—as the pre-measurement ceiling. Total registered or
installed users can be much higher when only a fraction use battles each day.

Pricing varies by database location. Recalculate from the actual billing
export before raising the ceiling:

```
monthly_reads  = daily_active_battle_users * reads_per_user_day * 30
monthly_writes = daily_active_battle_users * writes_per_user_day * 30
```

Official references:

- https://cloud.google.com/firestore/pricing
- https://firebase.google.com/pricing
- https://firebase.google.com/docs/projects/billing/spend-caps

## Required safeguards before Blaze deployment

- Enforce App Check on every social callable; use Play Integrity in release.
- Require Firebase authentication and Google linking for battles.
- Keep all membership, invitation, score and event mutations server-only.
- Bound callable memory, CPU, timeout, concurrency and maximum instances; keep
  minimum instances at zero.
- Rate-limit every callable and put a small daily ceiling on accepted outcomes.
- Reject duplicate, stale, future, cross-week and non-member outcomes.
- Keep battle membership at 2-10 and prevent a user joining multiple battles.
- Retain idempotency events only for a bounded period using Firestore TTL.
- Avoid duplicate leaderboard listeners and cap every query result.
- Configure a USD 3 Cloud Run Functions spend-cap budget. This is a preview
  control and can overshoot because enforcement is not instantaneous.
- Configure an overall alerts-only budget at USD 10 with notifications at the
  lowest available thresholds. This alerts on Firestore spend but does not stop
  it.
- Roll out at 1,000 battle DAU, inspect billed reads/writes daily for seven
  days, and raise the ceiling only from measured per-user costs.

If any safeguard is absent, leave the project on Spark and keep battles marked
unavailable. Spark cannot produce a surprise bill; quota exhaustion causes the
social backend to reject requests instead.
