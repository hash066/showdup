class BattleMemberScore {
  const BattleMemberScore({
    required this.uid,
    required this.displayName,
    required this.mascot,
    required this.score,
    required this.eligibleAttempts,
    required this.rank,
    required this.petMood,
  });

  final String uid;
  final String displayName;
  final String mascot;
  final int score;
  final int eligibleAttempts;
  final int rank;
  final String petMood;
  bool get provisional => eligibleAttempts < 3;

  factory BattleMemberScore.fromJson(String uid, Map<String, dynamic> data) =>
      BattleMemberScore(
        uid: uid,
        displayName: data['displayName'] as String? ?? 'Player',
        mascot: data['mascot'] as String? ?? 'dot',
        score: (data['score'] as num?)?.toInt() ?? 0,
        eligibleAttempts: (data['eligibleAttempts'] as num?)?.toInt() ?? 0,
        rank: (data['rank'] as num?)?.toInt() ?? 0,
        petMood: data['petMood'] as String? ?? 'happy',
      );
}

class Battle {
  const Battle({
    required this.id,
    required this.name,
    required this.creatorUid,
    required this.timezone,
    required this.weekKey,
    required this.memberUids,
    required this.active,
  });

  final String id;
  final String name;
  final String creatorUid;
  final String timezone;
  final String weekKey;
  final List<String> memberUids;
  final bool active;

  factory Battle.fromJson(String id, Map<String, dynamic> data) => Battle(
    id: id,
    name: data['name'] as String? ?? 'Weekly battle',
    creatorUid: data['creatorUid'] as String? ?? '',
    timezone: data['timezone'] as String? ?? 'UTC',
    weekKey: data['weekKey'] as String? ?? '',
    memberUids: (data['memberUids'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    active: data['active'] == true,
  );
}

class BattleInvite {
  const BattleInvite({
    required this.code,
    required this.url,
    required this.expiresAt,
  });
  final String code;
  final String url;
  final DateTime expiresAt;
}
