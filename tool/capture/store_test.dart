// Renders the Google Play store assets with the real brand fonts into
// tool/capture/out/store/:
//
//   flutter test --update-goldens tool/capture/store_test.dart
//   python tool/capture/store_assets.py
//
// The second step flattens the renders onto ink (Play rejects screenshots with
// an alpha channel) and copies them into docs/store-assets/.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showdup/design/mark.dart';
import 'package:showdup/design/theme.dart';
import 'package:showdup/design/tokens.dart';
import 'package:showdup/design/type.dart';
import 'package:showdup/core/scheduling.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/models/commitment.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/verifier_config.dart';
import 'package:showdup/services/controller.dart';
import 'package:showdup/services/repository.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:showdup/ui/app.dart';
import 'package:showdup/ui/keys.dart';
import 'package:showdup/ui/onboarding.dart';
import 'package:showdup/ui/screens.dart';
import 'package:timezone/data/latest.dart' as tz;

Future<void> _loadFonts() async {
  Future<ByteData> font(String name) => rootBundle.load('assets/fonts/$name');
  await (FontLoader(
    'BigShoulders',
  )..addFont(font('BigShouldersDisplay-ExtraBold.ttf'))).load();
  await (FontLoader('Bricolage')
        ..addFont(font('BricolageGrotesque-Regular.ttf'))
        ..addFont(font('BricolageGrotesque-Medium.ttf'))
        ..addFont(font('BricolageGrotesque-Bold.ttf')))
      .load();
  await (FontLoader(
    'Roboto',
  )..addFont(font('BricolageGrotesque-Medium.ttf'))).load();
}

/// Play phone screenshots may be at most twice as long as they are wide.
const _phone = Size(1080, 2160);

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await _loadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> render(
    WidgetTester tester,
    String name,
    Widget home, {
    Size size = _phone,
    double ratio = 3,
    AppController? controller,
    Future<void> Function()? before,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildShowdTheme(),
      home: home,
    );
    await tester.pumpWidget(
      controller == null
          ? app
          : ProviderScope(
              overrides: [appProvider.overrideWith((ref) => controller)],
              child: app,
            ),
    );
    await tester.pumpAndSettle();
    if (before != null) {
      await before();
      await tester.pumpAndSettle();
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('out/store/$name.png'),
    );
    expect(tester.takeException(), isNull, reason: name);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Sample data that reads like a real morning: a 06:30–09:00 walk of 3,000
  /// steps, ringing now. The alarm lives in whichever timezone is inside that
  /// window at the moment the renders run, so every run shows the same clock.
  Future<AppController> preview({String? state}) async {
    final prefs = await SharedPreferences.getInstance();
    final zone = _morningZone();
    final schedule = CommitmentSchedule(
      daysOfWeek: const [1, 2, 3, 4, 5, 6, 7],
      windowStartLocal: '06:30',
      windowEndLocal: '09:00',
      timezone: zone.name,
    );
    final commitment = Commitment(
      id: 'preview-walk',
      ownerUid: 'preview',
      title: 'Morning walk',
      verifierType: VerifierType.steps,
      verifierConfig: const StepsConfig(targetSteps: 3000),
      schedule: schedule,
      reminder: const ReminderConfig(),
      restrictions: const Restrictions(),
      status: CommitmentStatus.active,
    );
    final today = tz.TZDateTime.now(zone);
    final attempts = [
      for (var i = 0; i < 7; i++)
        () {
          final day = DateTime(today.year, today.month, today.day - i);
          final w = resolveWindow(schedule, day);
          final date =
              '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
          final done = i > 0 && i != 4;
          return Attempt(
            id: 'preview-walk_$date',
            commitmentId: 'preview-walk',
            ownerUid: 'preview',
            date: date,
            windowStartAt: w.start,
            windowEndAt: w.end,
            state: i == 0
                ? (state == null
                      ? AttemptState.pending
                      : AttemptState.values.firstWhere((s) => s.wire == state))
                : i == 4
                ? AttemptState.abandoned
                : AttemptState.completed,
            completedAt: done || (i == 0 && state != null)
                ? w.start.add(const Duration(minutes: 41))
                : null,
          );
        }(),
    ];
    await prefs.setString(
      'previewData',
      jsonEncode({
        'commitments': [
          {'id': commitment.id, ...commitment.toJson()},
        ],
        'attempts': [
          for (final a in attempts) {'id': a.id, ...a.toJson()},
        ],
      }),
    );
    return AppController(PreviewRepository(prefs));
  }

  Future<String> firstAttemptId() async {
    final repository = PreviewRepository(await SharedPreferences.getInstance());
    final id = (await repository.attempts().first).first.id;
    await repository.close();
    return id;
  }

  testWidgets('icon', (t) async {
    await render(
      t,
      'high-res-icon',
      const _Icon(),
      size: const Size(512, 512),
      ratio: 1,
    );
  });

  testWidgets('feature graphic', (t) async {
    await render(
      t,
      'feature-graphic',
      const _FeatureGraphic(),
      size: const Size(1024, 500),
      ratio: 1,
    );
  });

  testWidgets('phone 1 welcome', (t) async {
    await render(
      t,
      'phone-01-welcome',
      WelcomeScreen(onPreview: () {}, onAuthenticated: () async {}),
    );
  });

  testWidgets('phone 2 alarms', (t) async {
    final prefs = await SharedPreferences.getInstance();
    await render(
      t,
      'phone-02-alarms',
      HomeShell(onLogout: () async {}, prefs: prefs),
      controller: await preview(),
      before: () => t.tap(find.byKey(ShowdKeys.navAlarms)),
    );
  });

  for (final (name, state) in [
    ('phone-03-proof', null),
    ('phone-04-showed-up', AttemptState.completed.wire),
  ]) {
    testWidgets(name, (t) async {
      final controller = await preview(state: state);
      await render(
        t,
        name,
        AttemptScreen(attemptId: await firstAttemptId()),
        controller: controller,
      );
    });
  }

  testWidgets('phone 5 history', (t) async {
    final prefs = await SharedPreferences.getInstance();
    await render(
      t,
      'phone-05-history',
      HomeShell(onLogout: () async {}, prefs: prefs),
      controller: await preview(),
      before: () => t.tap(find.byKey(ShowdKeys.navHistory)),
    );
  });

  testWidgets('phone 6 research', (t) async {
    await render(
      t,
      'phone-06-research',
      WhyThisWorksScreen(onContinue: () async {}),
    );
  });
}

/// A timezone whose clock reads between 06:40 and 08:50 right now.
tz.Location _morningZone() {
  const zones = [
    'Pacific/Kiritimati', 'Pacific/Tongatapu', 'Pacific/Auckland',
    'Pacific/Noumea', 'Australia/Brisbane', 'Asia/Tokyo', 'Asia/Shanghai',
    'Asia/Bangkok', 'Asia/Dhaka', 'Asia/Kolkata', 'Asia/Karachi', 'Asia/Dubai',
    'Europe/Moscow', 'Africa/Cairo', 'Africa/Lagos', 'Africa/Abidjan',
    'Atlantic/Azores', 'America/Noronha', 'America/Sao_Paulo',
    'America/Halifax', 'America/New_York', 'America/Chicago',
    'America/Denver', 'America/Los_Angeles', 'America/Anchorage',
    'Pacific/Honolulu', 'Pacific/Pago_Pago',
  ];
  for (final name in zones) {
    if (!tz.timeZoneDatabase.locations.containsKey(name)) continue;
    final location = tz.getLocation(name);
    final now = tz.TZDateTime.now(location);
    final minutes = now.hour * 60 + now.minute;
    if (minutes >= 6 * 60 + 40 && minutes <= 8 * 60 + 50) return location;
  }
  return tz.getLocation('Asia/Kolkata');
}

/// The launcher icon at store size: the mark in ink on the accent square.
/// Play rounds the corners itself.
class _Icon extends StatelessWidget {
  const _Icon();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: ShowdColors.accent,
    child: Center(
      child: ShowdMark(
        state: MarkState.showedUp,
        size: 512 * 0.75 * 96 / 108,
        lineColor: ShowdColors.ink,
        dotColor: ShowdColors.ink,
      ),
    ),
  );
}

/// 1024 x 500. Play may crop the edges and overlay a play button in the
/// middle on some surfaces, so the words sit left and the mark sits right.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic();

  @override
  Widget build(BuildContext context) => Material(
    color: ShowdColors.ink,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 72, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const ShowdMark(state: MarkState.showedUp, size: 44),
                    const SizedBox(width: 12),
                    Text(
                      'ShowdUp',
                      style: ShowdType.titleL.copyWith(fontSize: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                Text(
                  'An alarm you have\nto show up for.',
                  style: ShowdType.hero.copyWith(fontSize: 56, height: 1.02),
                ),
                const SizedBox(height: 18),
                Text(
                  'It rings until your phone can tell.',
                  style: ShowdType.bodyL.copyWith(
                    fontSize: 20,
                    color: ShowdColors.stone,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 300,
            height: 300,
            child: CustomPaint(
              painter: _Waves(),
              child: Center(
                child: ShowdMark(state: MarkState.ringing, size: 180),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Two sound waves over the bell, as the ringing mark draws them mid-ring.
class _Waves extends CustomPainter {
  const _Waves();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (final (radius, alpha) in [(0.36, 0.7), (0.48, 0.35)]) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = ShowdColors.accent.withValues(alpha: alpha);
      final rect = Rect.fromCircle(center: center, radius: size.width * radius);
      canvas.drawArc(rect, -3.1416 * 0.85, 3.1416 * 0.7, false, paint);
    }
  }

  @override
  bool shouldRepaint(_Waves old) => false;
}
