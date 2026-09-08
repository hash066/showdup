class UserStats {
  const UserStats({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.completed = 0,
    this.abandoned = 0,
    this.unverifiable = 0,
  });

  final int currentStreak;
  final int longestStreak;
  final int completed;
  final int abandoned;
  final int unverifiable;

  Map<String, dynamic> toJson() => {
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'completed': completed,
        'abandoned': abandoned,
        'unverifiable': unverifiable,
      };

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        currentStreak: (j['currentStreak'] as num?)?.toInt() ?? 0,
        longestStreak: (j['longestStreak'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
        abandoned: (j['abandoned'] as num?)?.toInt() ?? 0,
        unverifiable: (j['unverifiable'] as num?)?.toInt() ?? 0,
      );
}

class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.timezone,
    this.handle,
    this.photoUrl,
    this.oneSignalId,
    this.isPro = false,
    this.proExpiresAt,
    this.stats = const UserStats(),
  });

  final String uid;
  final String displayName;
  final String timezone;
  final String? handle;
  final String? photoUrl;
  final String? oneSignalId;

  /// WEBHOOK ONLY. Never write from the client.
  final bool isPro;
  final DateTime? proExpiresAt;
  final UserStats stats;

  int get maxActiveCommitments => isPro ? 20 : 1;

  /// Only the fields a client is allowed to write.
  Map<String, dynamic> toClientWritableJson() => {
        'displayName': displayName,
        'timezone': timezone,
        if (handle != null) 'handle': handle,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (oneSignalId != null) 'oneSignalId': oneSignalId,
      };

  factory AppUser.fromJson(String uid, Map<String, dynamic> j) => AppUser(
        uid: uid,
        displayName: j['displayName'] as String? ?? '',
        timezone: j['timezone'] as String? ?? 'Asia/Kolkata',
        handle: j['handle'] as String?,
        photoUrl: j['photoUrl'] as String?,
        oneSignalId: j['oneSignalId'] as String?,
        isPro: j['isPro'] as bool? ?? false,
        stats: UserStats.fromJson(
            Map<String, dynamic>.from(j['stats'] as Map? ?? {})),
      );
}
