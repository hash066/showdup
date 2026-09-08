class AppConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const revenueCatKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const oneSignalId = String.fromEnvironment('ONESIGNAL_APP_ID');
  static const useEmulators = bool.fromEnvironment('USE_EMULATORS');
  static const emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );
  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;
}
