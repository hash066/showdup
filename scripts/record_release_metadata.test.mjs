import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { parseSha256Fingerprint, validateMetadataInputs } from './record_release_metadata.mjs';

describe('record release metadata helpers', () => {
  it('extracts a keytool SHA-256 fingerprint', () => {
    const fingerprint = Array.from({ length: 32 }, (_, index) =>
      index.toString(16).padStart(2, '0'),
    ).join(':');
    assert.equal(parseSha256Fingerprint(`SHA1: ignored\nSHA256: ${fingerprint}\n`), fingerprint.toUpperCase());
  });

  it('rejects unsafe release identifiers', () => {
    assert.deepEqual(
      validateMetadataInputs({
        applicationId: 'not-an-id',
        buildName: '1.0',
        buildNumber: '0',
        firebaseProjectId: 'demo-showdup',
      }),
      [
        'application_id is invalid',
        'build_name must be MAJOR.MINOR.PATCH',
        'build_number must be between 1 and 2100000000',
        'firebase_project_id is invalid or is a demo project',
      ],
    );
  });

  it('accepts the intended first-release identifiers', () => {
    assert.deepEqual(
      validateMetadataInputs({
        applicationId: 'com.rayyanshaikh.orbit',
        buildName: '1.0.0',
        buildNumber: '1',
        firebaseProjectId: 'showdup-f0799',
      }),
      [],
    );
  });
});
