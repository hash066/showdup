import {randomBytes} from 'node:crypto';
import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {FieldValue, getFirestore, Timestamp} from 'firebase-admin/firestore';
import {defineSecret} from 'firebase-functions/params';
import {HttpsError, onCall} from 'firebase-functions/v2/https';
import {DateTime} from 'luxon';
import {z} from 'zod';
import {
  battleCapacity,
  hasActivePro,
  nextBattleScore,
  storedCapacity,
} from './domain';

initializeApp();
const db = getFirestore();
const dayMs = 24 * 60 * 60 * 1000;
const id = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
const battleIdSchema = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
const mascotSchema =
  z.enum(['dot', 'fox', 'cat', 'puppy', 'penguin', 'capybara']);
const revenueCatSecret = defineSecret('REVENUECAT_SECRET_KEY');

/**
 * Asks RevenueCat whether the app user has Pro. The client only names its
 * anonymous RevenueCat id; the entitlement itself is read server-side. Any
 * lookup failure falls back to the free capacity.
 */
async function isProSubscriber(appUserId: string | undefined): Promise<boolean> {
  const key = revenueCatSecret.value();
  if (!appUserId || !key) return false;
  try {
    const response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
      {headers: {Authorization: `Bearer ${key}`}, signal: AbortSignal.timeout(5000)},
    );
    if (!response.ok) return false;
    return hasActivePro(await response.json());
  } catch {
    return false;
  }
}

// Capacity guardrails, not a monetary hard cap. Keeping minInstances at zero
// prevents idle social services from accruing instance charges.
const socialCall = {
  enforceAppCheck: true,
  region: 'us-central1' as const,
  memory: '256MiB' as const,
  cpu: 1,
  minInstances: 0,
  maxInstances: 2,
  concurrency: 20,
  timeoutSeconds: 15,
};

type AuthRequest = {auth?: {uid: string; token: Record<string, any>}};

function uid(req: {auth?: {uid: string}}) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  return req.auth.uid;
}

function parse<T>(schema: z.ZodType<T>, data: unknown): T {
  const parsed = schema.safeParse(data);
  if (!parsed.success) {
    throw new HttpsError('invalid-argument', parsed.error.issues
      .map((issue) => issue.message).join('. '));
  }
  return parsed.data;
}

function requireGoogle(req: AuthRequest) {
  const userId = uid(req);
  const providers = req.auth?.token.firebase?.identities ?? {};
  if (!providers['google.com']) {
    throw new HttpsError('failed-precondition',
      'Connect Google before using battles.');
  }
  return userId;
}

function requireRecentGoogleAuth(req: AuthRequest) {
  const providers = req.auth?.token.firebase?.identities ?? {};
  if (!providers['google.com']) return;
  const authenticatedAt = Number(req.auth?.token.auth_time ?? 0);
  if (!Number.isFinite(authenticatedAt) ||
      Date.now() / 1000 - authenticatedAt > 5 * 60) {
    throw new HttpsError('failed-precondition',
      'Sign in again before deleting your social account.');
  }
}

function identityFields(req: AuthRequest, mascot = 'dot') {
  const displayName = String(req.auth?.token.name ?? 'Player')
    .trim().slice(0, 40) || 'Player';
  const photoUrl = typeof req.auth?.token.picture === 'string'
    ? req.auth.token.picture.slice(0, 2048)
    : null;
  return {displayName, photoUrl, mascot, updatedAt: FieldValue.serverTimestamp()};
}

function weekKey(zone: string, now = Date.now()) {
  const local = DateTime.fromMillis(now, {zone});
  if (!local.isValid) {
    throw new HttpsError('invalid-argument', 'Invalid timezone.');
  }
  return local.startOf('day').minus({days: local.weekday - 1}).toISODate()!;
}

async function rateLimit(
  userId: string,
  action: string,
  limit: number,
  windowMs = dayMs,
) {
  const ref = db.doc(`rateLimits/${userId}_${action}`);
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const start = Number(data?.windowStartedAt ?? now);
    const expired = start + windowMs <= now;
    const count = expired ? 0 : Number(data?.count ?? 0);
    if (!Number.isSafeInteger(count) || count < 0 || count >= limit) {
      throw new HttpsError('resource-exhausted',
        'Too many requests. Try again later.');
    }
    tx.set(ref, {
      uid: userId,
      action,
      count: count + 1,
      windowStartedAt: expired ? now : start,
      expiresAt: Timestamp.fromMillis(now + windowMs * 2),
    });
  });
}

async function ensureBattleWeek(ref: FirebaseFirestore.DocumentReference) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const current = weekKey(snap.data()!.timezone);
    if (snap.data()!.weekKey === current) return;
    const scores = await tx.get(ref.collection('scores').limit(10));
    tx.update(ref, {weekKey: current, updatedAt: FieldValue.serverTimestamp()});
    for (const score of scores.docs) {
      tx.set(score.ref, {
        earned: 0,
        eligibleAttempts: 0,
        penalties: 0,
        score: 0,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
}

export const createBattle = onCall({...socialCall, secrets: [revenueCatSecret]},
  async (req) => {
  const userId = requireGoogle(req);
  const data = parse(z.object({
    name: z.string().trim().min(1).max(40),
    timezone: z.string().min(1).max(80),
    mascot: mascotSchema,
    revenueCatAppUserId: z.string().regex(/^[A-Za-z0-9_$.:-]{1,100}$/)
      .optional(),
  }).strict(), req.data);
  const capacity = battleCapacity(
    await isProSubscriber(data.revenueCatAppUserId));
  const week = weekKey(data.timezone);
  await rateLimit(userId, 'createBattle', 2);

  const battleRef = db.collection('battles').doc();
  const membershipRef = db.doc(`battleMemberships/${userId}`);
  const battleId = await db.runTransaction(async (tx) => {
    const membership = await tx.get(membershipRef);
    if (membership.exists) {
      const existingId = String(membership.data()!.battleId);
      const existingBattle = await tx.get(db.doc(`battles/${existingId}`));
      const existingMembers = existingBattle.data()?.memberUids;
      if (existingBattle.exists && Array.isArray(existingMembers) &&
          existingMembers.includes(userId)) {
        return existingId;
      }
      // A stale pointer is overwritten atomically by the new membership below.
    }
    const identity = identityFields(req, data.mascot);
    tx.create(battleRef, {
      name: data.name,
      creatorUid: userId,
      timezone: data.timezone,
      weekKey: week,
      memberUids: [userId],
      capacity,
      active: false,
      activatedAt: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(battleRef.collection('scores').doc(userId), {
      displayName: identity.displayName,
      mascot: data.mascot,
      petMood: 'happy',
      earned: 0,
      eligibleAttempts: 0,
      penalties: 0,
      consecutiveMisses: 0,
      cracked: false,
      score: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(membershipRef, {
      uid: userId,
      battleId: battleRef.id,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.doc(`socialUsers/${userId}`), identity, {merge: true});
    return battleRef.id;
  });
  return {battleId};
});

export const createBattleInvite = onCall(socialCall, async (req) => {
  const userId = requireGoogle(req);
  const battleId = parse(battleIdSchema, req.data?.battleId);
  await rateLimit(userId, 'invite', 10);
  const battle = await db.doc(`battles/${battleId}`).get();
  const members = battle.data()?.memberUids;
  if (!battle.exists || !Array.isArray(members) || !members.includes(userId)) {
    throw new HttpsError('not-found', 'Battle not found.');
  }
  const capacity = storedCapacity(battle.data()?.capacity);
  if (members.length >= capacity) {
    throw new HttpsError('resource-exhausted',
      `This battle already has ${capacity} people.`);
  }

  const expiresAt = Date.now() + 7 * dayMs;
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = randomBytes(5).toString('base64url')
      .replace(/[-_]/g, '').slice(0, 6).toUpperCase();
    if (code.length !== 6) continue;
    try {
      await db.doc(`battleInvites/${code}`).create({
        code,
        battleId,
        inviterUid: userId,
        expiresAt: Timestamp.fromMillis(expiresAt),
        uses: 0,
        maxUses: 9,
        createdAt: FieldValue.serverTimestamp(),
      });
      return {code, url: `https://showdup-f0799.web.app/i/${code}`, expiresAt};
    } catch (error) {
      const errorCode = (error as {code?: number | string}).code;
      if (errorCode !== 6 && errorCode !== 'already-exists') throw error;
    }
  }
  throw new HttpsError('internal', 'Could not create an invite.');
});

export const joinBattle = onCall(socialCall, async (req) => {
  const userId = requireGoogle(req);
  const code = parse(z.string().regex(/^[A-Z0-9]{6}$/), req.data?.code);
  await rateLimit(userId, 'join', 10);
  const inviteRef = db.doc(`battleInvites/${code}`);
  const membershipRef = db.doc(`battleMemberships/${userId}`);

  return db.runTransaction(async (tx) => {
    const invite = await tx.get(inviteRef);
    const membership = await tx.get(membershipRef);
    const expiresAt = invite.data()?.expiresAt;
    if (!invite.exists || !(expiresAt instanceof Timestamp) ||
        expiresAt.toMillis() <= Date.now()) {
      throw new HttpsError('not-found', 'Invite expired or invalid.');
    }
    const inviteBattleId = String(invite.data()!.battleId);
    const existingBattleId = membership.exists
      ? String(membership.data()!.battleId)
      : null;
    const existingBattle = existingBattleId != null &&
        existingBattleId !== inviteBattleId
      ? await tx.get(db.doc(`battles/${existingBattleId}`))
      : null;
    const existingMembers = existingBattle?.data()?.memberUids;
    if (existingBattle?.exists === true && Array.isArray(existingMembers) &&
        existingMembers.includes(userId)) {
      throw new HttpsError('failed-precondition',
        'Leave your current battle before joining another one.');
    }
    const battleRef = db.doc(`battles/${inviteBattleId}`);
    const battle = await tx.get(battleRef);
    if (!battle.exists) throw new HttpsError('not-found', 'Battle not found.');
    const members = battle.data()!.memberUids;
    if (!Array.isArray(members)) {
      throw new HttpsError('internal', 'Battle membership is invalid.');
    }
    if (members.includes(userId)) {
      return {battleId: battle.id, alreadyMember: true};
    }
    const capacity = storedCapacity(battle.data()!.capacity);
    if (members.length >= capacity ||
        Number(invite.data()!.uses ?? 0) >= Number(invite.data()!.maxUses ?? 9)) {
      throw new HttpsError('resource-exhausted',
        `This battle already has ${capacity} people.`);
    }

    const nextMembers = [...members, userId];
    const activating = battle.data()!.active !== true && nextMembers.length >= 2;
    const identity = identityFields(req);
    tx.update(battleRef, {
      memberUids: nextMembers,
      active: nextMembers.length >= 2,
      ...(activating ? {activatedAt: FieldValue.serverTimestamp()} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.create(battleRef.collection('scores').doc(userId), {
      displayName: identity.displayName,
      mascot: 'dot',
      petMood: 'happy',
      earned: 0,
      eligibleAttempts: 0,
      penalties: 0,
      consecutiveMisses: 0,
      cracked: false,
      score: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(membershipRef, {
      uid: userId,
      battleId: battle.id,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(db.doc(`socialUsers/${userId}`), identity, {merge: true});
    tx.update(inviteRef, {uses: FieldValue.increment(1)});
    return {battleId: battle.id, alreadyMember: false};
  });
});

export const leaveBattle = onCall(socialCall, async (req) => {
  const userId = requireGoogle(req);
  const battleId = parse(battleIdSchema, req.data?.battleId);
  await rateLimit(userId, 'leave', 5);
  const ref = db.doc(`battles/${battleId}`);
  const membershipRef = db.doc(`battleMemberships/${userId}`);
  const deleted = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const membership = await tx.get(membershipRef);
    const data = snap.data();
    const members = data?.memberUids;
    if (!data || !Array.isArray(members) || !members.includes(userId)) {
      return false;
    }
    const nextMembers = (members as string[]).filter((item) => item !== userId);
    if (nextMembers.length === 0) tx.delete(ref);
    else {
      tx.update(ref, {
        memberUids: nextMembers,
        creatorUid: data.creatorUid === userId ? nextMembers[0] : data.creatorUid,
        active: nextMembers.length >= 2,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    tx.delete(ref.collection('scores').doc(userId));
    if (membership.data()?.battleId === battleId) tx.delete(membershipRef);
    return nextMembers.length === 0;
  });
  if (deleted) await db.recursiveDelete(ref);
  return {ok: true};
});

export const submitBattleOutcome = onCall(socialCall, async (req) => {
  const userId = requireGoogle(req);
  const data = parse(z.object({
    eventId: id,
    outcome: z.enum(
      ['completed', 'expired', 'abandoned', 'unverifiable', 'rested']),
    snoozes: z.number().int().min(0).max(20),
    resolvedAt: z.number().int().positive(),
    // Kept for wire compatibility; server state below never trusts these.
    petMood: z.enum(['happy', 'uneasy', 'sad', 'cracked', 'recovery']),
    burstCount: z.number().int().min(0),
    mascot: mascotSchema,
  }).strict(), req.data);
  await rateLimit(userId, 'outcome', 25);

  const membership = await db.doc(`battleMemberships/${userId}`).get();
  if (!membership.exists) return {scored: false};
  const battle = await db.doc(`battles/${membership.data()!.battleId}`).get();
  const members = battle.data()?.memberUids;
  if (!battle.exists || !Array.isArray(members) ||
      !members.includes(userId) || battle.data()!.active !== true) {
    return {scored: false};
  }
  await ensureBattleWeek(battle.ref);
  const currentWeek = weekKey(battle.data()!.timezone);
  const weekStart = DateTime.fromISO(currentWeek,
    {zone: battle.data()!.timezone}).toMillis();
  const activatedAt =
    (battle.data()!.activatedAt as Timestamp | undefined)?.toMillis() ?? weekStart;
  if (data.resolvedAt < Math.max(weekStart, activatedAt) ||
      data.resolvedAt > Date.now() + 300000) {
    throw new HttpsError('failed-precondition',
      'Outcome is outside the active battle week.');
  }

  const scoreRef = battle.ref.collection('scores').doc(userId);
  const eventRef = battle.ref.collection('events')
    .doc(`${currentWeek}_${userId}_${data.eventId}`);
  return db.runTransaction(async (tx) => {
    const prior = await tx.get(eventRef);
    if (prior.exists) return {scored: true, duplicate: true};
    const score = await tx.get(scoreRef);
    const next = nextBattleScore(score.data(), data.outcome, data.snoozes);
    tx.create(eventRef, {
      uid: userId,
      eventId: data.eventId,
      outcome: data.outcome,
      snoozes: data.snoozes,
      resolvedAt: data.resolvedAt,
      weekKey: currentWeek,
      createdAt: FieldValue.serverTimestamp(),
      // Idempotency is only needed across the current/previous battle week.
      expiresAt: Timestamp.fromMillis(Date.now() + 14 * dayMs),
    });
    tx.set(scoreRef, {...next, mascot: data.mascot,
      updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {scored: true, score: next.score};
  });
});

export const deleteSocialAccount = onCall(socialCall, async (req) => {
  const userId = uid(req);
  requireRecentGoogleAuth(req);
  await rateLimit(userId, 'deleteAccount', 2);
  const membershipRef = db.doc(`battleMemberships/${userId}`);
  const membership = await membershipRef.get();
  if (membership.exists) {
    const battleRef = db.doc(`battles/${membership.data()!.battleId}`);
    const deleted = await db.runTransaction(async (tx) => {
      const battle = await tx.get(battleRef);
      const data = battle.data();
      if (!data) {
        tx.delete(membershipRef);
        return false;
      }
      const members = (data.memberUids as string[])
        .filter((item) => item !== userId);
      if (members.length === 0) tx.delete(battleRef);
      else {
        tx.update(battleRef, {
          memberUids: members,
          creatorUid: data.creatorUid === userId ? members[0] : data.creatorUid,
          active: members.length >= 2,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      tx.delete(battleRef.collection('scores').doc(userId));
      tx.delete(membershipRef);
      return members.length === 0;
    });
    if (deleted) await db.recursiveDelete(battleRef);
    else {
      const events = await battleRef.collection('events')
        .where('uid', '==', userId).limit(1000).get();
      const batch = db.batch();
      for (const event of events.docs) batch.delete(event.ref);
      if (!events.empty) await batch.commit();
    }
  }

  const invites = await db.collection('battleInvites')
    .where('inviterUid', '==', userId).limit(100).get();
  const cleanup = db.batch();
  for (const invite of invites.docs) cleanup.delete(invite.ref);
  for (const action of [
    'createBattle', 'invite', 'join', 'leave', 'outcome', 'deleteAccount',
  ]) {
    cleanup.delete(db.doc(`rateLimits/${userId}_${action}`));
  }
  cleanup.delete(db.doc(`socialUsers/${userId}`));
  await cleanup.commit();
  await getAuth().deleteUser(userId);
  return {ok: true};
});
