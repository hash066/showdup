# Google Play asset manifest

Upload these files to the main store listing:

| Play Console field | File | Size and format |
| --- | --- | --- |
| App icon | `high-res-icon.png` | 512 × 512, 32-bit PNG |
| Feature graphic | `feature-graphic.png` | 1024 × 500, 24-bit PNG |
| Phone screenshot 1 | `phone-01-welcome.png` | 1080 × 2160, 24-bit PNG |
| Phone screenshot 2 | `phone-02-alarms.png` | 1080 × 2160, 24-bit PNG |
| Phone screenshot 3 | `phone-03-proof.png` | 1080 × 2160, 24-bit PNG |
| Phone screenshot 4 | `phone-04-showed-up.png` | 1080 × 2160, 24-bit PNG |
| Phone screenshot 5 | `phone-05-history.png` | 1080 × 2160, 24-bit PNG |
| Phone screenshot 6 | `phone-06-research.png` | 1080 × 2160, 24-bit PNG |

Play rejects screenshots longer than twice their width and screenshots with an
alpha channel; these are exactly 2:1 and flattened onto ink.

They are rendered from the real app code with the real fonts, not mocked:

```powershell
flutter test --update-goldens tool/capture/store_test.dart
python tool/capture/store_assets.py
```

The first command renders into `tool/capture/out/store/`; the second checks the
Play limits, flattens and copies them here. Re-run both after any visible
change. The app screens use the visibly labeled preview data ("Preview · sample
data") with a 06:30 walk of 3,000 steps; they are not evidence that sensors,
OEM alarm behavior, the catch or Play Billing have passed device testing.
