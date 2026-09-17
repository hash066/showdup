import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/features.dart';
import '../design/buttons.dart';
import '../design/chrome.dart';
import '../design/icons.dart';
import '../design/layout.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../models/commitment.dart';
import '../models/enums.dart';
import '../models/verifier_config.dart';
import '../platform/alarm_channel.dart';
import '../platform/blocker_channel.dart';
import '../platform/health_channel.dart';
import '../platform/overlay_channel.dart';
import '../platform/places_channel.dart';
import '../services/controller.dart';
import '../verification/verifier_registry.dart';
import 'app_provider.dart';
import 'keys.dart';
import 'screens/common.dart';
import 'screens/permissions.dart';

/// Preset → When → Apps → Confirm. Missing Android access saves a draft.
class CommitmentWizard extends ConsumerStatefulWidget {
  const CommitmentWizard({super.key, this.existing});
  final Commitment? existing;

  @override
  ConsumerState<CommitmentWizard> createState() => _CommitmentWizardState();
}

class _CommitmentWizardState extends ConsumerState<CommitmentWizard>
    with WidgetsBindingObserver {
  static const _stepCount = 4;

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
  BlockerStatus? blockerStatus;
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

  bool get _isPro => ref.read(appProvider).user?.isPro == true;
  bool get _preview => ref.read(appProvider).preview;
  bool get _focus => type == VerifierType.focus;

  /// Holding apps is Pro, or free for one app once the catch ships.
  bool get _canCatch => _isPro || Features.catchEnabled;

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
    WalkConfig(mode: WalkGoalMode.duration) =>
      '$walkMinutes minutes on the move',
    WalkConfig(mode: WalkGoalMode.distance) =>
      '${(walkDistanceM / 1000).toStringAsFixed(2)} km by GPS',
    WalkConfig(mode: WalkGoalMode.destination) =>
      'Get within 150 m of ${label.text.isEmpty ? 'your destination' : label.text}',
    StepsConfig(:final targetSteps) => '$targetSteps new steps',
    LocationConfig() =>
      'Stay at ${label.text.isEmpty ? 'your place' : label.text} for ${kind == CommitmentKind.gym ? 5 : 2} minutes',
    FocusConfig() =>
      '$focusMinutes minutes away from ${selectedPackages.length} app${selectedPackages.length == 1 ? '' : 's'}',
    HealthWorkoutConfig() => '$workoutMinutes recorded workout minutes',
    LeetCodeConfig() =>
      '$targetAccepted accepted problem${targetAccepted == 1 ? '' : 's'} on @${username.text.trim()}',
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

  ReminderConfig get reminder => ReminderConfig(
    intervalMinutes: interval,
    volumeMode: loud ? VolumeMode.loud : VolumeMode.gentle,
    maxReminders: maxReminders,
  );

  CommitmentSchedule get schedule {
    final isPro = _isPro;
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
    final String? problem = switch (page) {
      0 => _focus && selectedPackages.isEmpty ? null : config.validate(),
      1 => schedule.validate() ?? reminder.validate(),
      2 when _focus && selectedPackages.isEmpty =>
        'Pick at least one app that pulls you away.',
      2 when restrictionsEnabled && selectedPackages.isEmpty =>
        'Pick the app to hold.',
      2 when restrictionsEnabled && !_isPro && selectedPackages.length > 1 =>
        'Free holds one app. Pick one, or turn holding off.',
      _ => null,
    };
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    if (page == _stepCount - 1) {
      await save();
      return;
    }
    setState(() => page++);
    if (page == 2 && (_focus || (_canCatch && restrictionsEnabled))) {
      await _loadBlockableApps();
    }
    if (page == 3) await _refreshReadiness();
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
      final holding = _canCatch && restrictionsEnabled;
      final data = {
        'title': _presetTitle,
        'kind': kind.wire,
        'verifierType': type.wire,
        'verifierConfig': config.toJson(),
        'schedule': schedule.toJson(),
        'reminder': reminder.toJson(),
        'status': shouldActivate
            ? CommitmentStatus.active.wire
            : CommitmentStatus.draft.wire,
        'restrictions': Restrictions(
          enabled: holding,
          packages: holding ? (selectedPackages.toList()..sort()) : const [],
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
              'Saved as a draft. It rings once the Android access is allowed.',
            ),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      if (friendlyError(e).startsWith('Free')) {
        await showLimitOrMessage(context, e);
      } else {
        setState(() => error = friendlyError(e));
      }
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
    if (_preview) return;
    try {
      final value = await AlarmChannel.getPermissionStatus();
      HealthAvailability? health;
      if (type == VerifierType.healthWorkout) {
        health = await HealthChannel.availability();
      }
      BlockerStatus? blocker;
      if (_focus || restrictionsEnabled) {
        blocker = await BlockerChannel.status();
      }
      if (mounted) {
        setState(() {
          alarmPermissions = value;
          if (health != null) healthAvailability = health;
          if (blocker != null) blockerStatus = blocker;
        });
      }
    } on MissingPluginException {
      // Widget tests and non-Android previews do not expose Android settings.
    } on PlatformException {
      // An older native build may lack a status method; rows stay "Allow".
    }
  }

  Future<void> _offerOverlay() async {
    if (!Features.overlay) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('overlay.permissionExplained') == true || !mounted) {
      return;
    }
    await prefs.setBool('overlay.permissionExplained', true);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep your next alarm in sight?'),
        content: const Text(
          'Your companion can float over other apps with your next alarm. It’s optional, labelled, and you can turn it off any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set it up'),
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
    if (blockableApps.isNotEmpty || loadingApps || _preview) return;
    setState(() => loadingApps = true);
    try {
      final apps = await BlockerChannel.listApps();
      if (mounted) setState(() => blockableApps = apps);
    } on MissingPluginException {
      // Widget tests have no installed-app list.
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
        label.text = kind == CommitmentKind.gym ? 'My gym' : 'My place';
        placeId = null;
        placeAddress = 'Pinned where you stood';
      }
    } catch (e) {
      setState(() => error = friendlyError(e));
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> pickPlace() async {
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

  void _selectPreset(CommitmentKind value) => setState(() {
    kind = value;
    type = switch (value) {
      CommitmentKind.walk => VerifierType.walk,
      CommitmentKind.gym || CommitmentKind.arrive => VerifierType.location,
      CommitmentKind.focus => VerifierType.focus,
      CommitmentKind.workout => VerifierType.healthWorkout,
      CommitmentKind.leetcode => VerifierType.leetcode,
    };
    title.text = _presetTitle;
    error = null;
    _refreshReadiness();
  });

  void _toggleApp(String package) => setState(() {
    if (selectedPackages.remove(package)) return;
    // Free holding keeps a single app: picking another replaces it.
    if (!_focus && !_isPro) selectedPackages.clear();
    selectedPackages.add(package);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ScreenHeader(
                  leading: ShowdIconButton(
                    icon: ShowdIcons.close,
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  title: widget.existing == null
                      ? 'New proof alarm'
                      : 'Edit proof alarm',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ShowdSpace.gutter,
                ),
                child: StepLine(count: _stepCount, index: page),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    ShowdSpace.gutter,
                    ShowdSpace.s6,
                    ShowdSpace.gutter,
                    ShowdSpace.s6,
                  ),
                  children: [
                    KeyedSubtree(
                      key: ShowdKeys.wizardStep(page),
                      child: Text(_stepTitle, style: ShowdType.titleXL),
                    ),
                    const SizedBox(height: ShowdSpace.s2),
                    Text(_stepBody, style: ShowdType.bodyM),
                    const SizedBox(height: ShowdSpace.s6),
                    ...switch (page) {
                      0 => _presetStep(),
                      1 => _whenStep(),
                      2 => _appsStep(),
                      _ => _confirmStep(),
                    },
                    if (error != null) ...[
                      const SizedBox(height: ShowdSpace.s4),
                      ShowdNotice(error!),
                      if (!_preview && page >= 2)
                        ShowdButton(
                          label: page == 2
                              ? 'Open Accessibility settings'
                              : 'Open permissions',
                          tone: ShowdButtonTone.quiet,
                          onPressed: page == 2
                              ? BlockerChannel.openAccessibilitySettings
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => const PermissionsScreen(),
                                  ),
                                ),
                        ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShowdSpace.gutter - 4,
                  ShowdSpace.s2,
                  ShowdSpace.gutter,
                  ShowdSpace.s4,
                ),
                child: Row(
                  children: [
                    if (page > 0) ...[
                      ShowdIconButton(
                        icon: ShowdIcons.back,
                        semanticLabel: 'Back',
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                page--;
                                error = null;
                              }),
                      ),
                      const SizedBox(width: ShowdSpace.s2),
                    ],
                    Expanded(
                      child: ShowdButton(
                        key: ShowdKeys.wizardNext,
                        busy: busy,
                        label: page == _stepCount - 1
                            ? widget.existing == null
                                  ? 'Save alarm'
                                  : 'Save changes'
                            : 'Continue',
                        onPressed: next,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String get _holdName => Features.catchEnabled ? 'Catch' : 'Hold';

  String get _stepTitle => switch (page) {
    0 => 'What will you show up for?',
    1 => 'When should it ring?',
    2 when _focus => 'Which apps pull you away?',
    2 => Features.catchEnabled ? 'Catch an app?' : 'Hold an app until then?',
    _ => 'Ready?',
  };

  String get _stepBody => switch (page) {
    0 => 'Your phone checks it. There’s no “done” button to tap.',
    1 => 'Reminders repeat inside this window and stop when it closes.',
    2 when _focus => 'Ten seconds in one of these restarts the timer.',
    2 =>
      'Pick the app you reach for. It stays closed until you show up or end today. Optional.',
    _ => 'Change any of it later.',
  };

  List<Widget> _presetStep() => [
    for (final (preset, subtitle) in [
      (CommitmentKind.walk, 'Time or distance, checked by GPS'),
      (CommitmentKind.gym, 'Checks you in when you get there'),
      (CommitmentKind.arrive, 'Class, office, library'),
      (CommitmentKind.focus, 'Time away from the apps you pick'),
      (CommitmentKind.workout, 'Recorded in Health Connect'),
      (
        CommitmentKind.leetcode,
        'Accepted problems on your public profile · beta',
      ),
    ])
      // A hidden preset stays visible only while editing an alarm that
      // already uses it, so existing setups remain editable.
      if (Features.presetEnabled(preset) || kind == preset)
        ChoiceRow(
          key: ShowdKeys.wizardPreset(preset),
          title: kindLabel(preset),
          subtitle: subtitle,
          leading: ShowdIcon(
            kindIcon(preset),
            color: kind == preset ? ShowdColors.accent : ShowdColors.paper,
          ),
          selected: kind == preset,
          onTap: () => _selectPreset(preset),
        ),
    const SizedBox(height: ShowdSpace.s8),
    ..._presetDetail(),
  ];

  List<Widget> _presetDetail() => switch (kind) {
    CommitmentKind.walk => [
      const SectionLabel('Goal'),
      const SizedBox(height: ShowdSpace.s2),
      Wrap(
        spacing: ShowdSpace.s2,
        children: [
          for (final mode in WalkGoalMode.values)
            if (mode != WalkGoalMode.destination || walkMode == mode)
              ChoiceChip(
                label: Text(switch (mode) {
                  WalkGoalMode.duration => 'Time',
                  WalkGoalMode.distance => 'Distance',
                  WalkGoalMode.destination => 'Destination',
                }),
                selected: walkMode == mode,
                onSelected: (_) => setState(() {
                  walkMode = mode;
                  title.text = _presetTitle;
                }),
              ),
        ],
      ),
      const SizedBox(height: ShowdSpace.s4),
      ...switch (walkMode) {
        WalkGoalMode.duration => [
          _amount(
            value: '$walkMinutes',
            unit: 'minutes',
            slider: Slider(
              value: walkMinutes.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              label: '$walkMinutes min',
              onChanged: (v) => setState(() {
                walkMinutes = (v / 5).round() * 5;
                title.text = _presetTitle;
              }),
            ),
          ),
        ],
        WalkGoalMode.distance => [
          _amount(
            value: (walkDistanceM / 1000).toStringAsFixed(2),
            unit: 'km',
            slider: Slider(
              value: walkDistanceM.toDouble(),
              min: 250,
              max: 10000,
              divisions: 39,
              onChanged: (v) => setState(() {
                walkDistanceM = (v / 250).round() * 250;
                title.text = _presetTitle;
              }),
            ),
          ),
        ],
        WalkGoalMode.destination => _placePicker(),
      },
      const SizedBox(height: ShowdSpace.s3),
      Text(
        'Keep the phone on you. Fake and blurry locations don’t count.',
        style: ShowdType.caption,
      ),
    ],
    CommitmentKind.gym || CommitmentKind.arrive => [
      ..._placePicker(),
      const SizedBox(height: ShowdSpace.s3),
      Text(
        'Checks you stay within 150 m for ${kind == CommitmentKind.gym ? 5 : 2} minutes in a row.',
        style: ShowdType.caption,
      ),
    ],
    CommitmentKind.focus => [
      _amount(
        value: '$focusMinutes',
        unit: 'minutes, phone down',
        slider: Slider(
          value: focusMinutes.toDouble(),
          min: 5,
          max: 180,
          divisions: 35,
          onChanged: (v) => setState(() {
            focusMinutes = (v / 5).round() * 5;
            title.text = _presetTitle;
          }),
        ),
      ),
      Text('You’ll pick the apps in step 3.', style: ShowdType.caption),
    ],
    CommitmentKind.workout => [
      Wrap(
        spacing: ShowdSpace.s2,
        runSpacing: ShowdSpace.s2,
        children: [
          for (final value in HealthWorkoutConfig.supported)
            ChoiceChip(
              label: Text(
                value == 'any'
                    ? 'Any workout'
                    : value[0].toUpperCase() + value.substring(1),
              ),
              selected: workoutType == value,
              onSelected: (_) => setState(() => workoutType = value),
            ),
        ],
      ),
      const SizedBox(height: ShowdSpace.s4),
      _amount(
        value: '$workoutMinutes',
        unit: 'recorded minutes',
        slider: Slider(
          value: workoutMinutes.toDouble(),
          min: 10,
          max: 180,
          divisions: 34,
          onChanged: (v) => setState(() {
            workoutMinutes = (v / 5).round() * 5;
            title.text = _presetTitle;
          }),
        ),
      ),
    ],
    CommitmentKind.leetcode => [
      TextField(
        controller: username,
        autocorrect: false,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Public LeetCode username',
          helperText: 'No password, token or cookie. Ever.',
        ),
      ),
      const SizedBox(height: ShowdSpace.s6),
      _amount(
        value: '$targetAccepted',
        unit: targetAccepted == 1 ? 'accepted problem' : 'accepted problems',
        slider: Slider(
          value: targetAccepted.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (v) => setState(() {
            targetAccepted = v.round();
            title.text = _presetTitle;
          }),
        ),
      ),
      Text(
        'If LeetCode can’t be reached, the day counts as “couldn’t tell”, not missed.',
        style: ShowdType.caption,
      ),
    ],
  };

  List<Widget> _placePicker() => [
    Text(
      label.text.isEmpty
          ? kind == CommitmentKind.gym
                ? 'Which gym?'
                : 'Where to?'
          : label.text,
      style: ShowdType.titleM,
    ),
    if (placeAddress?.isNotEmpty == true)
      Text(placeAddress!, style: ShowdType.bodyM),
    const SizedBox(height: ShowdSpace.s4),
    ShowdButton(
      label: label.text.isEmpty ? 'Search places' : 'Change place',
      icon: ShowdIcons.arrive,
      tone: ShowdButtonTone.outline,
      onPressed: busy ? null : pickPlace,
    ),
    if (kind != CommitmentKind.walk)
      ShowdButton(
        label: 'Use where I am now',
        tone: ShowdButtonTone.quiet,
        onPressed: busy ? null : currentLocation,
      ),
  ];

  Widget _amount({
    required String value,
    required String unit,
    required Widget slider,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          BigNumber(
            value,
            style: ShowdType.numeralM,
            color: ShowdColors.accent,
          ),
          const SizedBox(width: ShowdSpace.s2),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(unit, style: ShowdType.label),
            ),
          ),
        ],
      ),
      slider,
    ],
  );

  List<Widget> _whenStep() {
    final isPro = _isPro;
    return [
      const SectionLabel('Days'),
      const SizedBox(height: ShowdSpace.s3),
      DayPicker(
        selected: days,
        onToggle: (day) => setState(() {
          if (!days.remove(day)) {
            days.add(day);
            dayStarts.putIfAbsent(day, () => start);
            dayEnds.putIfAbsent(day, () => end);
          }
        }),
      ),
      const SizedBox(height: ShowdSpace.s8),
      Row(
        children: [
          Expanded(
            child: _timeTile('Opens', start, (v) => setState(() => start = v)),
          ),
          const SizedBox(width: ShowdSpace.s4),
          Expanded(
            child: _timeTile('Closes', end, (v) => setState(() => end = v)),
          ),
        ],
      ),
      const SizedBox(height: ShowdSpace.s4),
      if (isPro) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('A different time each day'),
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
        if (customDayTimes)
          for (final day in (days.toList()..sort())) _dayWindowRow(day),
      ] else
        ShowdRow(
          title: 'A different time each day',
          subtitle: 'Mondays can start later than Fridays.',
          trailing: const ProPill(),
          onTap: () => openPro(context),
        ),
      const SizedBox(height: ShowdSpace.s8),
      const SectionLabel('Reminders'),
      const SizedBox(height: ShowdSpace.s3),
      Text('Every $interval minutes', style: ShowdType.bodyL),
      Slider(
        value: interval.toDouble(),
        min: 5,
        max: 120,
        divisions: 23,
        onChanged: (v) => setState(() => interval = (v / 5).round() * 5),
      ),
      Text(
        'Up to $maxReminders reminder${maxReminders == 1 ? '' : 's'}',
        style: ShowdType.bodyL,
      ),
      Slider(
        value: maxReminders.toDouble(),
        min: 1,
        max: 6,
        divisions: 5,
        onChanged: (v) => setState(() => maxReminders = v.round()),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Loud'),
        subtitle: Text(
          loud
              ? 'Full volume for up to 30 seconds. Snooze silences it.'
              : 'Uses your alarm volume.',
          style: ShowdType.bodyM,
        ),
        value: loud,
        onChanged: (v) => setState(() => loud = v),
      ),
      ShowdRow(
        leading: const ShowdIcon(ShowdIcons.calendar),
        title: 'Timezone',
        subtitle: zone.text,
        onTap: _editZone,
      ),
    ];
  }

  Widget _timeTile(
    String caption,
    TimeOfDay time,
    ValueChanged<TimeOfDay> change,
  ) => Semantics(
    button: true,
    label: '$caption at ${_clock(time)}',
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(ShowdRadius.control),
      onTap: () async {
        final value = await showTimePicker(context: context, initialTime: time);
        if (value != null) change(value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption, style: ShowdType.label),
            BigNumber(_clock(time), style: ShowdType.numeralM),
          ],
        ),
      ),
    ),
  );

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
    Future<void> pick(Map<int, TimeOfDay> target, TimeOfDay fallback) async {
      final value = await showTimePicker(
        context: context,
        initialTime: target[day] ?? fallback,
      );
      if (value != null) setState(() => target[day] = value);
    }

    return ShowdRow(
      title: names[day - 1],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => pick(dayStarts, start),
            child: Text(_clock(dayStarts[day] ?? start)),
          ),
          Text('–', style: ShowdType.bodyM),
          TextButton(
            onPressed: () => pick(dayEnds, end),
            child: Text(_clock(dayEnds[day] ?? end)),
          ),
        ],
      ),
    );
  }

  Future<void> _editZone() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Timezone'),
        content: TextField(
          controller: zone,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(
            helperText: 'Like Asia/Kolkata or Europe/London',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  List<Widget> _appsStep() {
    final isPro = _isPro;
    if (!_focus && !_canCatch) {
      return [
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.caught),
          title: 'Hold an app until you show up',
          subtitle: 'Your go-to app stays closed during the window.',
          trailing: const ProPill(),
          onTap: () => openPro(context),
        ),
        const SizedBox(height: ShowdSpace.s3),
        Text('Optional. Continue without it.', style: ShowdType.caption),
      ];
    }
    final showPicker = _focus || restrictionsEnabled;
    final query = appSearch.text.trim().toLowerCase();
    final apps = blockableApps.where(
      (app) =>
          query.isEmpty ||
          app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query),
    );
    return [
      if (!_focus)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('$_holdName an app'),
          subtitle: Text(
            isPro
                ? 'Opens again when you show up or end today.'
                : 'Free holds one app. Pro holds as many as you like.',
            style: ShowdType.bodyM,
          ),
          value: restrictionsEnabled,
          onChanged: (value) async {
            setState(() => restrictionsEnabled = value);
            if (value) {
              await _loadBlockableApps();
              await _refreshReadiness();
            }
          },
        )
      else
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also hold these apps'),
          subtitle: Text(
            _canCatch
                ? isPro
                      ? 'They stay closed until the timer is done.'
                      : 'Free holds one app.'
                : 'Pro',
            style: ShowdType.bodyM,
          ),
          value: _canCatch && restrictionsEnabled,
          onChanged: (value) {
            if (!_canCatch) {
              openPro(context);
              return;
            }
            setState(() => restrictionsEnabled = value);
          },
        ),
      if (showPicker) ...[
        const SizedBox(height: ShowdSpace.s3),
        const ShowdNotice(
          'Android Accessibility tells ShowdUp only which app is in front. It never reads the screen, what you type or passwords.',
          icon: ShowdIcons.shield,
        ),
        if (!_preview && blockerStatus?.accessibilityEnabled != true)
          ShowdButton(
            label: 'Turn on Accessibility access',
            tone: ShowdButtonTone.outline,
            onPressed: BlockerChannel.openAccessibilitySettings,
          ),
        const SizedBox(height: ShowdSpace.s4),
        if (loadingApps)
          const Center(child: CircularProgressIndicator())
        else if (blockableApps.isEmpty)
          ShowdButton(
            label: _preview ? 'Apps load on your phone' : 'Load my apps',
            tone: ShowdButtonTone.quiet,
            onPressed: _preview ? null : _loadBlockableApps,
          )
        else ...[
          TextField(
            controller: appSearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Search apps'),
          ),
          const SizedBox(height: ShowdSpace.s2),
          for (final app in apps)
            _AppRow(
              app: app,
              selected: selectedPackages.contains(app.packageName),
              onTap: () => _toggleApp(app.packageName),
            ),
        ],
      ],
    ];
  }

  List<Widget> _confirmStep() {
    final preview = _preview;
    final permission = alarmPermissions;
    final apps = selectedPackages
        .map(
          (package) =>
              blockableApps
                  .where((app) => app.packageName == package)
                  .map((app) => app.label)
                  .firstOrNull ??
              package,
        )
        .toList();
    Widget ready(String name, bool ok, Future<void> Function() fix) => ShowdRow(
      leading: ShowdIcon(
        ok ? ShowdIcons.check : ShowdIcons.bell,
        color: ok ? ShowdColors.accent : ShowdColors.stone,
      ),
      title: name,
      trailing: ok
          ? Text('Ready', style: ShowdType.bodyM)
          : TextButton(
              onPressed: () async {
                await fix();
                await _refreshReadiness();
              },
              child: const Text('Allow'),
            ),
    );
    return [
      BigNumber(_clock(start), semanticLabel: 'Rings at ${_clock(start)}'),
      Text(_presetTitle, style: ShowdType.titleL),
      Text(_goalSummary, style: ShowdType.bodyM),
      const SizedBox(height: ShowdSpace.s6),
      ShowdRow(
        leading: const ShowdIcon(ShowdIcons.calendar),
        title: daysLabel(days.toList()),
        subtitle: customDayTimes && _isPro
            ? 'Own time each day · ${zone.text}'
            : '${_clock(start)}–${_clock(end)} · ${zone.text}',
        onTap: () => setState(() => page = 1),
      ),
      ShowdRow(
        leading: const ShowdIcon(ShowdIcons.snooze),
        title: 'Every $interval minutes',
        subtitle:
            'Up to $maxReminders reminder${maxReminders == 1 ? '' : 's'} · ${loud ? 'loud' : 'your alarm volume'}',
        onTap: () => setState(() => page = 1),
      ),
      if (_focus || (_canCatch && restrictionsEnabled))
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.caught),
          title: restrictionsEnabled && _canCatch
              ? 'Holds ${apps.length} app${apps.length == 1 ? '' : 's'}'
              : 'Watches ${apps.length} app${apps.length == 1 ? '' : 's'}',
          subtitle: apps.isEmpty ? null : apps.join(', '),
          onTap: () => setState(() => page = 2),
        ),
      const SizedBox(height: ShowdSpace.s8),
      const SectionLabel('Before it can ring'),
      const SizedBox(height: ShowdSpace.s2),
      ready(
        'Notifications',
        preview || permission?.notifications == true,
        () => AlarmChannel.requestPermission('notifications'),
      ),
      ready(
        'Exact alarms',
        preview || permission?.exactAlarm == true,
        () => AlarmChannel.requestPermission('exactAlarm'),
      ),
      if (type == VerifierType.walk || type == VerifierType.location)
        ready(
          'Precise location',
          preview || permission?.location == true,
          () => AlarmChannel.requestPermission('location'),
        ),
      if (type == VerifierType.healthWorkout)
        ready(
          'Health Connect',
          preview || healthAvailability?.permissionsGranted == true,
          HealthChannel.requestPermissions,
        ),
      if (_focus || (_canCatch && restrictionsEnabled))
        ready(
          'Accessibility access',
          preview || blockerStatus?.accessibilityEnabled == true,
          BlockerChannel.openAccessibilitySettings,
        ),
      const SizedBox(height: ShowdSpace.s3),
      Text(
        'If something’s missing it saves as a draft and waits.',
        style: ShowdType.caption,
      ),
    ];
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.selected,
    required this.onTap,
  });

  final BlockableApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    button: true,
    label: app.label,
    excludeSemantics: true,
    child: InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s2),
        child: Row(
          children: [
            LetterAvatar(app.label, size: 36),
            const SizedBox(width: ShowdSpace.s3),
            Expanded(
              child: Text(
                app.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShowdType.bodyL,
              ),
            ),
            RadioDot(selected: selected),
          ],
        ),
      ),
    ),
  );
}
