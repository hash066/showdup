#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { basename, dirname, join, resolve } from 'node:path';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const APPLICATION_ID = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$/;
const BUILD_NAME = /^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})$/;
const BUILD_NUMBER = /^[1-9][0-9]{0,9}$/;
const FIREBASE_PROJECT_ID = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

export function parseSha256Fingerprint(output) {
  const match = output.match(/^\s*SHA256:\s*([0-9A-F]{2}(?::[0-9A-F]{2}){31})\s*$/im);
  return match?.[1]?.toUpperCase() ?? null;
}

export function validateMetadataInputs({ applicationId, buildName, buildNumber, firebaseProjectId }) {
  const errors = [];
  if (!APPLICATION_ID.test(applicationId)) errors.push('application_id is invalid');
  if (!BUILD_NAME.test(buildName)) errors.push('build_name must be MAJOR.MINOR.PATCH');
  if (!BUILD_NUMBER.test(buildNumber) || Number(buildNumber) > 2_100_000_000) {
    errors.push('build_number must be between 1 and 2100000000');
  }
  if (!FIREBASE_PROJECT_ID.test(firebaseProjectId) || firebaseProjectId.startsWith('demo-')) {
    errors.push('firebase_project_id is invalid or is a demo project');
  }
  return errors;
}

function run(command, args) {
  return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function main() {
  const [aabArg, applicationId, buildName, buildNumber, firebaseProjectId] = process.argv.slice(2);
  if (!aabArg || !applicationId || !buildName || !buildNumber || !firebaseProjectId) {
    console.error(
      'Usage: node scripts/record_release_metadata.mjs <aab> <application-id> <build-name> <build-number> <firebase-project-id>',
    );
    process.exit(2);
  }

  const errors = validateMetadataInputs({ applicationId, buildName, buildNumber, firebaseProjectId });
  if (errors.length > 0) {
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }

  const aab = resolve(aabArg);
  if (!existsSync(aab)) {
    console.error(`AAB not found: ${aab}`);
    process.exit(1);
  }

  if (run('git', ['status', '--porcelain']).trim()) {
    console.error('The Git worktree is not clean. Commit or remove release-source changes before recording a Git SHA.');
    process.exit(1);
  }

  let verification;
  try {
    verification = run('jarsigner', ['-verify', aab]);
  } catch (error) {
    const report = `${error.stdout ?? ''}${error.stderr ?? ''}`;
    if (report) console.error(report.trim());
    console.error('jarsigner rejected the AAB.');
    process.exit(1);
  }
  if (!/^jar verified\.\s*$/im.test(verification) || /jar is unsigned|unsigned entries/i.test(verification)) {
    console.error(verification.trim());
    console.error('The AAB is unsigned or contains unsigned entries.');
    process.exit(1);
  }

  let certificate;
  try {
    certificate = run('keytool', ['-printcert', '-jarfile', aab]);
  } catch (error) {
    console.error(`${error.stderr ?? error.message}`.trim());
    process.exit(1);
  }
  const signerSha256 = parseSha256Fingerprint(certificate);
  if (!signerSha256) {
    console.error('Could not read the AAB signer SHA-256 fingerprint.');
    process.exit(1);
  }

  const aabSha256 = createHash('sha256').update(readFileSync(aab)).digest('hex');
  const gitSha = run('git', ['rev-parse', 'HEAD']).trim();
  const outputDirectory = dirname(aab);
  const checksumPath = join(outputDirectory, `${basename(aab)}.sha256`);
  const metadataPath = join(outputDirectory, 'release-info.txt');
  writeFileSync(checksumPath, `${aabSha256}  ${basename(aab)}\n`, { mode: 0o600 });
  writeFileSync(
    metadataPath,
    [
      `git_sha=${gitSha}`,
      `application_id=${applicationId}`,
      `version_name=${buildName}`,
      `version_code=${buildNumber}`,
      `firebase_project_id=${firebaseProjectId}`,
      `upload_certificate_sha256=${signerSha256}`,
      `aab_sha256=${aabSha256}`,
      '',
    ].join('\n'),
    { mode: 0o600 },
  );

  console.log(`Verified signed AAB: ${aab}`);
  console.log(`Wrote: ${checksumPath}`);
  console.log(`Wrote: ${metadataPath}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main();
