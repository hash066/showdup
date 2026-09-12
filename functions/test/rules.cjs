const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} = require('firebase/firestore');

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-showdup',
    firestore: {rules: fs.readFileSync('../firestore.rules', 'utf8')},
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'socialUsers/alice'), {displayName: 'Alice'});
    await setDoc(doc(db, 'battleMemberships/alice'), {battleId: 'weekly'});
    await setDoc(doc(db, 'battles/weekly'), {
      memberUids: ['alice', 'friend'],
    });
    await setDoc(doc(db, 'battles/weekly/scores/alice'), {score: 700});
    await setDoc(doc(db, 'battleInvites/ABC123'), {battleId: 'weekly'});
  });
});

after(async () => env.cleanup());

test('a user can read only their own social profile', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const outsider = env.authenticatedContext('outsider').firestore();
  await assertSucceeds(getDoc(doc(alice, 'socialUsers/alice')));
  await assertFails(getDoc(doc(outsider, 'socialUsers/alice')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'socialUsers/alice')));
  await assertSucceeds(getDoc(doc(alice, 'battleMemberships/alice')));
  await assertFails(getDoc(doc(outsider, 'battleMemberships/alice')));
});

test('only battle members read battles and scores', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const outsider = env.authenticatedContext('outsider').firestore();
  await assertSucceeds(getDoc(doc(alice, 'battles/weekly')));
  await assertSucceeds(getDoc(doc(alice, 'battles/weekly/scores/alice')));
  await assertFails(getDoc(doc(outsider, 'battles/weekly')));
  await assertFails(getDoc(doc(outsider, 'battles/weekly/scores/alice')));
  await assertSucceeds(getDocs(query(
    collection(alice, 'battles'),
    where('memberUids', 'array-contains', 'alice'),
  )));
  await assertFails(getDocs(query(
    collection(outsider, 'battles'),
    where('memberUids', 'array-contains', 'alice'),
  )));
});

test('all social mutations and invite access remain server-only', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  for (const path of [
    'socialUsers/alice',
    'battleMemberships/alice',
    'battles/new',
    'battles/weekly/scores/alice',
    'battleInvites/ABC123',
    'rateLimits/alice_join',
  ]) {
    await assertFails(setDoc(doc(alice, path), {score: 1000}));
  }
  await assertFails(getDoc(doc(alice, 'battleInvites/ABC123')));
});

test('callables require Google, activate on join, score idempotently and cap ten members', async () => {
  process.env.GCLOUD_PROJECT = 'demo-showdup';
  const api = require('../lib/index');
  const {getFirestore} = require('firebase-admin/firestore');
  const db = getFirestore();
  const auth = (uid) => ({
    uid,
    token: {
      name: uid,
      auth_time: Date.now() / 1000,
      firebase: {identities: {'google.com': [uid]}},
    },
  });
  const app = {appId: 'test-app'};
  const run = (name, uid, data) => api[name].run({
    data,
    auth: auth(uid),
    app,
  });

  await assertFails(getDoc(doc(env.authenticatedContext('outsider').firestore(), 'battles/weekly')));
  await api.createBattle.run({
    data: {name: 'Nope', timezone: 'UTC', mascot: 'fox'},
    auth: {uid: 'anonymous', token: {firebase: {identities: {}}}},
    app,
  }).then(() => assert.fail('anonymous user created a battle'), () => {});
  await api.deleteSocialAccount.run({
    data: {},
    auth: {
      uid: 'stolen-session',
      token: {
        auth_time: Date.now() / 1000 - 3600,
        firebase: {identities: {'google.com': ['stolen-session']}},
      },
    },
    app,
  }).then(() => assert.fail('stale Google session deleted an account'), () => {});

  const created = await run('createBattle', 'captain', {
    name: 'Focus crew',
    timezone: 'UTC',
    mascot: 'cat',
  });
  const invite = await run('createBattleInvite', 'captain', {
    battleId: created.battleId,
  });
  assert.match(invite.code, /^[A-Z0-9]{6}$/);

  const repeatedCreatorJoin = await run('joinBattle', 'captain', {
    code: invite.code,
  });
  assert.equal(repeatedCreatorJoin.alreadyMember, true);
  let inviteDoc = (await db.doc(`battleInvites/${invite.code}`).get()).data();
  assert.equal(inviteDoc.uses, 0, 'an idempotent join does not consume an invite');
  let captainScore = (await db.doc(
    `battles/${created.battleId}/scores/captain`,
  ).get()).data();
  assert.equal(captainScore.mascot, 'cat', 'an idempotent join does not reset score');

  await run('joinBattle', 'friend', {code: invite.code});
  let battle = (await db.doc(`battles/${created.battleId}`).get()).data();
  assert.equal(battle.active, true);
  assert.equal(battle.memberUids.length, 2);

  const outcome = {
    eventId: 'attempt_2026-09-12',
    outcome: 'completed',
    snoozes: 2,
    resolvedAt: Date.now(),
    petMood: 'happy',
    burstCount: 0,
    mascot: 'cat',
  };
  const first = await run('submitBattleOutcome', 'captain', outcome);
  const again = await run('submitBattleOutcome', 'captain', outcome);
  assert.equal(first.score, 900);
  assert.equal(again.duplicate, true);
  const eventDocs = await db.collection(
    `battles/${created.battleId}/events`,
  ).where('eventId', '==', outcome.eventId).get();
  const storedEvent = eventDocs.docs[0].data();
  assert.ok(storedEvent.expiresAt.toMillis() > Date.now() + 13 * 86400000,
    'outcome idempotency records expire after two weeks');

  for (let index = 0; index < 3; index++) {
    await run('submitBattleOutcome', 'captain', {
      ...outcome,
      eventId: `miss_${index}`,
      outcome: 'expired',
      petMood: 'happy',
      burstCount: 0,
    });
  }
  captainScore = (await db.doc(
    `battles/${created.battleId}/scores/captain`,
  ).get()).data();
  assert.equal(captainScore.penalties, 100,
    'server derives burst penalty despite false client pet state');
  assert.equal(captainScore.petMood, 'cracked');

  const rival = await run('createBattle', 'rival', {
    name: 'Other crew', timezone: 'UTC', mascot: 'fox',
  });
  const rivalInvite = await run('createBattleInvite', 'rival', {
    battleId: rival.battleId,
  });
  await run('joinBattle', 'friend', {code: rivalInvite.code})
    .then(() => assert.fail('member joined a second battle'), () => {});

  await db.doc('battleMemberships/stale').set({
    uid: 'stale', battleId: 'deleted-battle',
  });
  const repaired = await run('createBattle', 'stale', {
    name: 'Recovered crew', timezone: 'UTC', mascot: 'puppy',
  });
  const repairedMembership = (await db.doc('battleMemberships/stale').get()).data();
  assert.equal(repairedMembership.battleId, repaired.battleId,
    'stale membership pointers are repaired atomically');

  for (let index = 0; index < 8; index++) {
    await run('joinBattle', `member${index}`, {code: invite.code});
  }
  battle = (await db.doc(`battles/${created.battleId}`).get()).data();
  assert.equal(battle.memberUids.length, 10);
  await run('joinBattle', 'eleventh', {code: invite.code})
    .then(() => assert.fail('eleventh member joined'), () => {});
});
