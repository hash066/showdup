# Auto-verification scope

Only goals with evidence that ShowdUp can collect and explain should be
selectable. V1 enables:

| Preset | Evidence | Honest limitation |
| --- | --- | --- |
| Walk | Foreground GPS movement, measured by active time, distance, or arrival within 150 m of a chosen destination | Requires the app to be opened and the phone carried; it does not prove exercise intensity |
| Gym | Precise foreground location inside a fixed 150 m boundary for five continuous minutes | Proves presence, not a workout |

Candidates for later releases:

- Health Connect workout sessions, after separate health-data consent and
  Play health declarations.
- GitHub contributions using user OAuth and the official API.
- QR/NFC arrival at a user-owned location, labeled as scan verification rather
  than automatic completion.
- Screen-free or app-limit goals using the existing opt-in Accessibility
  service, with narrow scopes and fail-open behavior.

LeetCode is shown as unavailable. A public username or copied browser token is
not a production-grade authorization contract, and ShowdUp must not collect a
password/session cookie or promise verification through an undocumented
endpoint. Enable the preset only after a stable authorized integration exists.

Regular alarms use Android's standard Clock intent. Android does not provide a
portable contract for ShowdUp to read, synchronize or dismiss alarms owned by
Samsung/Google/Xiaomi Clock apps. Evidence-driven alarms therefore remain
ShowdUp-owned; the regular alarm action is an explicit handoff to Clock.
