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

The plan deliberately does not promise Health Connect workouts, LeetCode,
flashcards or publishing integrations. Those were future examples and require
separate authorized integrations and policies before they can be advertised.

## Verified repository evidence

- `flutter analyze`: clean.
- Flutter tests: 34 passed, including every navigation destination, all attempt
  states, free/Pro gates, restart recovery, pet transitions, scoring and
  unverifiable exclusions.
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
- A fresh release AAB including the final local hardening built and its JAR
  signature verified on 2026-09-12. SHA-256:
  `B16825CC521882DE319AA1DF5A883BE09230484B56824D5521EBE6740FF6D0F8`.
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

Account invariant: all Firebase and RevenueCat release work must use the
designated Harshita owner account. Deployment tooling now fails closed when the
Firebase CLI is signed into any other account.

- [ ] Rotate/reset the exposed upload key and update ignored local signing
  credentials.
- [ ] Add a real public support/developer contact to the Play listing and policy.
- [x] Deploy Hosting, verify the signed-out `/privacy/` URL, and set it as
  `PRIVACY_POLICY_URL`. The prior CLI credential was revoked after diagnostic
  output exposed it; re-authentication must use the designated Harshita account
  and pass the deployment account guard.
- [ ] Create and activate Google Play subscriptions `showdup_pro_monthly` and
  `showdup_pro_annual`; configure ₹79 monthly and ₹399 annual India prices,
  countries, offers/trial and tax. Harshita's Play developer identity is under
  review, phone verification is consequently locked, and Create app is
  currently disabled.
- [ ] Connect the Play app/service account in RevenueCat, attach both products
  to the current offering and exact `pro` entitlement, and verify notifications.
  The exact `pro` entitlement and isolated Test Store monthly/yearly setup are
  complete; the saved Play service-account credentials currently fail RevenueCat
  validation and no real Play products exist yet.
- [ ] Complete Play payments-profile identity, merchant, tax and bank details.
- [ ] Complete Data safety, Accessibility, foreground-service, exact-alarm and
  full-screen-intent declarations plus overlay/special-use FGS review and any
  requested demonstration video.
- [ ] Enable Places API (New), add a separate Android-restricted key for the
  debug and final Play signing certificates, cap its quota, and test gym and
  destination search. Redeploy the updated public privacy policy afterward.
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
