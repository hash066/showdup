import 'enums.dart';

/// FROZEN CONTRACT: the shape stored in commitments.verifierConfig.
/// The server validates the same schemas. Keep both in sync.
sealed class VerifierConfig {
  const VerifierConfig();
  VerifierType get type;
  Map<String, dynamic> toJson();

  /// Returns null when valid, else a human readable reason.
  String? validate();

  static VerifierConfig fromJson(String type, Map<String, dynamic> j) =>
      switch (VerifierType.from(type)) {
        VerifierType.steps => StepsConfig.fromJson(j),
        VerifierType.location => LocationConfig.fromJson(j),
        VerifierType.walk => WalkConfig.fromJson(j),
        VerifierType.focus => FocusConfig.fromJson(j),
        VerifierType.healthWorkout => HealthWorkoutConfig.fromJson(j),
        VerifierType.leetcode => LeetCodeConfig.fromJson(j),
        VerifierType.tagScan => TagScanConfig.fromJson(j),
      };
}

/// A QR code or barcode placed where the habit happens. Only a SHA-256 hash
/// of the code's value is stored, never the value itself.
class TagScanConfig extends VerifierConfig {
  const TagScanConfig({required this.codeHash, this.label});

  final String codeHash;
  final String? label;

  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  @override
  VerifierType get type => VerifierType.tagScan;

  @override
  String? validate() {
    if (!_hash.hasMatch(codeHash)) return 'Scan your tag to set it up.';
    if ((label?.length ?? 0) > 40) return 'Keep the place name short.';
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'codeHash': codeHash,
    if (label?.isNotEmpty == true) 'label': label,
  };

  factory TagScanConfig.fromJson(Map<String, dynamic> j) => TagScanConfig(
    codeHash: j['codeHash'] as String? ?? '',
    label: j['label'] as String?,
  );
}

class FocusConfig extends VerifierConfig {
  const FocusConfig({
    required this.packages,
    this.targetDurationMs = 25 * 60000,
    this.graceSeconds = 10,
  });

  final List<String> packages;
  final int targetDurationMs;
  final int graceSeconds;

  @override
  VerifierType get type => VerifierType.focus;

  @override
  String? validate() {
    if (packages.isEmpty) return 'Choose at least one distracting app.';
    if (targetDurationMs < 5 * 60000 || targetDurationMs > 3 * 60 * 60000) {
      return 'Focus time must be between 5 and 180 minutes.';
    }
    if (graceSeconds != 10) return 'The Focus grace period must be 10 seconds.';
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'packages': packages,
    'targetDurationMs': targetDurationMs,
    'graceSeconds': graceSeconds,
  };

  factory FocusConfig.fromJson(Map<String, dynamic> j) => FocusConfig(
    packages: (j['packages'] as List? ?? const []).cast<String>(),
    targetDurationMs: (j['targetDurationMs'] as num?)?.toInt() ?? 25 * 60000,
    graceSeconds: (j['graceSeconds'] as num?)?.toInt() ?? 10,
  );
}

class HealthWorkoutConfig extends VerifierConfig {
  const HealthWorkoutConfig({
    this.activityType = 'any',
    this.targetDurationMs = 30 * 60000,
  });

  /// Stable app-level values mapped to Health Connect exercise constants.
  final String activityType; // any | strength | running | cycling | yoga
  final int targetDurationMs;

  static const supported = {'any', 'strength', 'running', 'cycling', 'yoga'};

  @override
  VerifierType get type => VerifierType.healthWorkout;

  @override
  String? validate() {
    if (!supported.contains(activityType)) return 'Choose a supported workout.';
    if (targetDurationMs < 10 * 60000 || targetDurationMs > 3 * 60 * 60000) {
      return 'Workout time must be between 10 and 180 minutes.';
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'activityType': activityType,
    'targetDurationMs': targetDurationMs,
  };

  factory HealthWorkoutConfig.fromJson(Map<String, dynamic> j) =>
      HealthWorkoutConfig(
        activityType: j['activityType'] as String? ?? 'any',
        targetDurationMs:
            (j['targetDurationMs'] as num?)?.toInt() ?? 30 * 60000,
      );
}

class LeetCodeConfig extends VerifierConfig {
  const LeetCodeConfig({
    required this.username,
    this.targetAccepted = 1,
    this.ownerVerifiedAtMs,
  });

  final String username;
  final int targetAccepted;

  /// When the person proved they own the profile by putting a one-time code
  /// in its About field. No password, token or cookie is ever used.
  final int? ownerVerifiedAtMs;

  @override
  VerifierType get type => VerifierType.leetcode;

  @override
  String? validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(username.trim())) {
      return 'Enter a valid public LeetCode username.';
    }
    if (targetAccepted < 1 || targetAccepted > 10) {
      return 'Choose between 1 and 10 accepted problems.';
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'username': username.trim(),
    'targetAccepted': targetAccepted,
    if (ownerVerifiedAtMs != null) 'ownerVerifiedAtMs': ownerVerifiedAtMs,
  };

  factory LeetCodeConfig.fromJson(Map<String, dynamic> j) => LeetCodeConfig(
    username: j['username'] as String? ?? '',
    targetAccepted: (j['targetAccepted'] as num?)?.toInt() ?? 1,
    ownerVerifiedAtMs: (j['ownerVerifiedAtMs'] as num?)?.toInt(),
  );
}

class WalkConfig extends VerifierConfig {
  const WalkConfig({
    required this.mode,
    this.targetDurationMs = 15 * 60000,
    this.targetDistanceM = 1000,
    this.lat,
    this.lng,
    this.label,
    this.placeId,
    this.address,
  });

  final WalkGoalMode mode;
  final int targetDurationMs;
  final int targetDistanceM;
  final double? lat;
  final double? lng;
  final String? label;
  final String? placeId;
  final String? address;

  @override
  VerifierType get type => VerifierType.walk;

  @override
  String? validate() {
    if (mode == WalkGoalMode.duration &&
        (targetDurationMs < 5 * 60000 || targetDurationMs > 2 * 60 * 60000)) {
      return 'Walk time must be between 5 and 120 minutes.';
    }
    if (mode == WalkGoalMode.distance &&
        (targetDistanceM < 250 || targetDistanceM > 20000)) {
      return 'Walk distance must be between 0.25 and 20 km.';
    }
    if (mode == WalkGoalMode.destination) {
      if (lat == null || !lat!.isFinite || lat! < -90 || lat! > 90) {
        return 'Choose a destination from place search.';
      }
      if (lng == null || !lng!.isFinite || lng! < -180 || lng! > 180) {
        return 'Choose a destination from place search.';
      }
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'mode': mode.wire,
    'targetDurationMs': targetDurationMs,
    'targetDistanceM': targetDistanceM,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (label != null) 'label': label,
    if (placeId != null) 'placeId': placeId,
    if (address != null) 'address': address,
  };

  factory WalkConfig.fromJson(Map<String, dynamic> json) => WalkConfig(
    mode: WalkGoalMode.from(json['mode'] as String?),
    targetDurationMs: (json['targetDurationMs'] as num?)?.toInt() ?? 15 * 60000,
    targetDistanceM: (json['targetDistanceM'] as num?)?.toInt() ?? 1000,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    label: json['label'] as String?,
    placeId: json['placeId'] as String?,
    address: json['address'] as String?,
  );
}

class StepsConfig extends VerifierConfig {
  const StepsConfig({required this.targetSteps, this.minDurationMs = 60000});
  final int targetSteps;
  final int minDurationMs;

  @override
  VerifierType get type => VerifierType.steps;

  @override
  String? validate() {
    if (targetSteps < 200 || targetSteps > 20000) {
      return 'Target must be between 200 and 20000 steps.';
    }
    if (minDurationMs < 60000) return 'Minimum duration must be 60s or more.';
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'targetSteps': targetSteps,
    'minDurationMs': minDurationMs,
  };

  factory StepsConfig.fromJson(Map<String, dynamic> j) => StepsConfig(
    targetSteps: (j['targetSteps'] as num).toInt(),
    minDurationMs: (j['minDurationMs'] as num?)?.toInt() ?? 60000,
  );
}

class LocationConfig extends VerifierConfig {
  const LocationConfig({
    required this.lat,
    required this.lng,
    this.radiusM = 150,
    this.dwellMs = 300000,
    this.label,
    this.placeId,
    this.address,
  });

  final double lat;
  final double lng;
  final int radiusM;
  final int dwellMs;
  final String? label;
  final String? placeId;
  final String? address;

  @override
  VerifierType get type => VerifierType.location;

  @override
  String? validate() {
    if (!lat.isFinite || lat < -90 || lat > 90) return 'Invalid latitude.';
    if (!lng.isFinite || lng < -180 || lng > 180) return 'Invalid longitude.';
    if (radiusM < 100 || radiusM > 500) {
      return 'Radius must be between 100m and 500m. Phone GPS is not '
          'accurate enough to promise anything tighter.';
    }
    if (dwellMs < 60000) return 'Dwell must be at least 60s.';
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'radiusM': radiusM,
    'dwellMs': dwellMs,
    if (label != null) 'label': label,
    if (placeId != null) 'placeId': placeId,
    if (address != null) 'address': address,
  };

  factory LocationConfig.fromJson(Map<String, dynamic> j) => LocationConfig(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    radiusM: (j['radiusM'] as num?)?.toInt() ?? 150,
    dwellMs: (j['dwellMs'] as num?)?.toInt() ?? 300000,
    label: j['label'] as String?,
    placeId: j['placeId'] as String?,
    address: j['address'] as String?,
  );
}
