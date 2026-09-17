export type BattleOutcome =
  | 'completed'
  | 'expired'
  | 'abandoned'
  | 'unverifiable'
  | 'rested';

export type ServerPetMood =
  | 'happy'
  | 'uneasy'
  | 'sad'
  | 'cracked'
  | 'recovery';

export type BattleScoreState = {
  earned: number;
  eligibleAttempts: number;
  /** Kept for stored-document compatibility. Misses no longer cost points. */
  penalties: number;
  consecutiveMisses: number;
  /** Kept for stored-document compatibility. Never set any more. */
  cracked: boolean;
  petMood: ServerPetMood;
  score: number;
};

export const FREE_BATTLE_CAPACITY = 4;
export const PRO_BATTLE_CAPACITY = 10;

/** People allowed in a battle: you and 3 friends free, up to 10 with Pro. */
export function battleCapacity(creatorIsPro: boolean): number {
  return creatorIsPro ? PRO_BATTLE_CAPACITY : FREE_BATTLE_CAPACITY;
}

/** Capacity of a stored battle; battles made before capacities were Pro. */
export function storedCapacity(value: unknown): number {
  const n = Number(value);
  return n === FREE_BATTLE_CAPACITY || n === PRO_BATTLE_CAPACITY
    ? n
    : PRO_BATTLE_CAPACITY;
}

/**
 * Whether a RevenueCat subscriber response holds an active `pro` entitlement.
 * A null expiry means a lifetime grant.
 */
export function hasActivePro(subscriber: unknown, now = Date.now()): boolean {
  const entitlement = (subscriber as {
    subscriber?: {entitlements?: Record<string, {expires_date?: string | null}>};
  })?.subscriber?.entitlements?.pro;
  if (!entitlement) return false;
  if (entitlement.expires_date == null) return true;
  const expires = Date.parse(entitlement.expires_date);
  return Number.isFinite(expires) && expires > now;
}

/**
 * Calculates rankings and the companion's mood from server-held history.
 * Never punitive: a miss makes it `sad` (shown as determined), the next
 * show-up is a `recovery`, and rest days and sensor trouble are not scored.
 */
export function nextBattleScore(
  current: Partial<BattleScoreState> | undefined,
  outcome: BattleOutcome,
  snoozes: number,
): BattleScoreState {
  const eligible = outcome !== 'unverifiable' && outcome !== 'rested';
  const completed = outcome === 'completed';
  const missed = outcome === 'expired' || outcome === 'abandoned';
  const points = completed ? Math.max(60, 100 - Math.max(0, snoozes) * 5) : 0;
  const earned = Number(current?.earned ?? 0) + (eligible ? points : 0);
  const eligibleAttempts = Number(current?.eligibleAttempts ?? 0) +
    (eligible ? 1 : 0);
  let consecutiveMisses = Number(current?.consecutiveMisses ?? 0);
  let petMood: ServerPetMood = current?.petMood === 'cracked'
    ? 'sad'
    : current?.petMood ?? 'happy';

  if (completed) {
    petMood = consecutiveMisses > 0
      ? 'recovery'
      : snoozes >= 2 ? 'sad' : snoozes === 1 ? 'uneasy' : 'happy';
    consecutiveMisses = 0;
  } else if (missed) {
    consecutiveMisses += 1;
    petMood = 'sad';
  }

  const score = eligibleAttempts === 0
    ? 0
    : Math.max(
        0,
        Math.min(1000, Math.round(earned / (eligibleAttempts * 100) * 1000)),
      );
  return {
    earned,
    eligibleAttempts,
    penalties: 0,
    consecutiveMisses,
    cracked: false,
    petMood,
    score,
  };
}
