# ShowdUp Privacy Policy

Effective: 12 September 2026

ShowdUp is a local-first Android accountability app. This policy explains what
the app uses, where information is stored, and which outside services are
involved.

## Information stored on your device

ShowdUp stores your timezone, commitments, weekly and per-day schedules, reminder activity,
attempt history, subscription feature state, and verification evidence in the
app's private storage. Legacy step evidence can include new step counts and
elapsed time. Walk evidence can include active duration, distance, coordinates,
accuracy and timestamps. Gym evidence can include the destination you chose,
coordinates, accuracy, timestamps and dwell duration. Place-search text and
the selected result are processed by Google Places when you open gym or
destination search.

ShowdUp does not upload commitment titles, step readings, coordinates or
verification evidence for social features. If you use Battles, Firebase stores
your chosen identity, mascot, membership and aggregate resolved outcome,
snooze, score and pet-state events. Android backup is disabled for the app.
Terminal attempt history is retained locally for up to two years.

If you choose “Share a buddy check-in” or “Share my day,” Android’s share sheet
sends the summary or image only to the destination you select. ShowdUp does not
maintain or upload a buddy list.

## Subscriptions and RevenueCat

ShowdUp uses RevenueCat to present subscription plans, validate purchases, and
decide whether Pro features are active. The app creates a random, device-local
RevenueCat app-user identifier. RevenueCat and Google Play can process that
identifier, purchase tokens, product and entitlement status, store/device
information, and transaction events needed to operate subscriptions. Google
Play processes the payment; ShowdUp does not receive card or bank details.

Deleting ShowdUp data or uninstalling does not cancel a Google Play
subscription. Subscriptions must be managed or canceled through Google Play.

RevenueCat's privacy information is available at
https://www.revenuecat.com/privacy/ and Google's privacy policy is available at
https://policies.google.com/privacy.

## Accessibility-based selected-app restrictions

Pro users can optionally enable ShowdUp's Android Accessibility service. During
an active restricted commitment, the service receives window-change events to
identify the package name of the foreground app. It compares that package name
with the apps you selected and can show a ShowdUp blocking screen.

ShowdUp does not use this service to read screen contents, typed text,
notifications, passwords, or form fields; it does not inject gestures or key
events; and it does not transmit Accessibility events or the selected-app list.
You can decline this feature, disable the service in Android Accessibility
settings, clear app data, or uninstall ShowdUp at any time. Core reminders and
verification remain available without Accessibility access.

## Android permissions

- Physical activity is used for step-counter verification.
- Precise foreground location is used only after you start an arrival-and-dwell
  verification. ShowdUp does not request background location permission.
- Notifications, alarms, foreground services, and boot completion are used to
  deliver agreed reminders and keep active verification running.
- Installed launcher apps are listed only so you can select optional Pro
  distractions. That list is not uploaded by the current production flow.
- Display over other apps is optional and shows the ShowdUp pet, score and
  controls. It cannot inspect the app underneath, is identified by a persistent
  notification, and can be disabled at any time.

## Firebase and Battles

Firebase Authentication creates an anonymous account when configured. Google
sign-in is optional for solo use and required to invite or join a Battle.
Firestore and Cloud Functions store battle profiles, memberships, expiring
invite codes and aggregate scores. They do not store commitment titles or raw
verification evidence, and there is no scheduled Firebase scan.

## Sharing, advertising, and sale

ShowdUp does not include advertising and does not sell personal data. Data is
shared with Google Play and RevenueCat as necessary for subscriptions, with
Firebase when Battles are used, or when required by law.

## Security and limits

On-device data is protected by Android's application sandbox. No software can
guarantee absolute security, and users with root-level device access may be
able to alter local data. Location and step evidence are plausibility signals,
not tamper-proof proof of a workout or productive activity.

## Children

ShowdUp is not directed to children under 13. Do not use the app if local law
requires parental consent that has not been provided.

## Changes and contact

Material changes will be reflected by updating the effective date and the
policy shown with the app. For privacy questions, use the developer contact
email displayed on ShowdUp's Google Play listing.
