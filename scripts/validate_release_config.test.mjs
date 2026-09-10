import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { REQUIRED_KEYS, validateReleaseConfig } from './validate_release_config.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const script = join(here, 'validate_release_config.mjs');
const exampleConfig = join(here, '..', 'config.example.json');

// Well-formed but fake values. None of these are real credentials.
const valid = Object.freeze({
  FIREBASE_API_KEY: 'AIza' + 'SyTestOnlyNotARealKey'.padEnd(35, '0'),
  FIREBASE_APP_ID: '1:123456789012:android:0123456789abcdef',
  FIREBASE_PROJECT_ID: 'showdup-prod',
  FIREBASE_MESSAGING_SENDER_ID: '123456789012',
  REVENUECAT_ANDROID_KEY: 'goog_TestOnlyNotARealKey123',
  ONESIGNAL_APP_ID: '0b1f2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  USE_EMULATORS: 'false',
  EMULATOR_HOST: '10.0.2.2',
});
const patched = (patch) => ({ ...valid, ...patch });
const without = (key) => Object.fromEntries(Object.entries(valid).filter(([k]) => k !== key));

function assertRejected(config, pattern, expected = 'showdup-prod') {
  const errors = validateReleaseConfig(config, expected);
  assert.ok(errors.some((e) => pattern.test(e)), `expected ${pattern} in ${JSON.stringify(errors)}`);
}

describe('validateReleaseConfig', () => {
  test('accepts a complete production config', () => {
    assert.deepEqual(validateReleaseConfig(valid, 'showdup-prod'), []);
    assert.deepEqual(validateReleaseConfig(valid), []);
  });

  test('does not treat real-looking values as placeholders (regression)', () => {
    const errors = validateReleaseConfig(valid, 'showdup-prod');
    assert.ok(!errors.some((e) => /placeholder/.test(e)), JSON.stringify(errors));
  });

  test('accepts an upper-case OneSignal UUID', () => {
    assert.deepEqual(validateReleaseConfig(patched({ ONESIGNAL_APP_ID: valid.ONESIGNAL_APP_ID.toUpperCase() })), []);
  });

  for (const key of REQUIRED_KEYS) {
    test(`rejects a missing ${key}`, () => assertRejected(without(key), new RegExp(`^${key} is required`)));
    test(`rejects an empty ${key}`, () => assertRejected(patched({ [key]: '  ' }), new RegExp(`^${key} is required`)));
    test(`rejects a non-string ${key}`, () => assertRejected(patched({ [key]: 12345 }), new RegExp(`^${key} is required`)));
  }

  for (const value of ['replace-me', 'REPLACE_ME', 'changeme', 'TODO', 'your-api-key', '{{FIREBASE_API_KEY}}', '<api-key>', 'xxxx']) {
    test(`rejects placeholder ${value}`, () => assertRejected(patched({ FIREBASE_API_KEY: value }), /FIREBASE_API_KEY still contains a placeholder/));
  }

  test('rejects values with surrounding whitespace', () => {
    assertRejected(patched({ ONESIGNAL_APP_ID: ` ${valid.ONESIGNAL_APP_ID}` }), /ONESIGNAL_APP_ID must not contain whitespace/);
  });

  for (const value of ['true', 'False', '', true, false, undefined]) {
    test(`rejects USE_EMULATORS=${JSON.stringify(value)}`, () => {
      assertRejected(patched({ USE_EMULATORS: value }), /USE_EMULATORS must be the string "false"/);
    });
  }

  test('rejects a project id that differs from the expected project', () => {
    assertRejected(valid, /does not match expected project showdup-staging/, 'showdup-staging');
    const errors = validateReleaseConfig(valid, 'showdup-staging').join('\n');
    assert.ok(!errors.includes(valid.FIREBASE_PROJECT_ID), 'config project id leaked');
  });

  test('rejects Firebase demo projects', () => {
    assertRejected(patched({ FIREBASE_PROJECT_ID: 'demo-showdup' }), /must not target a Firebase demo project/, undefined);
    assertRejected(valid, /Expected project id must not be a Firebase demo project/, 'demo-showdup');
  });

  for (const value of ['Showdup-Prod', 'showdup_prod', 'short', 'trailing-hyphen-', '1showdup']) {
    test(`rejects malformed project id ${value}`, () => {
      assertRejected(patched({ FIREBASE_PROJECT_ID: value }), /FIREBASE_PROJECT_ID is not a valid Firebase project id/, undefined);
    });
  }

  test('rejects a malformed expected project id', () => {
    assertRejected(valid, /Expected project id is not a valid/, 'Not A Project');
  });

  for (const value of ['AIzaTooShort', 'BIza' + 'x'.repeat(35), 'AIza' + 'x'.repeat(36)]) {
    test(`rejects malformed API key of length ${value.length}`, () => {
      assertRejected(patched({ FIREBASE_API_KEY: value }), /FIREBASE_API_KEY does not look like a Google API key/);
    });
  }

  for (const value of ['1:123456789012:ios:0123456789abcdef', '1:123456789012:web:0123456789abcdef', '123456789012:android:abc', '1:123456789012:android:XYZ']) {
    test(`rejects non-Android Firebase app id ${value}`, () => {
      assertRejected(patched({ FIREBASE_APP_ID: value }), /FIREBASE_APP_ID must be a Firebase Android app id/);
    });
  }

  test('rejects an app id and sender id from different projects', () => {
    assertRejected(patched({ FIREBASE_MESSAGING_SENDER_ID: '999999999999' }), /belong to different Firebase projects/);
  });

  test('rejects a non-numeric sender id', () => {
    assertRejected(patched({ FIREBASE_MESSAGING_SENDER_ID: '12345abc' }), /FIREBASE_MESSAGING_SENDER_ID must contain digits only/);
  });

  test('rejects a RevenueCat secret key', () => {
    assertRejected(patched({ REVENUECAT_ANDROID_KEY: 'sk_TestOnlyNotARealKey' }), /is a RevenueCat secret key/);
  });

  for (const value of ['test_TestOnlyNotARealKey', 'appl_TestOnlyNotARealKey', 'amzn_TestOnlyNotARealKey', 'goog_']) {
    test(`rejects non-Play RevenueCat key ${value}`, () => {
      assertRejected(patched({ REVENUECAT_ANDROID_KEY: value }), /must be the RevenueCat Google Play public SDK key/);
    });
  }

  for (const value of ['not-a-uuid', '0b1f2c3d4e5f4a6b8c7d9e0f1a2b3c4d', '0b1f2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4g']) {
    test(`rejects malformed OneSignal app id ${value}`, () => {
      assertRejected(patched({ ONESIGNAL_APP_ID: value }), /ONESIGNAL_APP_ID must be a UUID/);
    });
  }

  for (const value of [null, [], 'string', 42]) {
    test(`rejects non-object JSON ${JSON.stringify(value)}`, () => {
      assert.deepEqual(validateReleaseConfig(value, 'showdup-prod'), ['Release config must be a JSON object']);
    });
  }
});

describe('validate_release_config CLI', () => {
  let dir;
  before(() => {
    dir = mkdtempSync(join(tmpdir(), 'showdup-release-config-'));
  });
  after(() => rmSync(dir, { recursive: true, force: true }));

  const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  const write = (name, content) => {
    const file = join(dir, name);
    writeFileSync(file, typeof content === 'string' ? content : JSON.stringify(content));
    return file;
  };

  test('exits 0 for a valid config and expected project', () => {
    const result = run(write('valid.json', valid), 'showdup-prod');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /valid for Firebase project showdup-prod/);
  });

  test('accepts a UTF-8 byte order mark', () => {
    const result = run(write('bom.json', `﻿${JSON.stringify(valid)}`), 'showdup-prod');
    assert.equal(result.status, 0, result.stderr);
  });

  test('config.example.json keeps secrets empty and USE_EMULATORS false', () => {
    const example = JSON.parse(readFileSync(exampleConfig, 'utf8'));
    for (const key of REQUIRED_KEYS) {
      assert.equal(example[key], '');
    }
    assert.equal(example.USE_EMULATORS, 'false');
  });

  test('rejects config.example.json with the demo project', () => {
    const result = run(exampleConfig, 'demo-showdup');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /FIREBASE_API_KEY is required/);
    assert.match(result.stderr, /Expected project id must not be a Firebase demo project/);
  });

  test('rejects config.example.json without an expected project', () => {
    assert.equal(run(exampleConfig).status, 1);
  });

  test('rejects a project mismatch', () => {
    const result = run(write('mismatch.json', valid), 'showdup-other');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /does not match expected project showdup-other/);
    assert.ok(!`${result.stdout}${result.stderr}`.includes(valid.FIREBASE_PROJECT_ID), 'config project id leaked');
  });

  test('rejects invalid JSON without echoing its contents', () => {
    const secretish = 'AIzaDoNotEchoThisValue';
    const result = run(write('broken.json', `{"FIREBASE_API_KEY": ${secretish}`), 'showdup-prod');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /not valid JSON/);
    assert.ok(!`${result.stdout}${result.stderr}`.includes(secretish), 'config contents leaked to output');
  });

  test('never echoes config values in validation errors', () => {
    const secretish = 'goog_DoNotEchoThisValue with space';
    const result = run(write('leak.json', patched({ REVENUECAT_ANDROID_KEY: secretish, FIREBASE_API_KEY: 'AIzaDoNotEcho' })), 'showdup-prod');
    assert.equal(result.status, 1);
    assert.ok(!`${result.stdout}${result.stderr}`.includes('DoNotEcho'), 'config value leaked to output');
  });

  test('reports a missing file', () => {
    const result = run(join(dir, 'missing.json'), 'showdup-prod');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /not found/);
  });

  test('prints usage and exits 2 without arguments', () => {
    const result = run();
    assert.equal(result.status, 2);
    assert.match(result.stderr, /Usage/);
  });
});
