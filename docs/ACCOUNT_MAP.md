# ShowdUp account map

This file records ownership and non-secret identifiers. Never put passwords,
service-account JSON, SDK keys, upload-key material or bank details here.

| Service | Owner | Identifier |
| --- | --- | --- |
| Google Play Console | Rayyan | Developer `7191292381196905461`; app `4973406805153470897` |
| Android application | Google Play app above | `com.rayyanshaikh.orbit` |
| RevenueCat | Harshita | Project `b01fe03e`; Android app `app3f4200bcaf` |
| Firebase / Google Cloud | Harshita | Project `showdup-f0799` |
| GitHub | `hash066` | `https://github.com/hash066/showdup` |
| Android upload signing | Local release machine | Ignored `android/key.properties` and keystore |

## Connection

Rayyan's Play developer account owns the application, subscriptions, merchant
profile and customer payments. A service account from Harshita's Google Cloud
project is invited to that Play app with the minimum reporting, financial and
subscription permissions required by RevenueCat. RevenueCat uses that service
account and Play real-time developer notifications to validate purchases and
grant the exact `pro` entitlement.

The release APK/AAB contains only RevenueCat's public Google Play SDK key from
ignored `config.release.json`. Google Play pays the configured Play merchant
bank account; RevenueCat does not receive or transfer subscription revenue.

Firebase remains separate from billing. It supports optional accounts and
social competition; local alarms, commitments, evidence and purchase state do
not depend on Firebase database scans.

## Release invariants

- Package name stays `com.rayyanshaikh.orbit`.
- Firebase CLI and deployments use the designated Harshita operator account.
- Google Play uploads use Rayyan's existing app, never a newly created app.
- RevenueCat offering `default` is Current and grants `pro` from
  `showdup_pro_monthly:monthly` and `showdup_pro_annual:annual`.
- Secrets remain ignored and are never copied into GitHub documentation.
