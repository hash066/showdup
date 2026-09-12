const {test} = require('node:test');
const assert = require('node:assert/strict');
const {nextBattleScore} = require('../lib/domain');

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

test('three genuine misses burst once and completion recovers the pet', () => {
  let score = nextBattleScore(undefined, 'expired', 0);
  assert.equal(score.consecutiveMisses, 1);
  assert.equal(score.penalties, 0);
  score = nextBattleScore(score, 'abandoned', 0);
  assert.equal(score.consecutiveMisses, 2);
  score = nextBattleScore(score, 'expired', 0);
  assert.equal(score.cracked, true);
  assert.equal(score.petMood, 'cracked');
  assert.equal(score.penalties, 100);
  score = nextBattleScore(score, 'expired', 0);
  assert.equal(score.penalties, 100, 'a cracked pet cannot burst repeatedly');
  score = nextBattleScore(score, 'completed', 0);
  assert.equal(score.cracked, false);
  assert.equal(score.consecutiveMisses, 0);
  assert.equal(score.petMood, 'recovery');
  assert.equal(score.penalties, 100);
});

test('unverifiable outcomes cannot advance a burst', () => {
  const missed = nextBattleScore(undefined, 'expired', 0);
  const ignored = nextBattleScore(missed, 'unverifiable', 0);
  assert.equal(ignored.consecutiveMisses, 1);
  assert.equal(ignored.penalties, 0);
  assert.equal(ignored.eligibleAttempts, 1);
});
