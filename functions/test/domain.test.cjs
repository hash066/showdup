const {test} = require('node:test');
const assert = require('node:assert/strict');
const {
  nextBattleScore,
  battleCapacity,
  storedCapacity,
  hasActivePro,
} = require('../lib/domain');

test('score normalizes, floors snoozed completion and excludes unverifiable', () => {
  let score = nextBattleScore(undefined, 'completed', 3);
  assert.deepEqual(score, {
    earned: 85,
    eligibleAttempts: 1,
    penalties: 0,
    consecutiveMisses: 0,
    cracked: false,
    petMood: 'sad',
    score: 850,
  });
  score = nextBattleScore(score, 'unverifiable', 0);
  assert.equal(score.eligibleAttempts, 1);
  assert.equal(score.score, 850);
  assert.equal(score.consecutiveMisses, 0);
});

test('misses never cost points or crack the companion', () => {
  let score = nextBattleScore(undefined, 'completed', 0);
  for (let i = 0; i < 4; i++) score = nextBattleScore(score, 'expired', 0);
  assert.equal(score.consecutiveMisses, 4);
  assert.equal(score.penalties, 0);
  assert.equal(score.cracked, false);
  assert.equal(score.petMood, 'sad');
  assert.equal(score.score, 200);
  score = nextBattleScore(score, 'completed', 0);
  assert.equal(score.petMood, 'recovery');
  assert.equal(score.consecutiveMisses, 0);
});

test('a legacy cracked score heals and drops its penalty', () => {
  const legacy = {
    earned: 100, eligibleAttempts: 4, penalties: 100,
    consecutiveMisses: 3, cracked: true, petMood: 'cracked', score: 150,
  };
  const next = nextBattleScore(legacy, 'expired', 0);
  assert.equal(next.penalties, 0);
  assert.equal(next.cracked, false);
  assert.equal(next.petMood, 'sad');
  assert.equal(next.score, 200);
});

test('rest days are not scored and do not break a run', () => {
  const missed = nextBattleScore(undefined, 'expired', 0);
  const rested = nextBattleScore(missed, 'rested', 0);
  assert.equal(rested.eligibleAttempts, 1);
  assert.equal(rested.consecutiveMisses, 1);
  assert.equal(rested.score, missed.score);
});

test('battle capacity follows the creator plan', () => {
  assert.equal(battleCapacity(false), 4);
  assert.equal(battleCapacity(true), 10);
  assert.equal(storedCapacity(4), 4);
  assert.equal(storedCapacity(undefined), 10, 'older battles keep ten seats');
});

test('RevenueCat pro entitlement must be unexpired', () => {
  const now = Date.parse('2026-09-17T00:00:00Z');
  const with_ = (expires_date) => ({subscriber: {entitlements: {pro: {expires_date}}}});
  assert.equal(hasActivePro(with_('2026-10-01T00:00:00Z'), now), true);
  assert.equal(hasActivePro(with_('2026-09-01T00:00:00Z'), now), false);
  assert.equal(hasActivePro(with_(null), now), true);
  assert.equal(hasActivePro({subscriber: {entitlements: {}}}, now), false);
  assert.equal(hasActivePro(undefined, now), false);
});
