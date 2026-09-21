# Production completion audit

This audit maps the supplied product plan to the shipping Android code. A
checked product item means it is implemented and covered by source/runtime or
automated evidence; it does not replace the external Play Console gates below.

## Product plan

- [x] Fixed package ID `com.rayyanshaikh.orbit`.
- [x] Local-first product: commitments, evidence, attempt rollover, history and
  reminders do not require a backend or scheduled server scan.
- [x] Walking completion based on new hardware step-counter readings after the
  attempt starts, with minimum-duration and implausible-pace checks.
- [x] Arrival-and-stay completion based on accurate, non-mock foreground
  location fixes and continuous dwell. The app clearly says this proves
  presence, requires opening/tapping a reminder to start, and does not request
  background location.
- [x] User-selected weekdays, timezone, start/end window, reminder interval,
  maximum reminder count and gentle/explicit loud modes.
- [x] AlarmManager schedules one durable pulse at a time. Manual or 30-second
  automatic snooze shortens later gaps; completion cancels the sequence, and
  six pulses/two hours/window end marks it expired.
- [x] “End today without completing” stops the attempt and records abandonment.
  Sensor/permission loss records “Unable to verify” without awarding completion
  or breaking an existing streak.
- [x] Free: one active commitment, supported verification and seven visible days
  of history.
- [x] Pro: up to 20 active commitments, per-weekday time windows, every attempt
  from the last two years, history patterns, buddy summary sharing and optional
  selected-app restrictions.
- [x] Restrictions cover only packages explicitly chosen by the user and only
  during active windows. ShowdUp, Android/system permission surfaces, Settings,
  the default dialer and recognized emergency packages are excluded.
- [x] Accessibility disclosure states the exact use. The service observes only
  foreground package changes and does not read screen contents, typed text,
  notifications or passwords, or inject input.
- [x] Users retain the ability to end today, disable Accessibility access, clear
  data or uninstall. The product never claims an unbreakable lock.
- [x] RevenueCat uses a stable anonymous device-local app-user ID and grants Pro
  only from the exact `pro` entitlement. Missing/stale entitlement state fails
  closed for paid restrictions while free reminders continue.
- [x] Purchase, restore and renewal wording is present. Price and trial details
  come from the live Google Play products through RevenueCat, not hard-coded
  marketing copy.
- [x] Optional native pet overlay has explicit permission, persistent
  attribution, safe teardown, user controls, and reboot restoration by tap.
- [x] Battles use Firebase only for authentication, membership, expiring
  invites, aggregate outcome scoring and pet state. No commitment titles,
  sensor readings, coordinates or evidence are uploaded.
- [x] No OneSignal dependency or periodic Firebase commitment scan remains.
- [x] LeetCode beta verifies ownership with a one-time public-profile code and
  counts accepted submissions from the public profile. Service outages make an
  attempt unverifiable instead of failed.

The 1.0 release deliberately does not promise Health Connect workouts,
flashcards or publishing integrations. Those remain disabled or out of scope
until their integrations, device tests and policy declarations are complete.

## Verified repository evidence

- `flutter analyze`: clean.
- Flutter tests: 77 passed (2026-09-21), including every navigation
  destination, all attempt states, free/Pro gates, restart recovery, pet
  transitions, scoring, unverifiable exclusions and the design system.
- Android unit tests cover the alarm schedule, focus and catch policies,
  including which reaches get the full Caught screen and which get the flash.
- Release builds now run R8 (`isMinifyEnabled`, `isShrinkResources`,
  `android/app/proguard-rules.pro`). A full `assembleRelease` on 2026-09-18
  shrank, obfuscated and dexed the app and wrote `mapping.txt`; it stopped only
  at signing, because the keystore lives outside the repository.
- The catch shows ShowdUp's own full screen on the first reach of an attempt
  and a two-second accessibility overlay ("Quick catch", Settings) after that,
  followed by the system Home action. The overlay needs no draw-over
  permission, falls back to the full screen when it cannot be shown or when
  TalkBack is on, and one app open counts one reach.
- `public/` is on the current brand and carries the privacy policy plus the
  Play-required data deletion page at `/delete-account/` (not yet deployed).
- Store icon, feature graphic and six phone screenshots were re-rendered from
  the app code on the current brand, at Play's limits (2:1, no alpha).
- The Pro page shows the store's live prices and trial from RevenueCat, and
  lists only perks the build ships (the catch and Battles hide when off).
- Social scoring tests: 3 passed; Firestore/Auth/Functions emulator tests: 4
  passed, covering unauthorized access, server-only writes, capacity and
  idempotency. Obsolete cloud commitment/evidence code has been removed. The
  social callables have zero idle instances, two-instance caps, 15-second
  timeouts, App Check enforcement and daily per-user limits; idempotency events
  expire after 14 days.
- Dormant Firebase commitment listeners and email/password authentication UI
  were removed so only anonymous/Google Battles can reach Firebase.
- Android alarm-policy unit tests and a fresh native Kotlin compile passed after
  overlay-revocation, exact-alarm fallback and blocker safety-list hardening.
- A fresh signed release AAB for version `1.0.0+3` built from the redesigned
  `main` and its JAR signature verified on 2026-09-21. SHA-256:
  `1E9C995E5DBEE749F462730DAEFB30E8644366D4A35F888852166EB0A4319944`.
  The matching V2-signed APK SHA-256 is
  `82F533856457F3DDE0B6F85267EEE5B26508A476ABE984D2D3EFDB9CFD14C942`.
  It is still not a Play release candidate until the external gates below are
  complete.
- Store icon, feature graphic and five labeled release screenshots are under
  `docs/store-assets/`.
- The static privacy site under `public/` renders correctly at desktop width.
- Firebase Hosting and the social-only Firestore rules are deployed to
  `showdup-f0799`; `/`, `/privacy/`, and `/i/ABC123` return HTTP 200.
- Firebase anonymous authentication is enabled, the Hosting domains are
  authorized, the upload certificate SHA-1/SHA-256 are registered, and the
  hardened server-only Firestore rules are deployed.
- `FIREBASE_COST_GUARDRAILS.md` fixes the initial engineering ceiling at 25,000
  daily active battle users and requires measured rollout before raising it.

## External gates — not yet proven

Account invariant: Google Play is owned by Rayyan; Firebase/Google Cloud and
RevenueCat are owned by Harshita. Deployment tooling fails closed when the
Firebase CLI is signed into any other account. See `ACCOUNT_MAP.md`.

- [ ] Rotate/reset the exposed upload key and update ignored local signing
  credentials.
- [ ] Add a real public support/developer contact to the Play listing and policy.
- [x] Deploy Hosting, verify the signed-out `/privacy/` URL, and set it as
  `PRIVACY_POLICY_URL`. The prior CLI credential was revoked after diagnostic
  output exposed it; re-authentication must use the designated Harshita account
  and pass the deployment account guard.
- [x] Google Play subscriptions `showdup_pro_monthly` and
  `showdup_pro_annual` have active India base plans at ₹80 monthly and ₹400
  annual. No introductory offer or trial is currently configured.
- [x] RevenueCat has valid Play service-account credentials, both products are
  attached to the current `default` offering and exact `pro` entitlement, and
  Google developer notifications are connected to
  `projects/showdup-f0799/topics/Play-Store-Notifications`.
- [ ] Complete Play payments-profile identity, merchant, tax and bank details.
- [ ] Complete Data safety, Accessibility, foreground-service, exact-alarm and
  full-screen-intent declarations plus overlay/special-use FGS review and any
  requested demonstration video.
- [x] Places API (New) is enabled with a dedicated key restricted to
  `com.rayyanshaikh.orbit`, the upload and Play app-signing SHA-1 certificates,
  and Places API (New) only. Autocomplete and place-details traffic is capped
  at 200 requests/day and 30 requests/minute each.
- [ ] Test gym and destination search from a Play-installed build on a physical
  device, then redeploy the updated public privacy policy.
- [ ] Finish activation of the linked Cloud Billing account. Blaze is linked
  and Google Cloud account verification is currently under review, but the
  billing account is not yet open, so the six social functions and Firestore
  TTL policies cannot yet be published.
- [ ] Configure a low Cloud Run Functions spend-cap budget after billing is
  active. The overall Firebase budget is alerts-only and does not stop
  Firestore charges.
- [ ] Enable Google authentication. Anonymous authentication, Hosting and
  social-only Firestore rules are live. App Check and final `assetlinks.json`
  additionally require the Play Integrity link/final Play signing SHA-256
  certificate.
- [ ] Replace the development mascot glyphs with the approved transparent
  happy/uneasy/sad/cracked/recovery/burst PNG asset set.
- [ ] Install from an internal/closed Play track and pass purchase, restore,
  cancel, renewal, grace-period, refund/revocation and expiry tests.
- [ ] Pass the physical Android 13/14/15 matrix for GPS walking time/distance,
  destination arrival, gym dwell,
  denied permissions, reboot, force-stop, Doze, OEM battery saving, overlapping
  commitments and Accessibility escape behavior.
- [ ] Satisfy the production-access testing requirement shown for this specific
  developer account, then use a small staged rollout and monitor Android vitals.

Until every unchecked gate has direct evidence, this is not a safe public
production rollout.
