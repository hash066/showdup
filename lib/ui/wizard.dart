import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/commitment.dart';
import '../models/verifier_config.dart';
import '../models/enums.dart';
import '../platform/alarm_channel.dart';
import '../platform/overlay_channel.dart';
import '../platform/places_channel.dart';
import '../platform/health_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../platform/blocker_channel.dart';
import '../services/controller.dart';
import '../verification/verifier_registry.dart';
import 'app.dart';
import 'widgets.dart';
import 'screens.dart';
import 'coach_marks.dart';

class CommitmentWizard extends ConsumerStatefulWidget {
  const CommitmentWizard({super.key, this.existing});
  final Commitment? existing;
  @override
  ConsumerState<CommitmentWizard> createState() => _CommitmentWizardState();
}

class _CommitmentWizardState extends ConsumerState<CommitmentWizard>
    with WidgetsBindingObserver {
  final title = TextEditingController(),
      lat = TextEditingController(),
      lng = TextEditingController(),
      label = TextEditingController(),
      zone = TextEditingController(),
      username = TextEditingController(),
      appSearch = TextEditingController();
  String? placeId, placeAddress;
  int page = 0,
      walkMinutes = 15,
      walkDistanceM = 1000,
      focusMinutes = 25,
      workoutMinutes = 30,
      targetAccepted = 1,
      interval = 20,
      maxReminders = 6;
  WalkGoalMode walkMode = WalkGoalMode.duration;
  bool loud = false,
      busy = false,
      restrictionsEnabled = false,
      customDayTimes = false;
  String? error;
  List<BlockableApp> blockableApps = const [];
  final Set<String> selectedPackages = {};
  bool loadingApps = false;
  VerifierType type = VerifierType.walk;
  CommitmentKind kind = CommitmentKind.walk;
  String workoutType = 'any';
  AlarmPermissionStatus? alarmPermissions;
  HealthAvailability? healthAvailability;
  final _presetTutorialKey = GlobalKey();
  final _guardrailTutorialKey = GlobalKey();
  Set<int> days = {1, 2, 3, 4, 5};
  final Map<int, TimeOfDay> dayStarts = {};
  final Map<int, TimeOfDay> dayEnds = {};
  TimeOfDay start = const TimeOfDay(hour: 6, minute: 30),
      end = const TimeOfDay(hour: 9, minute: 0);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final c = widget.existing;
    if (c != null) {
      type = c.verifierType == VerifierType.steps
          ? VerifierType.walk
          : c.verifierType;
      kind = c.kind;
      days = c.schedule.daysOfWeek.toSet();
      start = _time(c.schedule.windowStartLocal);
      end = _time(c.schedule.windowEndLocal);
      customDayTimes = c.schedule.hasCustomWindows;
      for (final entry in c.schedule.dayWindows.entries) {
        dayStarts[entry.key] = _time(entry.value.startLocal);
        dayEnds[entry.key] = _time(entry.value.endLocal);
      }
      zone.text = c.schedule.timezone;
      interval = c.reminder.intervalMinutes;
      maxReminders = c.reminder.maxReminders.clamp(1, 6);
      loud = c.reminder.volumeMode == VolumeMode.loud;
      restrictionsEnabled = c.restrictions.enabled;
      selectedPackages.addAll(c.restrictions.packages);
      final cfg = c.verifierConfig;
      if (cfg is WalkConfig) {
        walkMode = cfg.mode;
        walkMinutes = cfg.targetDurationMs ~/ 60000;
        walkDistanceM = cfg.targetDistanceM;
        if (cfg.lat != null) lat.text = cfg.lat.toString();
        if (cfg.lng != null) lng.text = cfg.lng.toString();
        label.text = cfg.label ?? '';
        placeId = cfg.placeId;
        placeAddress = cfg.address;
      }
      if (cfg is LocationConfig) {
        lat.text = cfg.lat.toString();
        lng.text = cfg.lng.toString();
        label.text = cfg.label ?? '';
        placeId = cfg.placeId;
        placeAddress = cfg.address;
      }
      if (cfg is FocusConfig) {
        focusMinutes = cfg.targetDurationMs ~/ 60000;
        selectedPackages.addAll(cfg.packages);
      }
      if (cfg is HealthWorkoutConfig) {
        workoutMinutes = cfg.targetDurationMs ~/ 60000;
        workoutType = cfg.activityType;
      }
      if (cfg is LeetCodeConfig) {
        username.text = cfg.username;
        targetAccepted = cfg.targetAccepted;
      }
      title.text = _presetTitle;
    } else {
      title.text = 'Morning walk';
      zone.text = ref.read(appProvider).user?.timezone ?? 'Asia/Kolkata';
      _restoreGuardrailProfile();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshReadiness());
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPresetTutorial());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [title, lat, lng, label, zone, username, appSearch]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshReadiness();
  }

  TimeOfDay _time(String s) => TimeOfDay(
    hour: int.parse(s.split(':')[0]),
    minute: int.parse(s.split(':')[1]),
  );
  String _clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String get _presetTitle => switch (kind) {
    CommitmentKind.gym => 'Gym session',
    CommitmentKind.arrive =>
      'Arrive at ${label.text.isEmpty ? 'my place' : label.text}',
    CommitmentKind.focus => 'Focus for $focusMinutes minutes',
    CommitmentKind.workout => 'Workout for $workoutMinutes minutes',
    CommitmentKind.leetcode =>
      'Solve $targetAccepted LeetCode problem${targetAccepted == 1 ? '' : 's'}',
    CommitmentKind.walk when walkMode == WalkGoalMode.duration =>
      'Walk for $walkMinutes minutes',
    CommitmentKind.walk when walkMode == WalkGoalMode.distance =>
      'Walk ${(walkDistanceM / 1000).toStringAsFixed(walkDistanceM % 1000 == 0 ? 0 : 2)} km',
    CommitmentKind.walk =>
      'Walk to ${label.text.isEmpty ? 'my destination' : label.text}',
  };
  String get _goalSummary => switch (config) {
    WalkConfig(mode: WalkGoalMode.duration) => '$walkMinutes active minutes',
    WalkConfig(mode: WalkGoalMode.distance) =>
      '${(walkDistanceM / 1000).toStringAsFixed(2)} km by GPS',
    WalkConfig(mode: WalkGoalMode.destination) =>
      'Arrive within 150 m of ${label.text.isEmpty ? 'your destination' : label.text}',
    StepsConfig(:final targetSteps) => '$targetSteps new steps',
    LocationConfig() =>
      'Stay near ${label.text.isEmpty ? 'your place' : label.text} for ${kind == CommitmentKind.gym ? 5 : 2} minutes',
    FocusConfig() =>
      '$focusMinutes uninterrupted minutes away from ${selectedPackages.length} selected app${selectedPackages.length == 1 ? '' : 's'}',
    HealthWorkoutConfig() =>
      '$workoutMinutes sensor-recorded Health Connect minutes',
    LeetCodeConfig() =>
      '$targetAccepted unique accepted problem${targetAccepted == 1 ? '' : 's'} on @${username.text.trim()}',
  };
  VerifierConfig get config => switch (type) {
    VerifierType.walk => WalkConfig(
      mode: walkMode,
      targetDurationMs: walkMinutes * 60000,
      targetDistanceM: walkDistanceM,
      lat: double.tryParse(lat.text),
      lng: double.tryParse(lng.text),
      label: label.text.trim().isEmpty ? null : label.text.trim(),
      placeId: placeId,
      address: placeAddress,
    ),
    VerifierType.location => LocationConfig(
      lat: double.tryParse(lat.text) ?? double.nan,
      lng: double.tryParse(lng.text) ?? double.nan,
      radiusM: 150,
      dwellMs: (kind == CommitmentKind.gym ? 5 : 2) * 60000,
      label: label.text.trim(),
      placeId: placeId,
      address: placeAddress,
    ),
    VerifierType.steps => const StepsConfig(targetSteps: 1000),
    VerifierType.focus => FocusConfig(
      packages: selectedPackages.toList()..sort(),
      targetDurationMs: focusMinutes * 60000,
    ),
    VerifierType.healthWorkout => HealthWorkoutConfig(
      activityType: workoutType,
      targetDurationMs: workoutMinutes * 60000,
    ),
    VerifierType.leetcode => LeetCodeConfig(
      username: username.text.trim(),
      targetAccepted: targetAccepted,
    ),
  };
  CommitmentSchedule get schedule {
    final isPro = ref.read(appProvider).user?.isPro == true;
    final selected = days.toList()..sort();
    final existingWindows = widget.existing?.schedule.dayWindows ?? const {};
    return CommitmentSchedule(
      daysOfWeek: selected,
      windowStartLocal: _clock(start),
      windowEndLocal: _clock(end),
      timezone: zone.text.trim(),
      dayWindows: isPro && customDayTimes
          ? {
              for (final day in selected)
                day: DailyWindow(
                  startLocal: _clock(dayStarts[day] ?? start),
                  endLocal: _clock(dayEnds[day] ?? end),
                ),
            }
          : !isPro
          ? existingWindows
          : const {},
    );
  }

  Future<void> next() async {
    setState(() => error = null);
    if (page == 0) {
      final configError = type == VerifierType.focus && selectedPackages.isEmpty
          ? null
          : config.validate();
      final validation =
          configError ??
          schedule.validate() ??
          ReminderConfig(
            intervalMinutes: interval,
            volumeMode: loud ? VolumeMode.loud : VolumeMode.gentle,
            maxReminders: maxReminders,
          ).validate();
      if (validation != null) {
        setState(() => error = validation);
        return;
      }
      setState(() => page = 1);
      if (type == VerifierType.focus ||
          ref.read(appProvider).user?.isPro == true) {
        await _loadBlockableApps();
      }
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showGuardrailTutorial(),
      );
      return;
    }
    if (type == VerifierType.focus && selectedPackages.isEmpty) {
      setState(
        () => error = 'Choose at least one distracting app for Focus proof.',
      );
      return;
    }
    if (restrictionsEnabled && selectedPackages.isEmpty) {
      setState(() => error = 'Choose at least one distracting app.');
      return;
    }
    await save();
  }

  Future<void> save() async {
    setState(() => busy = true);
    final app = ref.read(appProvider);
    final firstCommitment = widget.existing == null && app.commitments.isEmpty;
    try {
      var shouldActivate = true;
      if (!app.preview) {
        final permissions = await AlarmChannel.getPermissionStatus();
        alarmPermissions = permissions;
        shouldActivate = permissions.notifications && permissions.exactAlarm;
        final verifier = VerifierRegistry().create(type);
        final availability = await verifier.checkAvailability(config);
        shouldActivate = shouldActivate && availability.available;
      }
      final data = {
        'title': _presetTitle,
        'kind': kind.wire,
        'verifierType': type.wire,
        'verifierConfig': config.toJson(),
        'schedule': schedule.toJson(),
        'reminder': ReminderConfig(
          intervalMinutes: interval,
          volumeMode: loud ? VolumeMode.loud : VolumeMode.gentle,
          maxReminders: maxReminders,
        ).toJson(),
        'status': shouldActivate
            ? CommitmentStatus.active.wire
            : CommitmentStatus.draft.wire,
        'restrictions': Restrictions(
          enabled: app.user?.isPro == true && restrictionsEnabled,
          packages: app.user?.isPro == true
              ? (selectedPackages.toList()..sort())
              : const [],
        ).toJson(),
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'guardrails.lastPackages.v1',
        selectedPackages.toList()..sort(),
      );
      if (widget.existing == null) {
        await app.repository.create(data);
      } else {
        await app.repository.update(widget.existing!.id, data);
      }
      await app.refresh();
      if (firstCommitment && shouldActivate && mounted) await _offerOverlay();
      if (!shouldActivate && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Saved as a draft. Finish the required Android access to activate reminders.',
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restoreGuardrailProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || selectedPackages.isNotEmpty) return;
    setState(() {
      selectedPackages.addAll(
        prefs.getStringList('guardrails.lastPackages.v1') ?? const [],
      );
    });
  }

  Future<void> _refreshReadiness() async {
    if (ref.read(appProvider).preview) return;
    try {
      final value = await AlarmChannel.getPermissionStatus();
      HealthAvailability? health;
      if (type == VerifierType.healthWorkout) {
        health = await HealthChannel.availability();
      }
      if (mounted) {
        setState(() {
          alarmPermissions = value;
          if (health != null) healthAvailability = health;
        });
      }
    } on MissingPluginException {
      // Widget tests and non-Android previews do not expose Android settings.
    }
  }

  Future<void> _showPresetTutorial() async {
    if (ref.read(appProvider).preview) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || prefs.getBool('tutorial.wizard.v1') == true) return;
    await showCoachMarks(context, [
      CoachMarkStep(
        target: _presetTutorialKey,
        title: 'Start with proof',
        body:
            'Every preset defines exactly what the phone can verify. Then choose days, the commitment window and alarm readiness on this same screen.',
      ),
    ]);
  }

  Future<void> _showGuardrailTutorial() async {
    if (ref.read(appProvider).preview) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || prefs.getBool('tutorial.wizard.v1') == true) return;
    await showCoachMarks(context, [
      CoachMarkStep(
        target: _guardrailTutorialKey,
        title: 'You control the guardrails',
        body:
            'Select or uncheck every distracting app yourself. Focus proof is free; actively covering those apps is a Pro option.',
      ),
    ]);
    await prefs.setBool('tutorial.wizard.v1', true);
  }

  Future<void> _offerOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('overlay.permissionExplained') == true || !mounted) {
      return;
    }
    await prefs.setBool('overlay.permissionExplained', true);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep your pet in sight?'),
        content: const Text(
          'ShowdUp can display a small draggable accountability pet over other apps. It is optional, clearly labeled, and can be turned off anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set up overlay'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await prefs.setBool('overlay.pendingEnable', true);
      await OverlayChannel.requestPermission();
    }
  }

  Future<void> _loadBlockableApps() async {
    if (blockableApps.isNotEmpty || loadingApps) return;
    setState(() => loadingApps = true);
    try {
      final apps = await BlockerChannel.listApps();
      if (mounted) setState(() => blockableApps = apps);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => loadingApps = false);
    }
  }

  Future<void> currentLocation() async {
    setState(() => busy = true);
    try {
      await AlarmChannel.requestPermission('location');
      final p = await const MethodChannel(
        'app.showdup/location',
      ).invokeMapMethod<String, dynamic>('currentLocation');
      if (p != null) {
        lat.text = (p['lat'] as num).toStringAsFixed(6);
        lng.text = (p['lng'] as num).toStringAsFixed(6);
        label.text = kind == CommitmentKind.gym ? 'My gym' : 'My destination';
        placeId = null;
        placeAddress = 'Pinned from your current location';
      }
    } catch (e) {
      setState(() => error = friendlyError(e));
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> pickGym() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final place = await PlacesChannel.pickPlace(
        initialQuery: kind == CommitmentKind.gym ? 'gym' : '',
      );
      if (place == null || !mounted) return;
      setState(() {
        placeId = place.id;
        placeAddress = place.address;
        label.text = place.name;
        lat.text = place.lat.toStringAsFixed(6);
        lng.text = place.lng.toStringAsFixed(6);
        title.text = _presetTitle;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null ? 'A promise with a plan' : 'Edit commitment',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: List.generate(
                  2,
                  (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: i <= page ? T.accent : T.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Eyebrow('Step ${page + 1} of 2'),
                  const SizedBox(height: 12),
                  Text(
                    [
                      'Set the finish line.',
                      'Guardrails and confirmation.',
                    ][page],
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ...switch (page) {
                    0 => _setup(),
                    _ => [
                      KeyedSubtree(
                        key: _guardrailTutorialKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ..._restrictions(),
                            const SizedBox(height: 28),
                            ..._review(),
                          ],
                        ),
                      ),
                    ],
                  },
                  if (error != null) ...[
                    const SizedBox(height: 18),
                    ErrorNotice(error!),
                    if (!ref.read(appProvider).preview)
                      TextButton(
                        onPressed: page == 1
                            ? BlockerChannel.openAccessibilitySettings
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => const PermissionsScreen(),
                                ),
                              ),
                        child: Text(
                          page == 1
                              ? 'Open accessibility settings'
                              : 'Open permissions & reliability',
                        ),
                      ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Row(
                  children: [
                    if (page > 0) ...[
                      IconButton(
                        onPressed: busy ? null : () => setState(() => page--),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : next,
                        child: Text(
                          busy
                              ? 'Saving…'
                              : page == 1
                              ? widget.existing == null
                                    ? 'I’m showing up  →'
                                    : 'Save changes'
                              : 'Continue  →',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  List<Widget> _setup() => [
    ..._goal(),
    const SizedBox(height: 30),
    const Divider(),
    const SizedBox(height: 24),
    ..._schedule(),
    const SizedBox(height: 30),
    const Divider(),
    const SizedBox(height: 24),
    ..._reminders(),
    const SizedBox(height: 24),
    _readinessCard(),
  ];

  List<Widget> _goal() => [
    const Text(
      'Every option below is completed by evidence from your phone. There is no manual “done” button.',
      style: TextStyle(color: T.muted, height: 1.55),
    ),
    const SizedBox(height: 20),
    const Eyebrow('Choose a verified preset'),
    const SizedBox(height: 14),
    Wrap(
      key: _presetTutorialKey,
      spacing: 10,
      runSpacing: 10,
      children: [
        _typeCard(CommitmentKind.walk, Icons.directions_run, 'Walk / run'),
        _typeCard(CommitmentKind.gym, Icons.fitness_center, 'Gym'),
        _typeCard(CommitmentKind.arrive, Icons.place_outlined, 'Arrive'),
        _typeCard(CommitmentKind.focus, Icons.center_focus_strong, 'Focus'),
        _typeCard(
          CommitmentKind.workout,
          Icons.health_and_safety_outlined,
          'Workout',
        ),
        _typeCard(CommitmentKind.leetcode, Icons.code_rounded, 'LeetCode'),
      ],
    ),
    const SizedBox(height: 24),
    if (kind == CommitmentKind.walk) ...[
      Wrap(
        spacing: 8,
        children: WalkGoalMode.values
            .where(
              (mode) => mode != WalkGoalMode.destination || walkMode == mode,
            )
            .map(
              (mode) => ChoiceChip(
                label: Text(switch (mode) {
                  WalkGoalMode.duration => 'Time',
                  WalkGoalMode.distance => 'Kilometres',
                  WalkGoalMode.destination => 'Destination',
                }),
                selected: walkMode == mode,
                onSelected: (_) => setState(() {
                  walkMode = mode;
                  title.text = _presetTitle;
                }),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 14),
      Panel(
        child: switch (walkMode) {
          WalkGoalMode.duration => Column(
            children: [
              const Eyebrow('Active walking time'),
              const SizedBox(height: 10),
              Text(
                '$walkMinutes min',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: T.accent,
                ),
              ),
              Slider(
                value: walkMinutes.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                onChanged: (value) => setState(() {
                  walkMinutes = (value / 5).round() * 5;
                  title.text = _presetTitle;
                }),
              ),
            ],
          ),
          WalkGoalMode.distance => Column(
            children: [
              const Eyebrow('GPS distance'),
              const SizedBox(height: 10),
              Text(
                '${(walkDistanceM / 1000).toStringAsFixed(2)} km',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: T.accent,
                ),
              ),
              Slider(
                value: walkDistanceM.toDouble(),
                min: 250,
                max: 10000,
                divisions: 39,
                onChanged: (value) => setState(() {
                  walkDistanceM = (value / 250).round() * 250;
                  title.text = _presetTitle;
                }),
              ),
            ],
          ),
          WalkGoalMode.destination => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.text.isEmpty ? 'Choose a destination' : label.text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (placeAddress?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text(
                  placeAddress!,
                  style: const TextStyle(color: T.muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: busy ? null : pickGym,
                icon: const Icon(Icons.search),
                label: Text(
                  label.text.isEmpty ? 'Search places' : 'Change destination',
                ),
              ),
            ],
          ),
        },
      ),
      const SizedBox(height: 16),
      Text(
        'Foreground GPS counts only plausible movement with a precise, non-mock fix. Keep the phone with you and open ShowdUp to start.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ] else if (kind == CommitmentKind.gym || kind == CommitmentKind.arrive) ...[
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_searching, color: T.accent, size: 28),
            const SizedBox(height: 14),
            Text(
              label.text.isEmpty
                  ? kind == CommitmentKind.gym
                        ? 'Choose your gym'
                        : 'Choose where you must arrive'
                  : label.text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (placeAddress?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                placeAddress!,
                style: const TextStyle(
                  color: T.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: busy ? null : pickGym,
              icon: const Icon(Icons.search),
              label: Text(
                label.text.isEmpty ? 'Search places' : 'Change place',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: busy ? null : currentLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Pin where I am now'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Text(
        'ShowdUp uses a fixed 150 m boundary and verifies after a continuous ${kind == CommitmentKind.gym ? 5 : 2}-minute stay. Coordinates and radius are never shown or editable.',
        style: const TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ] else if (kind == CommitmentKind.focus) ...[
      _durationPanel(
        label: 'Uninterrupted focus',
        minutes: focusMinutes,
        min: 5,
        max: 180,
        onChanged: (value) => setState(() => focusMinutes = value),
      ),
      const SizedBox(height: 12),
      const Text(
        'Choose distracting apps on the next step. Ten continuous seconds in one resets the timer; Pro blocks it immediately.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ] else if (kind == CommitmentKind.workout) ...[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: HealthWorkoutConfig.supported
            .map(
              (value) => ChoiceChip(
                label: Text(
                  value == 'any'
                      ? 'Any workout'
                      : value[0].toUpperCase() + value.substring(1),
                ),
                selected: workoutType == value,
                onSelected: (_) => setState(() => workoutType = value),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 14),
      _durationPanel(
        label: 'Sensor-recorded workout',
        minutes: workoutMinutes,
        min: 10,
        max: 180,
        onChanged: (value) => setState(() => workoutMinutes = value),
      ),
      const SizedBox(height: 12),
      const Text(
        'Only actively or automatically recorded Health Connect sessions count. Manual and unknown records are excluded.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ] else if (kind == CommitmentKind.leetcode) ...[
      TextField(
        controller: username,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Public LeetCode username',
          helperText: 'ShowdUp never asks for your password or session cookie.',
        ),
      ),
      const SizedBox(height: 16),
      Panel(
        child: Column(
          children: [
            Text(
              '$targetAccepted accepted problem${targetAccepted == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            Slider(
              value: targetAccepted.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (value) =>
                  setState(() => targetAccepted = value.round()),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Verification reads recent accepted submissions from your public profile. If LeetCode is unavailable, the attempt is marked unable to verify—not missed.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ],
  ];
  Widget _typeCard(
    CommitmentKind value,
    IconData icon,
    String label,
  ) => SizedBox(
    width: 150,
    child: InkWell(
      onTap: () => setState(() {
        kind = value;
        type = switch (value) {
          CommitmentKind.walk => VerifierType.walk,
          CommitmentKind.gym || CommitmentKind.arrive => VerifierType.location,
          CommitmentKind.focus => VerifierType.focus,
          CommitmentKind.workout => VerifierType.healthWorkout,
          CommitmentKind.leetcode => VerifierType.leetcode,
        };
        title.text = _presetTitle;
        _refreshReadiness();
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: kind == value ? T.accent.withValues(alpha: .10) : T.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: kind == value ? T.accent : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: kind == value ? T.accent : T.muted, size: 30),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _durationPanel({
    required String label,
    required int minutes,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) => Panel(
    child: Column(
      children: [
        Eyebrow(label),
        const SizedBox(height: 10),
        Text(
          '$minutes min',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: T.accent,
          ),
        ),
        Slider(
          value: minutes.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ 5,
          onChanged: (value) => onChanged((value / 5).round() * 5),
        ),
      ],
    ),
  );

  Widget _readinessCard() {
    final preview = ref.read(appProvider).preview;
    final permission = alarmPermissions;
    final rows = <Widget>[
      _readinessRow(
        'Notifications',
        preview || permission?.notifications == true,
        () async {
          await AlarmChannel.requestPermission('notifications');
          await _refreshReadiness();
        },
      ),
      _readinessRow(
        'Exact reminders',
        preview || permission?.exactAlarm == true,
        () async {
          await AlarmChannel.requestPermission('exactAlarm');
          await _refreshReadiness();
        },
      ),
    ];
    if (type == VerifierType.walk || type == VerifierType.location) {
      rows.add(
        _readinessRow(
          'Precise location',
          preview || permission?.location == true,
          () async {
            await AlarmChannel.requestPermission('location');
            await _refreshReadiness();
          },
        ),
      );
    }
    if (type == VerifierType.healthWorkout) {
      rows.add(
        _readinessRow(
          'Health Connect exercise + background access',
          preview || healthAvailability?.permissionsGranted == true,
          () async {
            await HealthChannel.requestPermissions();
            await _refreshReadiness();
          },
        ),
      );
    }
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Alarm readiness'),
          const SizedBox(height: 8),
          const Text(
            'Missing required access saves this setup as a draft. Nothing is scheduled until it is ready.',
            style: TextStyle(color: T.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _readinessRow(String label, bool ready, Future<void> Function() fix) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          ready ? Icons.check_circle : Icons.warning_amber_rounded,
          color: ready ? T.ok : T.accent,
        ),
        title: Text(label),
        trailing: ready
            ? const Text('Ready', style: TextStyle(color: T.ok, fontSize: 12))
            : TextButton(onPressed: fix, child: const Text('Enable')),
      );
  List<Widget> _schedule() {
    final isPro = ref.read(appProvider).user?.isPro == true;
    return [
      const Text(
        'Pick the days you can repeat. Your commitment uses this timezone, even when your phone travels.',
        style: TextStyle(color: T.muted, height: 1.6),
      ),
      const SizedBox(height: 22),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          7,
          (i) => FilterChip(
            label: Text(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i]),
            selected: days.contains(i + 1),
            onSelected: (v) => setState(() {
              final day = i + 1;
              if (v) {
                days.add(day);
                dayStarts.putIfAbsent(day, () => start);
                dayEnds.putIfAbsent(day, () => end);
              } else {
                days.remove(day);
              }
            }),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Panel(
        child: Column(
          children: [
            _timeRow('Window opens', start, (v) => setState(() => start = v)),
            const Divider(height: 32),
            _timeRow('Window ends', end, (v) => setState(() => end = v)),
          ],
        ),
      ),
      if (isPro) ...[
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.all(12),
          title: const Text('Different time for each day'),
          subtitle: const Text(
            'Pro · Give every selected weekday its own start and end time.',
            style: TextStyle(color: T.muted, fontSize: 12, height: 1.5),
          ),
          value: customDayTimes,
          onChanged: (value) => setState(() {
            customDayTimes = value;
            if (value) {
              for (final day in days) {
                dayStarts.putIfAbsent(day, () => start);
                dayEnds.putIfAbsent(day, () => end);
              }
            }
          }),
        ),
        if (customDayTimes) ...[
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                for (final day in (days.toList()..sort())) ...[
                  _dayWindowRow(day),
                  if (day != (days.toList()..sort()).last)
                    const Divider(height: 28),
                ],
              ],
            ),
          ),
        ],
      ] else ...[
        const SizedBox(height: 12),
        const Text(
          'Pro can use a different window on each selected day.',
          style: TextStyle(color: T.muted, fontSize: 12),
        ),
      ],
      const SizedBox(height: 24),
      TextField(
        controller: zone,
        decoration: const InputDecoration(
          labelText: 'Commitment timezone',
          hintText: 'Asia/Kolkata',
          helperText: 'IANA timezone, for example Europe/London',
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Reminders stop when the window ends. A window must be at least 15 minutes and finish on the same day.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ];
  }

  Widget _dayWindowRow(int day) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dayStart = dayStarts[day] ?? start;
    final dayEnd = dayEnds[day] ?? end;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          names[day - 1],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _compactTime('Opens', dayStart, (value) {
                setState(() => dayStarts[day] = value);
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _compactTime('Ends', dayEnd, (value) {
                setState(() => dayEnds[day] = value);
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactTime(
    String label,
    TimeOfDay time,
    void Function(TimeOfDay) change,
  ) => OutlinedButton(
    onPressed: () async {
      final value = await showTimePicker(context: context, initialTime: time);
      if (value != null) change(value);
    },
    child: Text('$label ${_clock(time)}'),
  );
  Widget _timeRow(
    String label,
    TimeOfDay time,
    void Function(TimeOfDay) change,
  ) => Row(
    children: [
      Expanded(child: Text(label)),
      TextButton(
        onPressed: () async {
          final v = await showTimePicker(context: context, initialTime: time);
          if (v != null) change(v);
        },
        child: Text(
          _clock(time),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
  List<Widget> _reminders() => [
    const Text(
      'Snooze silences the current reminder. Only verified evidence completes the commitment.',
      style: TextStyle(color: T.muted, height: 1.6),
    ),
    const SizedBox(height: 24),
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start with a $interval minute snooze gap',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            value: interval.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            onChanged: (v) => setState(() => interval = v.round()),
          ),
          const SizedBox(height: 12),
          Text(
            'Up to $maxReminders reminders',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            value: maxReminders.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            onChanged: (v) => setState(() => maxReminders = v.round()),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    SwitchListTile(
      contentPadding: const EdgeInsets.all(12),
      title: const Text('Loud reminders'),
      subtitle: const Text(
        'Overrides your alarm volume to maximum while ringing. Choose this only if it suits your day.',
        style: TextStyle(color: T.muted, fontSize: 12, height: 1.5),
      ),
      value: loud,
      onChanged: (v) => setState(() => loud = v),
    ),
    if (loud)
      const ErrorNotice(
        'You chose maximum alarm volume. Each reminder rings for up to 30 seconds; snooze silences it immediately.',
      ),
    const SizedBox(height: 18),
    const Text(
      'Gentle respects your existing alarm volume. You can always end today without completing.',
      style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
    ),
  ];
  List<Widget> _restrictions() {
    final isPro = ref.read(appProvider).user?.isPro == true;
    final focusProof = type == VerifierType.focus;
    if (!isPro && !focusProof) {
      return [
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, color: T.accent, size: 32),
              SizedBox(height: 16),
              Text(
                'Unlock after completion',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 10),
              Text(
                'With Pro, only the distracting apps you choose are covered during this commitment window. Completing or ending today removes the restriction.',
                style: TextStyle(color: T.muted, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ProScreen()),
          ),
          child: const Text('Explore ShowdUp Pro'),
        ),
        const SizedBox(height: 12),
        const Text(
          'App blocking is optional. Reminders and verification remain available for free.',
          style: TextStyle(color: T.muted, fontSize: 12, height: 1.5),
        ),
      ];
    }
    return [
      if (focusProof) ...[
        const Text(
          'Choose the apps that reset your uninterrupted Focus timer. Window contents, passwords and typed text are never read.',
          style: TextStyle(color: T.muted, height: 1.6),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: BlockerChannel.openAccessibilitySettings,
          icon: const Icon(Icons.accessibility_new),
          label: const Text('Check accessibility access'),
        ),
      ],
      if (isPro)
        SwitchListTile(
          contentPadding: const EdgeInsets.all(12),
          title: const Text('Block selected distractions'),
          subtitle: Text(
            focusProof
                ? 'Pro covers a selected app immediately, before it can reset your Focus timer.'
                : 'ShowdUp covers only the apps you choose during this commitment window.',
            style: const TextStyle(color: T.muted, fontSize: 12, height: 1.5),
          ),
          value: restrictionsEnabled,
          onChanged: (value) async {
            setState(() => restrictionsEnabled = value);
            if (value) await _loadBlockableApps();
          },
        ),
      if (focusProof || restrictionsEnabled) ...[
        const SizedBox(height: 12),
        ErrorNotice(
          focusProof && !isPro
              ? 'Accessibility access reports only which foreground app opened. It resets the timer after ten seconds and never reads the app’s contents.'
              : 'Accessibility access lets ShowdUp notice when a selected app opens and place a blocking screen over it. You can disable access at any time.',
        ),
        const SizedBox(height: 16),
        if (loadingApps)
          const Center(child: CircularProgressIndicator())
        else if (blockableApps.isEmpty)
          OutlinedButton.icon(
            onPressed: _loadBlockableApps,
            icon: const Icon(Icons.refresh),
            label: const Text('Load installed apps'),
          )
        else
          TextField(
            controller: appSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search installed apps',
            ),
          ),
        if (blockableApps.isNotEmpty) const SizedBox(height: 10),
        if (blockableApps.isNotEmpty)
          ...blockableApps
              .where((app) {
                final query = appSearch.text.trim().toLowerCase();
                return query.isEmpty ||
                    app.label.toLowerCase().contains(query) ||
                    app.packageName.toLowerCase().contains(query);
              })
              .map(
                (app) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selectedPackages.contains(app.packageName),
                  title: Text(app.label),
                  subtitle: Text(
                    app.packageName,
                    style: const TextStyle(color: T.muted, fontSize: 10),
                  ),
                  onChanged: (selected) => setState(() {
                    if (selected == true) {
                      selectedPackages.add(app.packageName);
                    } else {
                      selectedPackages.remove(app.packageName);
                    }
                  }),
                ),
              ),
      ],
    ];
  }

  List<Widget> _review() => [
    Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (kind) {
              CommitmentKind.gym => Icons.fitness_center,
              CommitmentKind.arrive => Icons.place_outlined,
              CommitmentKind.focus => Icons.center_focus_strong,
              CommitmentKind.workout => Icons.health_and_safety_outlined,
              CommitmentKind.leetcode => Icons.code_rounded,
              _ => Icons.directions_run,
            },
            color: T.accent,
            size: 34,
          ),
          const SizedBox(height: 20),
          Text(
            _presetTitle,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(_goalSummary, style: const TextStyle(color: T.muted)),
          const Divider(height: 36),
          Text('${_clock(start)} – ${_clock(end)}'),
          const SizedBox(height: 8),
          Text(
            customDayTimes && ref.read(appProvider).user?.isPro == true
                ? '${days.length} custom day windows · ${zone.text}'
                : '${days.length} days a week · ${zone.text}',
            style: const TextStyle(color: T.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            'Every $interval minutes · up to $maxReminders reminders',
            style: const TextStyle(fontSize: 12),
          ),
          if (restrictionsEnabled) ...[
            const SizedBox(height: 8),
            Text(
              '${selectedPackages.length} selected app${selectedPackages.length == 1 ? '' : 's'} blocked until completion or today is ended',
              style: const TextStyle(color: T.accent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            loud
                ? 'Loud · maximum alarm volume'
                : 'Gentle · your chosen alarm volume',
            style: TextStyle(color: loud ? T.accent : T.muted, fontSize: 12),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    const Text(
      'You’re in charge.',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 10),
    const Text(
      'End today without completing, whenever you need to. Sensor issues show “Unable to verify” and preserve your streak. No guilt. Just a plan.',
      style: TextStyle(color: T.muted, height: 1.7, fontSize: 13),
    ),
    if (type == VerifierType.location) ...[
      const SizedBox(height: 16),
      const Text(
        'Location verification starts when you open ShowdUp or when the first reminder fires, with an Android foreground notification.',
        style: TextStyle(color: T.accent, height: 1.6, fontSize: 13),
      ),
    ],
  ];
}
