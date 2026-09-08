// FROZEN CONTRACT: signatures only. Agent 2 fills in the bodies.
//
// THE ONE RULE THAT MATTERS: the client never sends a completion time.
// submitEvidence stamps completedAt with FieldValue.serverTimestamp().
// If a client-supplied completedAt or timestamp field arrives, strip it.

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';

/**
 * Free users: rejects a second commitment with status "active".
 * Validates verifierConfig against the schema for verifierType.
 */
export const createCommitment = onCall(async (req) => {
  throw new HttpsError('unimplemented', 'agent 2');
});

/** Rejects patches to ownerUid, status transitions to active past the cap. */
export const updateCommitment = onCall(async (req) => {
  throw new HttpsError('unimplemented', 'agent 2');
});

/**
 * THE TRUST BOUNDARY.
 *  1. load attempt, reject unless state === 'pending'
 *  2. reject if now outside [windowStartAt, windowEndAt]
 *  3. run the plausibility check for this verifier type
 *  4. stamp completedAt = FieldValue.serverTimestamp()
 *  5. state = 'completed', endedReason = 'verified', update user stats
 *  6. idempotent: a repeat call returns the existing state, no double count
 */
export const submitEvidence = onCall(async (req) => {
  throw new HttpsError('unimplemented', 'agent 2');
});

/** reason must be 'user_ended'. Sets state = 'abandoned'. Can never complete. */
export const endAttempt = onCall(async (req) => {
  throw new HttpsError('unimplemented', 'agent 2');
});

/**
 * Every 15 minutes.
 *  - create today's pending attempt for any active commitment whose window
 *    opens within the next hour and whose weekday matches
 *  - expire pending attempts past windowEndAt: state = 'expired',
 *    endedReason = 'window_expired', break streak, clear restrictions
 * MUST be idempotent. It will run twice on the same attempt eventually.
 */
export const rolloverAttempts = onSchedule('every 15 minutes', async () => {
  throw new Error('unimplemented: agent 2');
});

/** Verifies the RevenueCat auth header. ONLY writer of isPro/proExpiresAt. */
export const revenueCatWebhook = onRequest(async (req, res) => {
  res.status(501).send('unimplemented: agent 2');
});
