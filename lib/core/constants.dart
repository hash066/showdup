/// FROZEN CONTRACT. Do not edit without stopping every agent first.
class K {
  K._();

  static const packageName = 'com.rayyanshaikh.orbit';

  // Firestore collections
  static const usersCol = 'users';
  static const commitmentsCol = 'commitments';
  static const attemptsCol = 'attempts';

  // RevenueCat
  static const entitlementPro = 'pro';
  static const offeringDefault = 'default';
  static const pkgMonthly = r'$rc_monthly';
  static const pkgAnnual = r'$rc_annual';
  static const productMonthly = 'showdup_pro_monthly';
  static const productAnnual = 'showdup_pro_annual';

  // Platform channels
  static const alarmChannel = 'app.showdup/alarm';
  static const alarmEvents = 'app.showdup/alarm_events';
  static const stepsChannel = 'app.showdup/steps';
  static const stepsEvents = 'app.showdup/steps_events';
  static const locationChannel = 'app.showdup/location';
  static const locationEvents = 'app.showdup/location_events';
  static const blockerChannel = 'app.showdup/blocker';

  // Callable function names
  static const fnCreateCommitment = 'createCommitment';
  static const fnUpdateCommitment = 'updateCommitment';
  static const fnSubmitEvidence = 'submitEvidence';
  static const fnEndAttempt = 'endAttempt';

  // Limits
  static const freeMaxActiveCommitments = 1;
  static const proMaxActiveCommitments = 20;

  /// attemptId is deterministic. Both client and server must derive it
  /// exactly this way or idempotency breaks.
  static String attemptId(String commitmentId, String localDate) =>
      '${commitmentId}_$localDate';
}
