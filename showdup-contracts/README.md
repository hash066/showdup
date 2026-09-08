# ShowdUp contracts (Agent 0 output)

These are the frozen interfaces from section 4 of the build plan. Every
other agent codes against them. **No agent may change a file in here.** If
a change is genuinely required, stop all agents, change it centrally, and
rebroadcast.

## Layout

```
lib/core/constants.dart              ids, collection names, channel names
lib/core/theme.dart                  design tokens
lib/models/enums.dart                persisted string enums
lib/models/verifier_config.dart      StepsConfig, LocationConfig + validation
lib/models/commitment.dart           Commitment, Schedule, Reminder, Restrictions
lib/models/attempt.dart              Attempt
lib/models/app_user.dart             AppUser, UserStats
lib/verification/verifier.dart       the Verifier interface (the extension point)
lib/verification/steps_verifier.dart      v1, stub for Agent 4
lib/verification/location_verifier.dart   v1, stub for Agent 4
lib/verification/verifier_registry.dart   the only file that knows what exists
lib/platform/alarm_channel.dart      Dart side of the alarm channel
lib/platform/steps_channel.dart      Dart side of the steps channel
lib/platform/location_channel.dart   Dart side of the location channel
functions/src/types.ts               server mirror of the Dart models
functions/src/validation.ts          schema + plausibility check signatures
functions/src/index.ts               the five function signatures
firestore.rules                      complete, working, ready to deploy
firestore.indexes.json               the three indexes you will need
android/.../AndroidManifest.xml.snippet   v1 permission set
```

## The three rules everything else depends on

1. **The client never sends a completion time.** `submitEvidence` stamps
   `completedAt` server side. Rules deny all client writes to `attempts/**`.
   This is what makes the whole product trustworthy.
2. **`isPro` is written only by the RevenueCat webhook.** And you must call
   `Purchases.logIn(firebaseUid)` after Firebase auth, or the webhook cannot
   map a purchase to a user and the paywall will unlock nothing.
3. **No `ACCESS_BACKGROUND_LOCATION` in v1.** Location verification runs in
   a foreground service started when the user taps a reminder. Adding
   background location means a Play declaration and a demo video, and the
   review time will not fit before the deadline.

## Definition of done for Agent 0

- [ ] `flutter analyze` clean
- [ ] `flutter test` runs green with zero tests
- [ ] `firebase emulators:start` boots with these rules loaded
- [ ] `npm run build` in `functions/` compiles
- [ ] App launches to a themed empty screen
