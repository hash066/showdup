// Server-side schema validation and plausibility checks.
// These MUST mirror the Dart validators. Agent 2 implements the bodies.

import { LocationConfig, StepsConfig, VerifierConfig, VerifierType } from './types';

export function validateVerifierConfig(
  type: VerifierType,
  cfg: unknown
): asserts cfg is VerifierConfig {
  throw new Error('unimplemented');
}

/** Rejects impossible step evidence. Returns null when plausible. */
export function checkStepsPlausibility(args: {
  stepsSinceBaseline: number;
  elapsedMs: number;
  config: StepsConfig;
}): string | null {
  // Reject: elapsedMs < 60_000
  // Reject: steps/minute > 250 (human sprint cadence is about 200)
  // Reject: stepsSinceBaseline > 50_000
  // Reject: stepsSinceBaseline < config.targetSteps
  throw new Error('unimplemented');
}

/** Rejects impossible location evidence. Returns null when plausible. */
export function checkLocationPlausibility(args: {
  lat: number;
  lng: number;
  accuracyM: number;
  isMock: boolean;
  dwellMs: number;
  previousFix?: { lat: number; lng: number; epochMs: number };
  epochMs: number;
  config: LocationConfig;
}): string | null {
  // Reject: isMock === true
  // Reject: accuracyM > config.radiusM
  // Reject: distance to target > config.radiusM
  // Reject: dwellMs < config.dwellMs
  // Reject: implied speed from previousFix > 200 km/h
  throw new Error('unimplemented');
}

export function haversineMetres(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number }
): number {
  throw new Error('unimplemented');
}
