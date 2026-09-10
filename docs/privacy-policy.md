# Privacy Policy for ShowdUp

**Effective date:** {{EFFECTIVE_DATE}}

> Publication blocker: replace every `{{PLACEHOLDER}}`, verify this policy against the production implementation and vendor settings, and obtain owner/legal approval. This template is not legal advice.

{{LEGAL_ENTITY_NAME}} ("we", "us", or "our") provides the ShowdUp mobile application. This policy explains what information ShowdUp processes, why it is processed, how it is shared, and the choices available to users.

## Information we process

- **Account and profile information:** authentication identifier and the profile fields a user provides, such as display name, handle, photo URL, and timezone.
- **Commitment and verification information:** commitment schedules, reminders, completion state, streak/statistics, step counts and measurement timing, and location evidence such as coordinates, accuracy, and dwell/arrival signals when a location commitment is used.
- **Device and notification information:** OneSignal identifiers, notification permission/state, and technical delivery information needed to send reminders.
- **Purchase information:** product, entitlement, subscription, and transaction status supplied through Google Play and RevenueCat. We do not receive full payment-card details.
- **Technical and security information:** app/device metadata, authentication and server logs, errors, IP address, and abuse/security signals processed by our infrastructure and service providers.

ShowdUp requests physical-activity and location permissions only for the verification features selected by the user.

ShowdUp does not request `ACCESS_BACKGROUND_LOCATION`. Location verification starts only when the user explicitly starts it from an open location attempt (for example after tapping a reminder). A user-started foreground service (`FOREGROUND_SERVICE_LOCATION`) checks arrival and continuous dwell while that verification is running. The wizard may request a one-shot foreground location fix so the user can set a place; that is not background tracking. After process death, location tracking does not resume in the background; only step tracks may resume. Location is not collected when the user has not started verification or when the app is closed without an active location verification session.

When a step or location commitment is completed, the app calls the Cloud Function `submitEvidence`. That function writes a sanitized evidence object onto the matching Firestore attempt document (`type`, `payload`, `capturedAt`, and a plausibility `confidence`). Step payloads include steps since baseline, elapsed duration, and baseline time. Location payloads include coordinates, accuracy, a mock-location flag, dwell timing, and a previous fix when present. Clients cannot write attempt documents directly. Evidence remains on the attempt until that attempt is deleted, including when the user deletes their account.

## How we use information

We use information to authenticate users; create and operate commitments; verify progress or completion; schedule reminders; preserve or calculate streaks and statistics; provide paid entitlements; prevent fraud and abuse; troubleshoot and secure the service; comply with law; and respond to support or privacy requests.

## Sharing and service providers

We disclose information as needed to providers acting for us, including:

- **Google Firebase** for authentication, database, server functions, application protection, and operational infrastructure;
- **RevenueCat and Google Play** for purchases, subscriptions, and entitlements; and
- **OneSignal** for notifications and delivery management.

These providers process information under their own terms and privacy notices. We may also disclose information when required by law, to protect rights and safety, or as part of a merger, financing, acquisition, or sale with appropriate safeguards.

ShowdUp does not display third-party ads. We do not sell personal information and we do not share personal information for targeted advertising.

## Retention and deletion

We retain information only for the periods needed for the purposes above, legal obligations, dispute resolution, and security. Account profile data, commitments, attempts, and the evidence stored on those attempts are removed when the user deletes their account through the in-app flow, which calls the `deleteAccount` Cloud Function. That function deletes the user's commitments, attempts, user document, and Firebase Auth user. Subscription billing is separate and is not cancelled by account deletion. {{INSERT_SPECIFIC_RETENTION_PERIODS_FOR_ACCOUNT_DATA_COMMITMENTS_EVIDENCE_SERVER_LOGS_AND_BACKUPS}}

Users can request account and data deletion from **Settings → Delete account** (password re-authentication is required) or at {{PRIVACY_CONTACT_EMAIL}}. We will verify requests and explain any information that must be retained. The public account-deletion request URL supplied to Google Play is {{PUBLIC_ACCOUNT_DELETION_URL}}.

## Security and international processing

We use reasonable administrative, technical, and organizational safeguards. No storage or transmission system is completely secure. Information may be processed in {{COUNTRIES_OR_REGIONS_OF_PROCESSING}}; where required, we use an applicable transfer mechanism.

## User choices and rights

Users may decline or revoke activity, location, exact-alarm, and notification permissions in Android settings, although the related feature may no longer work. Users may manage subscriptions through Google Play. Depending on location, users may have rights to access, correct, delete, restrict, object to, or export personal information, and to appeal or complain to a regulator. Submit requests to {{PRIVACY_CONTACT_EMAIL}}.

## Children

ShowdUp is intended for {{MINIMUM_USER_AGE_OR_TARGET_AUDIENCE}}. {{INSERT_CHILDREN_DATA_POSITION_AND_PARENT_GUARDIAN_PROCESS_IF_APPLICABLE}}.

## Changes

We may update this policy. We will post the revised policy at {{PUBLIC_PRIVACY_POLICY_URL}} and change the effective date. We will provide any additional notice required by law.

## Contact

{{LEGAL_ENTITY_NAME}}  
{{POSTAL_ADDRESS}}  
Email: {{PRIVACY_CONTACT_EMAIL}}  
Privacy policy URL: {{PUBLIC_PRIVACY_POLICY_URL}}
