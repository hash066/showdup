export type BattleOutcome =
  | 'completed'
  | 'expired'
  | 'abandoned'
  | 'unverifiable';

export type ServerPetMood =
  | 'happy'
  | 'uneasy'
  | 'sad'
  | 'cracked'
  | 'recovery';

export type BattleScoreState = {
  earned: number;
  eligibleAttempts: number;
  penalties: number;
  consecutiveMisses: number;
  cracked: boolean;
  petMood: ServerPetMood;
  score: number;
};

/** Calculates rankings and pet state from server-held history. */
export function nextBattleScore(
  current: Partial<BattleScoreState> | undefined,
  outcome: BattleOutcome,
  snoozes: number,
): BattleScoreState {
  const eligible = outcome !== 'unverifiable';
  const completed = outcome === 'completed';
  const missed = outcome === 'expired' || outcome === 'abandoned';
  const points = completed ? Math.max(60, 100 - Math.max(0, snoozes) * 5) : 0;
  const earned = Number(current?.earned ?? 0) + (eligible ? points : 0);
  const eligibleAttempts = Number(current?.eligibleAttempts ?? 0) +
    (eligible ? 1 : 0);
  let penalties = Number(current?.penalties ?? 0);
  let consecutiveMisses = Number(current?.consecutiveMisses ?? 0);
  let cracked = current?.cracked === true;
  let petMood: ServerPetMood = current?.petMood ?? 'happy';

  if (completed) {
    petMood = cracked ? 'recovery' : snoozes >= 2 ? 'sad' : snoozes === 1 ? 'uneasy' : 'happy';
    consecutiveMisses = 0;
    cracked = false;
  } else if (missed) {
    consecutiveMisses += 1;
    if (consecutiveMisses >= 3 && !cracked) {
      penalties += 100;
      cracked = true;
    }
    petMood = cracked ? 'cracked' : 'sad';
  }

  const score = eligibleAttempts === 0
    ? 0
    : Math.max(
        0,
        Math.min(
          1000,
          Math.round(earned / (eligibleAttempts * 100) * 1000) - penalties,
        ),
      );
  return {
    earned,
    eligibleAttempts,
    penalties,
    consecutiveMisses,
    cracked,
    petMood,
    score,
  };
}
