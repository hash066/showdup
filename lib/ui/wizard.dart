import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/commitment.dart';
import '../models/verifier_config.dart';
import '../models/enums.dart';
import '../platform/alarm_channel.dart';
import '../platform/overlay_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../platform/blocker_channel.dart';
import '../services/controller.dart';
import '../verification/verifier_registry.dart';
import 'app.dart';
import 'widgets.dart';
import 'screens.dart';

class CommitmentWizard extends ConsumerStatefulWidget {
  const CommitmentWizard({super.key, this.existing});
  final Commitment? existing;
  @override
  ConsumerState<CommitmentWizard> createState() => _CommitmentWizardState();
}

class _CommitmentWizardState extends ConsumerState<CommitmentWizard> {
  final title = TextEditingController(),
      lat = TextEditingController(),
      lng = TextEditingController(),
      label = TextEditingController(),
      zone = TextEditingController();
  int page = 0,
      target = 1000,
      interval = 20,
      maxReminders = 6,
      dwell = 5,
      radius = 150;
  bool loud = false,
      busy = false,
      restrictionsEnabled = false,
      customDayTimes = false;
  String? error;
  List<BlockableApp> blockableApps = const [];
  final Set<String> selectedPackages = {};
  bool loadingApps = false;
  VerifierType type = VerifierType.steps;
  Set<int> days = {1, 2, 3, 4, 5};
  final Map<int, TimeOfDay> dayStarts = {};
  final Map<int, TimeOfDay> dayEnds = {};
  TimeOfDay start = const TimeOfDay(hour: 6, minute: 30),
      end = const TimeOfDay(hour: 9, minute: 0);
  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      title.text = c.title;
      type = c.verifierType;
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
      if (cfg is StepsConfig) target = cfg.targetSteps;
      if (cfg is LocationConfig) {
        lat.text = cfg.lat.toString();
        lng.text = cfg.lng.toString();
        label.text = cfg.label ?? '';
        dwell = cfg.dwellMs ~/ 60000;
        radius = cfg.radiusM;
      }
    } else {
      title.text = 'Morning walk';
      zone.text = ref.read(appProvider).user?.timezone ?? 'Asia/Kolkata';
    }
  }

  @override
  void dispose() {
    for (final c in [title, lat, lng, label, zone]) {
      c.dispose();
    }
    super.dispose();
  }

  TimeOfDay _time(String s) => TimeOfDay(
    hour: int.parse(s.split(':')[0]),
    minute: int.parse(s.split(':')[1]),
  );
  String _clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  VerifierConfig get config => type == VerifierType.steps
      ? StepsConfig(targetSteps: target)
      : LocationConfig(
          lat: double.tryParse(lat.text) ?? double.nan,
          lng: double.tryParse(lng.text) ?? double.nan,
          radiusM: radius,
          dwellMs: dwell * 60000,
          label: label.text.trim(),
        );
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
      if (title.text.trim().isEmpty || title.text.trim().length > 80) {
        setState(
          () => error = 'Give your commitment a name, up to 80 characters.',
        );
        return;
      }
      if (config.validate() != null) {
        setState(() => error = config.validate());
        return;
      }
    }
    if (page == 1 && schedule.validate() != null) {
      setState(() => error = schedule.validate());
      return;
    }
    if (page == 2 && !ref.read(appProvider).preview) {
      var permissions = await AlarmChannel.getPermissionStatus();
      if (!permissions.notifications) {
        await AlarmChannel.requestPermission('notifications');
        permissions = await AlarmChannel.getPermissionStatus();
      }
      if (!permissions.notifications || !permissions.exactAlarm) {
        setState(
          () => error = !permissions.notifications
              ? 'Allow notifications before saving. Without them, ShowdUp cannot remind you.'
              : 'Enable exact reminders in Android settings before saving. Without them, Android may delay the recurring reminders you chose.',
        );
        return;
      }
    }
    final isPro = ref.read(appProvider).user?.isPro == true;
    if (page == 3 && isPro && restrictionsEnabled) {
      if (selectedPackages.isEmpty) {
        setState(() => error = 'Choose at least one distracting app.');
        return;
      }
      final status = await BlockerChannel.status();
      if (!status.accessibilityEnabled) {
        setState(
          () => error =
              'Enable ShowdUp accessibility access so it can detect and cover only the apps you selected.',
        );
        return;
      }
    }
    if (page < 4) {
      setState(() => page++);
      if (page == 3 && isPro) await _loadBlockableApps();
      return;
    }
    await save();
  }

  Future<void> save() async {
    setState(() => busy = true);
    final app = ref.read(appProvider);
    final firstCommitment = widget.existing == null && app.commitments.isEmpty;
    try {
      if (!app.preview) {
        final verifier = VerifierRegistry().create(type);
        final availability = await verifier.checkAvailability(config);
        if (!availability.available) {
          setState(
            () => error =
                availability.reason ??
                'Check required permissions before saving.',
          );
          return;
        }
      }
      final data = {
        'title': title.text.trim(),
        'verifierType': type.wire,
        'verifierConfig': config.toJson(),
        'schedule': schedule.toJson(),
        'reminder': ReminderConfig(
          intervalMinutes: interval,
          volumeMode: loud ? VolumeMode.loud : VolumeMode.gentle,
          maxReminders: maxReminders,
        ).toJson(),
        'restrictions': Restrictions(
          enabled: app.user?.isPro == true && restrictionsEnabled,
          packages: app.user?.isPro == true
              ? (selectedPackages.toList()..sort())
              : const [],
        ).toJson(),
      };
      if (widget.existing == null) {
        await app.repository.create(data);
      } else {
        await app.repository.update(widget.existing!.id, data);
      }
      await app.refresh();
      if (firstCommitment && mounted) await _offerOverlay();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
      }
    } catch (e) {
      setState(() => error = friendlyError(e));
    } finally {
      setState(() => busy = false);
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
                  5,
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
                  Eyebrow('Step ${page + 1} of 5'),
                  const SizedBox(height: 12),
                  Text(
                    [
                      'Choose your finish line.',
                      'Give it a place in your day.',
                      'Reminders, on your terms.',
                      'Choose your guardrails.',
                      'This is your promise.',
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
                    0 => _goal(),
                    1 => _schedule(),
                    2 => _reminders(),
                    3 => _restrictions(),
                    _ => _review(),
                  },
                  if (error != null) ...[
                    const SizedBox(height: 18),
                    ErrorNotice(error!),
                    if (!ref.read(appProvider).preview)
                      TextButton(
                        onPressed: page == 3
                            ? BlockerChannel.openAccessibilitySettings
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => const PermissionsScreen(),
                                ),
                              ),
                        child: Text(
                          page == 3
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
                              : page == 4
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
  List<Widget> _goal() => [
    TextField(
      controller: title,
      maxLength: 80,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'What are you showing up for?',
        hintText: 'Morning walk',
      ),
    ),
    const SizedBox(height: 18),
    const Eyebrow('What counts as done?'),
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(
          child: _typeCard(
            VerifierType.steps,
            Icons.directions_walk,
            'Record steps',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _typeCard(
            VerifierType.location,
            Icons.place_outlined,
            'Arrive & stay',
          ),
        ),
      ],
    ),
    const SizedBox(height: 24),
    if (type == VerifierType.steps) ...[
      Panel(
        child: Column(
          children: [
            const Eyebrow('New steps after your window opens'),
            const SizedBox(height: 12),
            Text(
              '$target',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: T.accent,
              ),
            ),
            Slider(
              value: target.toDouble(),
              min: 200,
              max: 20000,
              divisions: 99,
              onChanged: (v) => setState(() => target = v.round()),
            ),
            const Text(
              'Start small. You can adjust it later.',
              style: TextStyle(color: T.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Steps prove recorded movement, not a walk. Keep your phone with you. A hardware step counter is required.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ] else ...[
      TextField(
        controller: label,
        decoration: const InputDecoration(
          labelText: 'Place name',
          hintText: 'My gym',
        ),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: busy ? null : currentLocation,
        icon: const Icon(Icons.my_location),
        label: const Text('Use my current location'),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: lng,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Text('Arrival radius · $radius m'),
      Slider(
        value: radius.toDouble(),
        min: 100,
        max: 500,
        divisions: 8,
        onChanged: (v) => setState(() => radius = v.round()),
      ),
      Text('Stay for · $dwell minutes'),
      Slider(
        value: dwell.toDouble().clamp(1, 30),
        min: 1,
        max: 30,
        divisions: 29,
        onChanged: (v) => setState(() => dwell = v.round()),
      ),
      const Text(
        '150 m or more is recommended. Location proves presence near a place, not a workout. Open the app to start verification.',
        style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
      ),
    ],
  ];
  Widget _typeCard(VerifierType value, IconData icon, String label) => InkWell(
    onTap: () => setState(() => type = value),
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: type == value ? T.accent.withValues(alpha: .10) : T.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: type == value ? T.accent : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: type == value ? T.accent : T.muted, size: 30),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
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
    if (!isPro) {
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
      SwitchListTile(
        contentPadding: const EdgeInsets.all(12),
        title: const Text('Block selected distractions'),
        subtitle: const Text(
          'ShowdUp observes the foreground app only while a restriction is active. It does not read typed text or screen contents.',
          style: TextStyle(color: T.muted, fontSize: 12, height: 1.5),
        ),
        value: restrictionsEnabled,
        onChanged: (value) async {
          setState(() => restrictionsEnabled = value);
          if (value) await _loadBlockableApps();
        },
      ),
      if (restrictionsEnabled) ...[
        const SizedBox(height: 12),
        const ErrorNotice(
          'Accessibility access lets ShowdUp notice when a selected app opens and place a blocking screen over it. You can disable access or uninstall ShowdUp at any time.',
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
          ...blockableApps.map(
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
            type == VerifierType.steps
                ? Icons.directions_walk
                : Icons.place_outlined,
            color: T.accent,
            size: 34,
          ),
          const SizedBox(height: 20),
          Text(
            title.text,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(
            type == VerifierType.steps
                ? '$target new steps'
                : 'Stay near ${label.text.isEmpty ? 'your destination' : label.text} for $dwell minutes',
            style: const TextStyle(color: T.muted),
          ),
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
        'Remember to open ShowdUp or tap a reminder. Location verification cannot start until you do.',
        style: TextStyle(color: T.accent, height: 1.6, fontSize: 13),
      ),
    ],
  ];
}
