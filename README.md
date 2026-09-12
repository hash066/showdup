# ShowdUp

ShowdUp is a local-first Android alarm and commitment tracker. The first screen
offers a regular alarm (handed to the installed Clock app) or a verified
commitment alarm. Commitments use presets rather than free-form check-ins:
foreground GPS walking time/distance/destination or a fixed 150 m /
five-minute gym visit.
ShowdUp Pro uses RevenueCat and can cover only the distracting apps selected by
the user during an active attempt.

The production flow is local-first. Commitments, attempts, reminders, sensor
evidence, and history live on the Android device. Firebase remains available
for an explicitly reviewed future backup feature, but the app has no scheduled
backend scan and does not require Firebase to work.

Free supports one recurring commitment with selected weekdays. Pro adds
multiple commitments, per-weekday time windows, two years of history and
patterns, optional buddy check-ins, and selected-app restrictions until
completion.

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android application ID is fixed at `com.rayyanshaikh.orbit`.

## Release

Production builds require an ignored `config.release.json` containing the
RevenueCat Android public SDK key and an ignored `android/key.properties` for
the upload key:

```powershell
.\tool\build_release.ps1
```

See [docs/RELEASE.md](docs/RELEASE.md) for release checks,
[docs/PLAY_CONSOLE.md](docs/PLAY_CONSOLE.md) for external setup and declarations,
and [docs/PRODUCTION_AUDIT.md](docs/PRODUCTION_AUDIT.md) for the plan-to-evidence
completion matrix. Listing copy and assets are in
[docs/STORE_LISTING.md](docs/STORE_LISTING.md).
Do not upload a bundle until every external checklist item is complete.

Gym search uses the native Places SDK for Android. Copy
`android/secrets.properties.example` to the ignored
`android/secrets.properties`, add an Android-restricted `PLACES_API_KEY`, and
enable only Places API (New). Without a key the app still builds and current-
location pinning remains available, but search reports a clear setup error.
See [docs/MAPS_SETUP.md](docs/MAPS_SETUP.md).
