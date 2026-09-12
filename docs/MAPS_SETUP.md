# Gym place search

ShowdUp uses Google Places Autocomplete (New) through the native Android SDK.
The selected place ID, display name, address and coordinates remain in local
commitment storage. Users never edit raw coordinates, radius or dwell time.

1. Enable **Places API (New)** in the Google Cloud project.
2. Create a separate Android API key.
3. Restrict it to package `com.rayyanshaikh.orbit` and the debug/Play signing
   certificates.
4. Restrict the key to **Places API (New)** only and set a conservative quota.
5. Copy `android/secrets.properties.example` to
   `android/secrets.properties` and replace the placeholder.

`android/secrets.properties` is ignored. The checked-in default is deliberately
invalid so an accidental public build cannot spend Maps quota. Autocomplete
uses one session token and requests only ID, formatted address and location in
the details call. The visible name comes from the selected autocomplete
prediction, avoiding a duplicate higher-tier display-name field.
