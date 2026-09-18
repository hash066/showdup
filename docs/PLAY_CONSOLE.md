# Play Console production setup

The fixed Android package is `com.rayyanshaikh.orbit`. This file is an operator
checklist, not proof that the external Console settings are complete.

## Monetization and payout

Create Google Play subscription products with the exact IDs
`showdup_pro_monthly` and `showdup_pro_annual`. Connect the Play app and service
account to RevenueCat, attach both products to packages in the current offering,
and make both grant the exact RevenueCat entitlement `pro`.

The approved initial India pricing is:

| Product ID | Base plan ID | Renewal period | India price |
| --- | --- | --- | --- |
| `showdup_pro_monthly` | `monthly` | 1 month, auto-renewing | ₹79 |
| `showdup_pro_annual` | `annual` | 1 year, auto-renewing | ₹399 |

Add tester Google accounts under Play Console license testing. License testers
use Google's test payment methods and are not charged; they do not need promo
codes. Subscription promo codes are optional acquisition offers created only
after a published subscription exists, and grant a limited free trial rather
than permanent Pro access.

The customer pays Google Play. RevenueCat observes and validates the store
transaction and tells ShowdUp whether `pro` is active; it does not collect the
customer's payment or pay the developer. Complete the Play Console payments
profile, merchant verification, tax details, and bank account so Google can pay
store proceeds after its fees, taxes, refunds, and payout timing.

Validate purchase, restore, cancellation, renewal, grace period, billing issue,
refund/revocation, and expiry from a Play-installed internal-test build. A
sideloaded APK is not a valid end-to-end billing test.

Before Play account approval, `tool/build_pro_sandbox.ps1` builds a separate
debug APK against RevenueCat Test Store. The Test Store monthly and yearly
products grant the exact `pro` entitlement and sandbox access is currently open
to anybody with that build. This validates ShowdUp's entitlement gates but does
not replace the Play Billing tests above.

## Data safety source of truth

Answer from the actual release behavior and the current RevenueCat/Google SDK
disclosures. The current app stores commitments, schedules, attempt history,
legacy step evidence, GPS walk/gym evidence, reminder activity, and selected-
app packages locally. Google Places processes place-search text and selected
results. The app sends purchase identifiers and subscription status needed for
billing to Google Play and RevenueCat. Optional Battles send Firebase a
chosen identity, mascot, membership, aggregate outcome, snooze count, score and
pet state. They do not upload commitment titles, sensor readings, coordinates,
verification evidence or Accessibility events. The app has no ads.

Do not claim that no data is collected merely because most product data remains
on-device: third-party billing SDK behavior still has to be declared. Re-check
the current RevenueCat data-safety guidance immediately before submission.

## Sensitive capability declarations

- Accessibility: describe the optional selected-app hold ("the catch"), its
  prominent in-app disclosure, the exact foreground-package comparison, and
  that it does not read screen contents, text, passwords, or inject input. The
  service declares `android:isAccessibilityTool="false"` because it is a
  product feature, not an assistive tool. Say that the first catch of a day
  opens ShowdUp's own full screen and later reaches show a two-second
  accessibility overlay before the system Home action, and that the overlay is
  ShowdUp's own text only and can be turned off in Settings. Supply Play's
  requested demonstration video showing both.
- Foreground services: declare location verification and, where requested by
  target Android version, health/step verification. The visible ongoing
  notification explains active verification.
- Exact alarms: the core user-facing function is delivering reminders inside
  user-created commitment windows. The app detects when exact alarms are not
  granted and falls back to best-effort alarms; never promise exact delivery on
  every OEM/device state.
- Full-screen intent: declare the high-priority user-created reminder use. The
  feature is permission/state checked and normal notifications remain the
  fallback.
- Location: foreground precise location only, after the user chooses a walk or
  gym rule. The app does not request background location.
- Physical activity: used only for on-device step verification.
- Installed apps: launcher packages are shown locally only so a Pro user can
  choose apps for the optional restriction feature.
- Display over other apps: the user-enabled pet and statistics overlay is
  visibly attributable to ShowdUp, has a persistent notification and off
  controls, and does not inspect content underneath it.
- Special-use foreground service: declare the accountability pet overlay and
  provide the exact manifest subtype text and review video if requested.

## Before production access or rollout

1. Rotate the exposed upload-key credentials; reset the upload key through Play
   if the current public key was already registered.
2. Publish `PRIVACY.md` at a public, active HTTPS URL with a real developer
   contact, then build with that exact `PRIVACY_POLICY_URL`. `public/privacy/`
   and `public/delete-account/` carry the hosted copies; enter the deletion URL
   in the Console's data-deletion field (Play requires both an in-app path,
   Settings → Delete data on this phone, and a web URL).
3. Complete app access, ads, content rating, target audience, news, health, and
   other declarations truthfully for the Console prompts shown to this account.
4. Upload the store assets listed in `store-assets/README.md`.
5. Complete the developer payments profile, bank account, tax information,
   countries, base prices, and subscription availability.
6. Pass the required testing track and production-access requirements shown for
   this developer account.
7. Run the physical-device and Play Billing matrix in `RELEASE.md` before any
   public rollout; begin with a small staged rollout and watch Android vitals.
