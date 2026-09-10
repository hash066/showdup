import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/commitment.dart';
import '../models/verifier_config.dart';
import '../models/enums.dart';
import '../platform/alarm_channel.dart';
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
  bool loud = false, busy = false, locating = false;
  String? error;
  VerifierType type = VerifierType.steps;
  Set<int> days = {1, 2, 3, 4, 5};
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
      zone.text = c.schedule.timezone;
      interval = c.reminder.intervalMinutes;
      maxReminders = c.reminder.maxReminders;
      loud = c.reminder.volumeMode == VolumeMode.loud;
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
  CommitmentSchedule get schedule => CommitmentSchedule(
    daysOfWeek: days.toList()..sort(),
    windowStartLocal: _clock(start),
    windowEndLocal: _clock(end),
    timezone: zone.text.trim(),
  );
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
    if (page < 3) {
      setState(() => page++);
      return;
    }
    await save();
  }

  Future<void> save() async {
    setState(() => busy = true);
    final app = ref.read(appProvider);
    try {
      if (!app.preview) {
        final verifier = VerifierRegistry().create(type);
        final availability = await verifier.checkAvailability(config);
        if (!mounted) return;
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
        'restrictions': const Restrictions().toJson(),
      };
      if (widget.existing == null) {
        await app.repository.create(data);
      } else {
        // Send only what changed: the server refuses non-title edits while
        // today's window is open, so a title fix must not carry the schedule.
        final before = widget.existing!.toJson();
        final patch = {
          for (final e in data.entries)
            if (jsonEncode(e.value) != jsonEncode(before[e.key]))
              e.key: e.value,
        };
        if (patch.isNotEmpty) {
          await app.repository.update(widget.existing!.id, patch);
        }
      }
      await app.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> currentLocation() async {
    if (locating) return;
    setState(() {
      locating = true;
      error = null;
    });
    try {
      await AlarmChannel.requestPermission('location');
      final p = await const MethodChannel(
        'app.showdup/location',
      ).invokeMapMethod<String, dynamic>('currentLocation');
      if (p != null && mounted) {
        lat.text = (p['lat'] as num).toStringAsFixed(6);
        lng.text = (p['lng'] as num).toStringAsFixed(6);
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => locating = false);
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
                  4,
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow('Step ${page + 1} of 4'),
                    const SizedBox(height: 12),
                    Text(
                      [
                        'Choose your finish line.',
                        'Give it a place in your day.',
                        'Reminders, on your terms.',
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
                      _ => _review(),
                    },
                  ],
                ),
              ),
            ),
            Flexible(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (error != null) ...[
                        ErrorNotice(error!),
                        if (!ref.read(appProvider).preview)
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const PermissionsScreen(),
                              ),
                            ),
                            child: const Text('Open permissions & reliability'),
                          ),
                      ],
                      Row(
                        children: [
                          if (page > 0) ...[
                            IconButton(
                              tooltip: 'Back',
                              onPressed: busy || locating
                                  ? null
                                  : () => setState(() {
                                      page--;
                                      error = null;
                                    }),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: FilledButton(
                              onPressed: busy || locating ? null : next,
                              child: Text(
                                busy
                                    ? 'Saving…'
                                    : page == 3
                                    ? widget.existing == null
                                          ? 'I’m showing up  →'
                                          : 'Save changes'
                                    : 'Continue  →',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
    LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _typeCard(VerifierType.steps, Icons.directions_walk, 'Record steps'),
          _typeCard(
            VerifierType.location,
            Icons.place_outlined,
            'Arrive & stay',
          ),
        ];
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(16) > 22) {
          return Column(
            children: [cards.first, const SizedBox(height: 12), cards.last],
          );
        }
        return Row(
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: 12),
            Expanded(child: cards.last),
          ],
        );
      },
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
              value: target.toDouble().clamp(200, 20000),
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
        onPressed: busy || locating ? null : currentLocation,
        icon: const Icon(Icons.my_location),
        label: Text(
          locating ? 'Finding your location…' : 'Use my current location',
        ),
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
        value: radius.toDouble().clamp(100, 500),
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
  Widget _typeCard(
    VerifierType value,
    IconData icon,
    String label,
  ) => Semantics(
    button: true,
    selected: type == value,
    label: label,
    child: ExcludeSemantics(
      child: InkWell(
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  List<Widget> _schedule() => [
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
          onSelected: (v) =>
              setState(() => v ? days.add(i + 1) : days.remove(i + 1)),
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
  Widget _timeRow(
    String label,
    TimeOfDay time,
    void Function(TimeOfDay) change,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final button = TextButton(
        onPressed: () async {
          final v = await showTimePicker(context: context, initialTime: time);
          if (v != null && mounted) change(v);
        },
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _clock(time),
            maxLines: 1,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ),
      );
      // Large text on a narrow screen stacks the label above the time.
      if (constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(16) > 22) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label), button],
        );
      }
      return Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(child: button),
        ],
      );
    },
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
            'Repeat every $interval minutes',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Slider(
            value: interval.toDouble().clamp(5, 120),
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
            value: maxReminders.toDouble().clamp(1, 20),
            min: 1,
            max: 20,
            divisions: 19,
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
            '${days.length} days a week · ${zone.text}',
            style: const TextStyle(color: T.muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Text(
            'Every $interval minutes · up to $maxReminders reminders',
            style: const TextStyle(fontSize: 12),
          ),
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
