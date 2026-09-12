# Android release checklist

The Android package name is fixed: `com.rayyanshaikh.orbit`.

All Firebase and RevenueCat release operations must use the designated Harshita
owner account. The Firebase deployment scripts verify the ignored
`FIREBASE_OPERATOR_EMAIL` value and abort if another CLI account is active.

## Local secrets

Never commit `android/key.properties`, the upload keystore, or
`config.release.json`. Start with `android/key.properties.example`, copy it
to `android/key.properties`, and supply the real keystore path and values
locally.

`config.release.json` must also contain an active HTTPS
`PRIVACY_POLICY_URL` that displays `docs/PRIVACY.md` (with your real developer
contact details) without requiring a login.

The repository includes a matching static Firebase Hosting site in `public/`.
After confirming the policy and the public developer contact, deploy only that
site with:

```powershell
.\tool\deploy_privacy.ps1
```

This script takes the real project ID from the ignored release config and uses
`--only hosting`; it does not deploy Functions or Firestore resources. Confirm
the resulting `/privacy/` URL in a signed-out browser, put it in
`PRIVACY_POLICY_URL`, and then run the release builder.

The RevenueCat Android public SDK key is intentionally passed at build time,
not checked into Dart source. Build the Play artifact from the repository
root with:

```powershell
.\tool\build_release.ps1
```

Do not omit `--dart-define-from-file=config.release.json`; without
`REVENUECAT_ANDROID_KEY`, the production paywall is deliberately disabled.

For free local Pro purchase testing before Play approval, copy
`config.sandbox.example.json` to the ignored `config.sandbox.json`, set the
RevenueCat Test Store public key, and run:

```powershell
.\tool\build_pro_sandbox.ps1
```

This produces only a debug APK. Release builds reject keys beginning with
`test_`, so the Test Store configuration cannot accidentally become a Play
artifact.

## RevenueCat and Play Console

Before testing the bundle, configure the following external state:

1. Create the RevenueCat Android app for `com.rayyanshaikh.orbit` and use its
   Android public SDK key in the local release config.
2. In Play Console create active subscription products
   `showdup_pro_monthly` and `showdup_pro_annual`.
3. In RevenueCat attach those products to the matching packages in the
   current/default offering, and grant the exact entitlement ID `pro`.
4. Connect RevenueCat to Play Developer API access using the required service
   account credentials.
5. Upload the signed AAB to an internal testing track, add both internal-track
   and license-test users, then install through the Play opt-in link. A
   sideloaded debug APK is not a valid subscription test.

Exercise purchase, cancellation, restore after clearing app data, renewal,
and expired entitlement flows before promoting the release.

## Play policy and device checks

Before production rollout:

1. Rotate the local upload-key passwords that were exposed during development.
   If this key is already registered with Play App Signing, use Play Console's
   upload-key reset flow.
2. Publish a privacy policy URL and complete Data safety for RevenueCat,
   foreground GPS walk/gym evidence, Google Places search, legacy
   physical-activity data, installed-app selection, and the fact that
   commitment data otherwise stays on-device.
3. Complete the AccessibilityService declaration and provide Play's required
   demonstration video. The disclosure shown before Android Settings must stay
   in the app.
4. Complete any exact-alarm, full-screen-intent, and foreground-service
   declarations requested by Play for the target SDK.
5. Test from the Play internal-testing install on physical Android 13, 14, and
   15 devices: reboot, force-stop, Doze, denied permissions, OEM battery saver,
   GPS walking time/distance/destination, gym dwell, overlapping commitments,
   blocker escape,
   per-weekday Pro windows, buddy sharing, purchase, restore, expiry, and
   offline launch.
6. Confirm the public developer contact email, support URL, store listing,
   content rating, countries, pricing, and tax/payout profile in Play Console.

## Firebase social setup and cost guardrail

The production app is local-first and does not need Cloud Functions for
reminders, evidence, rollover, or history. Firebase is used by optional Battles
for anonymous/Google identity, membership, expiring invites and aggregate
scores. There is deliberately no scheduled collection scan. Before deployment,
enable both Auth providers, register Play Integrity App Check, deploy the
reviewed Functions/Rules/Hosting resources, publish the final Play-signing
`assetlinks.json`, and set billing budgets and quota alerts.

If an older test project already deployed `rolloverAttempts`, delete that
scheduled function and its Cloud Scheduler job before launch; removing the
export from this repository does not retroactively stop an old deployment.
