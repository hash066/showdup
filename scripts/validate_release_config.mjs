#!/usr/bin/env node
// Validates the production --dart-define-from-file config before a signed
// release build. Error messages never include config values.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const REQUIRED_KEYS = Object.freeze([
  'FIREBASE_API_KEY',
  'FIREBASE_APP_ID',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_MESSAGING_SENDER_ID',
  'REVENUECAT_ANDROID_KEY',
  'ONESIGNAL_APP_ID',
]);

// Whole-value placeholder words, template markers, and "your-..." stubs.
const PLACEHOLDER =
  /^(?:replace[-_ ]?me|change[-_ ]?me|todo|tbd|placeholder|example|x{3,})$|^your[-_ ]|^replace[-_ ]?me[-_ ]|\{\{|\}\}|^<.*>$/i;
// Google Cloud project ids: 6-30 chars, lowercase letter first, no trailing hyphen.
const PROJECT_ID = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
// Google API keys are 39 characters and start with "AIza".
const GOOGLE_API_KEY = /^AIza[0-9A-Za-z_-]{35}$/;
// Firebase app ids are 1:<project number>:<platform>:<hex>.
const ANDROID_APP_ID = /^1:(\d+):android:[0-9a-f]+$/;
const DIGITS = /^\d+$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Returns a list of human-readable problems; an empty list means valid.
 * @param {unknown} config parsed JSON
 * @param {string | undefined} expectedProjectId
 */
export function validateReleaseConfig(config, expectedProjectId) {
  if (config === null || typeof config !== 'object' || Array.isArray(config)) {
    return ['Release config must be a JSON object'];
  }
  const errors = [];
  const present = new Set();

  for (const key of REQUIRED_KEYS) {
    const value = config[key];
    if (typeof value !== 'string' || value.trim() === '') {
      errors.push(`${key} is required and must be a non-empty string`);
    } else if (value !== value.trim() || /\s/.test(value)) {
      errors.push(`${key} must not contain whitespace`);
    } else if (PLACEHOLDER.test(value)) {
      errors.push(`${key} still contains a placeholder value`);
    } else {
      present.add(key);
    }
  }

  if (config.USE_EMULATORS !== 'false') {
    errors.push('USE_EMULATORS must be the string "false" for production');
  }

  const projectId = config.FIREBASE_PROJECT_ID;
  if (present.has('FIREBASE_PROJECT_ID')) {
    if (!PROJECT_ID.test(projectId)) {
      errors.push('FIREBASE_PROJECT_ID is not a valid Firebase project id');
    } else if (projectId.startsWith('demo-')) {
      errors.push('FIREBASE_PROJECT_ID must not target a Firebase demo project');
    }
  }
  if (expectedProjectId !== undefined) {
    if (typeof expectedProjectId !== 'string' || !PROJECT_ID.test(expectedProjectId)) {
      errors.push('Expected project id is not a valid Firebase project id');
    } else if (expectedProjectId.startsWith('demo-')) {
      errors.push('Expected project id must not be a Firebase demo project');
    } else if (projectId !== expectedProjectId) {
      // Name the expected id (a CLI/workflow input), never the config value.
      errors.push(`FIREBASE_PROJECT_ID does not match expected project ${expectedProjectId}`);
    }
  }

  if (present.has('FIREBASE_API_KEY') && !GOOGLE_API_KEY.test(config.FIREBASE_API_KEY)) {
    errors.push('FIREBASE_API_KEY does not look like a Google API key (AIza..., 39 characters)');
  }

  const appId = present.has('FIREBASE_APP_ID') ? ANDROID_APP_ID.exec(config.FIREBASE_APP_ID) : null;
  if (present.has('FIREBASE_APP_ID') && !appId) {
    errors.push('FIREBASE_APP_ID must be a Firebase Android app id (1:<project number>:android:<hex>)');
  }
  const senderOk = present.has('FIREBASE_MESSAGING_SENDER_ID') && DIGITS.test(config.FIREBASE_MESSAGING_SENDER_ID);
  if (present.has('FIREBASE_MESSAGING_SENDER_ID') && !senderOk) {
    errors.push('FIREBASE_MESSAGING_SENDER_ID must contain digits only');
  }
  if (appId && senderOk && appId[1] !== config.FIREBASE_MESSAGING_SENDER_ID) {
    errors.push('FIREBASE_APP_ID and FIREBASE_MESSAGING_SENDER_ID belong to different Firebase projects');
  }

  if (present.has('REVENUECAT_ANDROID_KEY')) {
    const key = config.REVENUECAT_ANDROID_KEY;
    if (key.startsWith('sk_')) {
      errors.push('REVENUECAT_ANDROID_KEY is a RevenueCat secret key; ship only the public Google Play SDK key');
    } else if (!key.startsWith('goog_') || key.length <= 'goog_'.length) {
      errors.push('REVENUECAT_ANDROID_KEY must be the RevenueCat Google Play public SDK key (goog_...)');
    }
  }

  if (present.has('ONESIGNAL_APP_ID') && !UUID.test(config.ONESIGNAL_APP_ID)) {
    errors.push('ONESIGNAL_APP_ID must be a UUID');
  }

  return errors;
}

/** CLI entry point. Returns the process exit code. */
export function main(args, { log = console.log, error = console.error } = {}) {
  const [configPath, expectedProjectId] = args;
  if (!configPath) {
    error('Usage: node scripts/validate_release_config.mjs <config.json> [expected-project-id]');
    return 2;
  }
  let config;
  try {
    // JSON.parse messages quote the input, so never print them.
    config = JSON.parse(readFileSync(configPath, 'utf8').replace(/^﻿/, ''));
  } catch (cause) {
    error(cause?.code === 'ENOENT' ? `Release config not found: ${configPath}` : 'Release config is not valid JSON');
    return 1;
  }
  const errors = validateReleaseConfig(config, expectedProjectId);
  if (errors.length) {
    error(`Release config failed validation:\n- ${errors.join('\n- ')}`);
    return 1;
  }
  log(`Release config valid for Firebase project ${config.FIREBASE_PROJECT_ID}.`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2));
}
