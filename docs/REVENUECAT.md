# RevenueCat and Google Play subscriptions

The app side is finished: `lib/services/billing.dart` configures RevenueCat
with an anonymous device-local user, unlocks Pro only from the active `pro`
entitlement (and relocks it at expiry), shows RevenueCat's paywall for the
current offering, restores purchases, and reads the live prices for the Pro
page. The Google Play app, products, RevenueCat entitlement/offering, Play API
credentials and real-time developer notifications were connected and verified
on 2026-09-17. Re-check the items below before every release; do not recreate
them under a different account. See `ACCOUNT_MAP.md` for ownership.

Identifiers the code expects — use them exactly:

| What | Value |
| --- | --- |
| Package | `com.rayyanshaikh.orbit` |
| Monthly subscription | `showdup_pro_monthly`, base plan `monthly` |
| Annual subscription | `showdup_pro_annual`, base plan `annual` |
| RevenueCat entitlement | `pro` |
| RevenueCat offering | `default`, marked Current |
| Packages | `$rc_monthly` → monthly, `$rc_annual` → annual |

## 1. Play Console: the subscriptions

Monetize with Play → Products → Subscriptions → Create subscription.

1. `showdup_pro_monthly`, name "ShowdUp Pro Monthly". Its active `monthly`
   base plan is auto-renewing, 1 month, ₹80 in India, with a 7-day grace
   period and account hold enabled.
2. `showdup_pro_annual`, name "ShowdUp Pro Annual". Its active `annual` base
   plan is auto-renewing, 1 year, ₹400 in India, with a 14-day grace period
   and account hold enabled.

No introductory offer or free trial is currently configured. The app reads
both price and trial state from the store, so it must not display trial copy
unless a real Play offer is activated later.

## 2. Google Cloud: the service account RevenueCat uses

The saved credentials currently validate. If RevenueCat stops reporting
"Valid credentials", verify the three requirements below before replacing the
service account or creating another app.

1. In the Google Cloud project linked to the Play developer account, enable
   **Google Play Android Developer API** and **Cloud Pub/Sub API**.
2. Create a service account (IAM → Service accounts), give it the
   **Pub/Sub Admin** role, create a JSON key and download it. Keep that file
   out of the repository.
3. In Play Console → Users and permissions → Invite new user, invite the
   service account's email with app access to ShowdUp and these permissions:
   View app information and download bulk reports; View financial data,
   orders and cancellation survey responses; Manage orders and subscriptions.

Google can take up to 36 hours to accept new credentials. RevenueCat shows
"Valid credentials" when it works.

## 3. RevenueCat dashboard

1. Project → Apps → add a **Google Play** app for `com.rayyanshaikh.orbit`,
   upload the JSON key from step 2, and turn on **Real-time developer
   notifications** (RevenueCat creates the Pub/Sub topic; paste its name into
   Play Console → Monetization setup → Real-time developer notifications, then
   send a test notification).
2. Products → import from Play: `showdup_pro_monthly:monthly` and
   `showdup_pro_annual:annual`.
3. Entitlements → `pro` (already exists) → attach both products.
4. Offerings → `default` → packages `$rc_monthly` and `$rc_annual` with the
   matching products. Make it the **Current** offering.
5. The `default` offering has a RevenueCat paywall. Keep it consistent with the
   current ShowdUp design and with the live Play products. It must not display
   a trial badge while no Play trial offer exists. The original palette was:
   background `#0E0E0C`, text `#F2EEE6`, accent and button `#5CF0BE` with
   `#0E0E0C` text.
6. API keys → copy the **Google Play public SDK key** (starts with `goog_`).

## 4. The build

Put that key into the ignored `config.release.json` at the repository root
(it already has the privacy URL):

```json
"REVENUECAT_ANDROID_KEY": "goog_…"
```

Then build the bundle. The script refuses a missing, placeholder or Test Store
key, runs the analyzer and tests, and builds with R8:

```powershell
.\tool\build_release.ps1
```

## 5. Testing real purchases

Sideloaded builds cannot buy. Upload the `.aab` to **Internal testing**, add
yourself under Setup → **License testing** and as an internal tester, then
install from the tester opt-in link. License testers are not charged, and test
renewals are fast (a month renews in about five minutes).

Walk through, and check RevenueCat's customer page after each:

- Buy monthly; Pro turns on and the animal companions unlock.
- Cancel in Play; Pro stays until expiry, then turns off by itself.
- Buy annual; Pro turns on and the ₹400 yearly plan is shown at checkout.
- Clear app data, open Pro, Restore purchases; Pro comes back.
- Let a test renewal fail (Play's test card "declines after a while"); grace
  period and account hold behave, and Pro drops when it should.

For free local testing before any of this exists, `tool/build_pro_sandbox.ps1`
builds a debug app against RevenueCat's Test Store (`config.sandbox.json`).
