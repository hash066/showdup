// FROZEN CONTRACT. Mirrors lib/models/*.dart exactly. Keep in sync.

export type VerifierType = 'steps' | 'location';

export type AttemptState =
  | 'pending'
  | 'completed'
  | 'abandoned'
  | 'expired'
  | 'unverifiable';

export type EndedReason =
  | 'verified'
  | 'user_ended'
  | 'window_expired'
  | 'verifier_error';

export type CommitmentStatus = 'active' | 'paused' | 'archived';
export type VolumeMode = 'gentle' | 'loud';

export interface StepsConfig {
  targetSteps: number;   // 200..20000
  minDurationMs: number; // >= 60000
}

export interface LocationConfig {
  lat: number;
  lng: number;
  radiusM: number; // 100..500
  dwellMs: number; // >= 60000
  label?: string;
}

export type VerifierConfig = StepsConfig | LocationConfig;

export interface CommitmentSchedule {
  daysOfWeek: number[];     // ISO, 1 = Monday
  windowStartLocal: string; // "06:30"
  windowEndLocal: string;   // "09:00"
  timezone: string;         // IANA
}

export interface ReminderConfig {
  intervalMinutes: number;
  volumeMode: VolumeMode;
  maxReminders: number;
}

export interface Restrictions {
  enabled: boolean;
  packages: string[];
}

export interface Commitment {
  ownerUid: string;
  title: string;
  verifierType: VerifierType;
  verifierConfig: VerifierConfig;
  schedule: CommitmentSchedule;
  reminder: ReminderConfig;
  restrictions: Restrictions;
  status: CommitmentStatus;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

export interface Attempt {
  commitmentId: string;
  ownerUid: string;
  date: string;
  windowStartAt: FirebaseFirestore.Timestamp;
  windowEndAt: FirebaseFirestore.Timestamp;
  state: AttemptState;
  remindersFired: number;
  snoozes: number;
  completedAt?: FirebaseFirestore.Timestamp; // SERVER ONLY
  evidence?: Record<string, unknown>;
  endedReason?: EndedReason;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface UserStats {
  currentStreak: number;
  longestStreak: number;
  completed: number;
  abandoned: number;
  unverifiable: number;
}

export const FREE_MAX_ACTIVE_COMMITMENTS = 1;
export const PRO_MAX_ACTIVE_COMMITMENTS = 20;

export const attemptId = (commitmentId: string, localDate: string) =>
  `${commitmentId}_${localDate}`;
