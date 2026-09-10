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
      };
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
    if (minDurationMs > 86400000) {
      return 'Minimum duration must be 24 hours or less.';
    }
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
  });

  final double lat;
  final double lng;
  final int radiusM;
  final int dwellMs;
  final String? label;

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
    if (dwellMs > 86400000) return 'Dwell must be 24 hours or less.';
    if ((label?.length ?? 0) > 100) {
      return 'Keep the place name to 100 characters or fewer.';
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'radiusM': radiusM,
    'dwellMs': dwellMs,
    if (label != null) 'label': label,
  };

  factory LocationConfig.fromJson(Map<String, dynamic> j) => LocationConfig(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    radiusM: (j['radiusM'] as num?)?.toInt() ?? 150,
    dwellMs: (j['dwellMs'] as num?)?.toInt() ?? 300000,
    label: j['label'] as String?,
  );
}
