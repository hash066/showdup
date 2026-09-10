# ShowdUp

ShowdUp is an Android Flutter app for commitments backed by step or location evidence. Firebase Auth, Firestore, and callable Functions provide the backend; RevenueCat and OneSignal provide billing and notifications.

## Local verification

Prerequisites: Flutter 3.41.7 with Dart 3.11.5, Node 22, Java 21, and at least 5 GB free on the system/temp drive. CI pins these versions plus Firebase CLI 15.30.0.

```powershell
flutter pub get
flutter analyze
flutter test
node --test "scripts/*.test.mjs"
npm ci --prefix functions
npm test --prefix functions
npm audit --prefix functions --omit=dev --audit-level=moderate
npx --yes firebase-tools@15.30.0 emulators:exec --only firestore --project demo-showdup "npm --prefix functions run test:rules"
flutter build apk --debug --dart-define-from-file=config.example.json
```

If the repository and pub cache are on different Windows drives and Kotlin incremental compilation fails, use a Java/Gradle environment on one drive or the clean Linux CI runner. Do not delete user caches to work around it.

## Production secrets and signing

Never commit `config.release.json`, `android/key.properties`, a keystore, or a service-account key. Verify `git status` before every push.

Create `config.release.json` from `config.example.json`, populate every value, keep `USE_EMULATORS` equal to the string `false`, and validate it:

```powershell
node scripts/validate_release_config.mjs config.release.json your-production-project-id
```

For a local signed build, create `android/key.properties`:

```properties
storeFile=C:/secure/showdup-upload.jks
storePassword=...
keyAlias=...
keyPassword=...
applicationId=com.yourcompany.showdup
```

Release has no debug-key fallback and fails if signing is incomplete:

```powershell
flutter build appbundle --release --dart-define-from-file=config.release.json --build-name=1.0.0 --build-number=1
node scripts/record_release_metadata.mjs build/app/outputs/bundle/release/app-release.aab com.rayyanshaikh.orbit 1.0.0 1 showdup-f0799
```

The metadata command requires a clean Git worktree, fails for an unsigned bundle, and writes `app-release.aab.sha256` plus `release-info.txt` beside the AAB. Keep those files with the release record. This build-and-record path does not use GitHub Actions, deploy Firebase, or require Blaze billing.

Back up the upload key and passwords in the team password manager. Confirm `applicationId` before the first Play upload; it cannot be changed afterward.

## GitHub production environment

Create a protected GitHub Environment named `production`, require a human reviewer, and add:

- `RELEASE_CONFIG_JSON`: complete production config JSON.
- `ANDROID_KEYSTORE_BASE64`: base64 of the Play upload keystore.
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- `FIREBASE_SERVICE_ACCOUNT_JSON`: least-privilege deploy identity, only needed for backend deployment.

Run **Production release** manually with the exact Firebase project and Play application ids. The workflow validates config/project alignment, runs checks, creates a signed AAB, verifies it, and publishes it as a short-lived artifact. Optional backend deployment runs only after the signed build and production-environment approval.

Set `deploy_firebase` to `false` when only producing the AAB. That path does not deploy Functions, rules, or indexes and does not require Firebase billing or a Firebase service-account secret. Set it to `true` only when the selected Firebase project is on Blaze and backend deployment is intended.

The repository is private. Check that the GitHub plan supports environment secrets and required reviewers for private repositories before relying on the `production` environment. If it does not, use the local signed-build path above and have a second person verify `release-info.txt` before upload; this is a zero-cost fallback, not a substitute for the requested protected-environment control.

## First Play internal release and App Check

1. Confirm the final application id before uploading any artifact. The first Play upload permanently assigns the package name to the Play app.
2. Create and back up a dedicated upload keystore outside the repository, then build and record the signed AAB as above.
3. Enable Play App Signing and upload that exact AAB to **Internal testing**, not Production. The upload certificate authenticates the bundle upload; Google Play signs the APK delivered to testers with a separate Play app-signing certificate.
4. In Play Console, link the Play Integrity API to the same Google Cloud project used by Firebase. Copy every applicable Play app-signing SHA-256 fingerprint shown by Play—not just the upload-key fingerprint—into the Firebase Android app and its Play Integrity App Check registration. This includes the certificate used for older Android versions when Play shows multiple signing certificates.
5. Callable Functions enforce App Check in code (`enforceAppCheck: true`). From their first deploy they reject every request from a build whose signing certificate is not registered, including the native reminder and evidence calls. Finish step 4 before deploying Functions. Leave the console's Firestore enforcement off for now. Install the internal-track build from its Play tester link, exercise Auth, Firestore, and callable Functions, and confirm App Check metrics classify those requests as valid.
6. Turn on console enforcement for Firestore only after the internal-track device gate passes. Do not use a debug App Check token in a release build.

Internal App Sharing is a different facility that re-signs uploads with a test certificate. Prefer the Internal testing track for this gate; otherwise that separate test-certificate SHA-256 also has to be registered.

## EOD production checklist

1. **Firebase:** register the final application id; enable the intended Auth provider; create Firestore in the intended region; deploy Functions, rules, and indexes. Callable Functions in this repo are pinned to `us-central1`—deploy that region and configure billing plus the RevenueCat webhook secret. Confirm callable Functions and owner-only reads with a non-admin test account.
2. **App Check:** register Play Integrity and add the Play app-signing SHA-256 *before* deploying Functions, because callables enforce App Check in code from the first deploy. Observe metrics, test the internal-track build, then enforce Firestore in the console. Never ship a debug App Check provider.
3. **RevenueCat:** register the same application id, connect Play credentials, define the entitlement/product/Offering used by the app, use only the public Android SDK key in app config, and test purchase, restore, cancellation, and expiry.
4. **OneSignal:** configure Firebase Cloud Messaging credentials, use the production app id, and test permission, foreground/background/terminated delivery, `showdup://today`, and opt-out on hardware.
5. **Privacy:** replace every `{{...}}` marker in [docs/privacy-policy.md](docs/privacy-policy.md), have the owner/legal reviewer approve it, publish it at a stable public HTTPS URL, put that URL in Play Console and the app/store listing, and ensure the disclosures match actual retention/deletion behavior.
6. **Google Play:** enable Play App Signing; upload to Internal testing first; complete Data safety, content rating, ads, target audience, account deletion, and declarations for activity recognition, location, foreground service, exact alarms, full-screen intent, and notifications. Remove any permission the shipped journey cannot justify.
7. **Device gate:** clean install and upgrade on Android 8, Android 13, and current Android; test denied/revoked permissions, reboot, battery saver, offline/reconnect, timezone/DST, unavailable step sensor, inaccurate GPS, sign-out/data isolation, purchase restore, notification routing, and production-config startup.
8. **Rollout:** promote only the tested AAB. Start staged rollout; monitor Play vitals, Functions errors/latency, Firestore denials, notifications, purchases, and support. Record Git SHA, AAB SHA-256, version code, backend deploy time, and rollback owner.

CI deliberately rejects moderate-or-higher production npm advisories. Resolve audit findings before calling the release green.
