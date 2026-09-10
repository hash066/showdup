import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:showdup/main.dart';
import 'package:showdup/core/theme.dart';
import 'package:showdup/models/app_user.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/models/commitment.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/verifier_config.dart';
import 'package:showdup/services/controller.dart';
import 'package:showdup/services/repository.dart';
import 'package:showdup/ui/app.dart';
import 'package:showdup/ui/screens.dart';
import 'package:showdup/ui/wizard.dart';

/// Every screen reachable in preview must render without layout exceptions
/// on the smallest supported phone with 200% text and on a large phone.
typedef Viewport = ({String name, Size size, double textScale});

const viewports = <Viewport>[
  (name: '320x700 @2.0', size: Size(320, 700), textScale: 2.0),
  (name: '430x932 @1.0', size: Size(430, 932), textScale: 1.0),
];

const _alarm = MethodChannel('app.showdup/alarm');

void useViewport(WidgetTester tester, Viewport v) {
  tester.view.physicalSize = v.size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = v.textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void mockAlarmChannel(
  WidgetTester tester, {
  Future<Object?> Function(MethodCall call)? handler,
  String? launchAttemptId,
}) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    _alarm,
    handler ??
        (call) async {
          if (call.method == 'getLaunchAttempt') return launchAttemptId;
          if (call.method == 'getPermissionStatus') {
            return {
              'exactAlarm': true,
              'notifications': true,
              'batteryOptimised': true,
              'fullScreenIntent': false,
              'activityRecognition': true,
              'location': false,
            };
          }
          return true;
        },
  );
  addTearDown(() => messenger.setMockMethodCallHandler(_alarm, null));
}

const _schedule = CommitmentSchedule(
  daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
  windowStartLocal: '06:30',
  windowEndLocal: '09:00',
  timezone: 'Asia/Kolkata',
);

Commitment walk({CommitmentStatus status = CommitmentStatus.active}) =>
    Commitment(
      id: 'walk',
      ownerUid: 'preview',
      title: 'Morning walk',
      verifierType: VerifierType.steps,
      verifierConfig: const StepsConfig(targetSteps: 1000),
      schedule: _schedule,
      reminder: const ReminderConfig(),
      restrictions: const Restrictions(),
      status: status,
    );

Commitment gym({CommitmentStatus status = CommitmentStatus.paused}) =>
    Commitment(
      id: 'gym',
      ownerUid: 'preview',
      title: 'Arrive at the neighbourhood gym before work',
      verifierType: VerifierType.location,
      verifierConfig: const LocationConfig(
        lat: 12.9716,
        lng: 77.5946,
        dwellMs: 600000,
        label: 'Neighbourhood gym',
      ),
      schedule: _schedule,
      reminder: const ReminderConfig(
        intervalMinutes: 10,
        volumeMode: VolumeMode.loud,
        maxReminders: 12,
      ),
      restrictions: const Restrictions(),
      status: status,
    );

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today's attempts get a window around "now" so open/not-open is
/// deterministic regardless of the machine's timezone.
Attempt attempt(
  String commitmentId,
  int daysAgo,
  AttemptState state, {
  bool future = false,
}) {
  final now = DateTime.now();
  final date = DateTime(now.year, now.month, now.day - daysAgo);
  final start = daysAgo > 0
      ? date.add(const Duration(hours: 6))
      : future
      ? now.add(const Duration(hours: 2))
      : now.subtract(const Duration(hours: 1));
  final end = daysAgo > 0
      ? date.add(const Duration(hours: 9))
      : future
      ? now.add(const Duration(hours: 3))
      : now.add(const Duration(hours: 1));
  return Attempt(
    id: '${commitmentId}_${_day(date)}',
    commitmentId: commitmentId,
    ownerUid: 'preview',
    date: _day(date),
    windowStartAt: start,
    windowEndAt: end,
    state: state,
  );
}

List<Commitment> richCommitments() => [walk(), gym()];
List<Attempt> richAttempts() => [
  attempt('walk', 0, AttemptState.pending),
  attempt('gym', 0, AttemptState.pending, future: true),
  attempt('walk', 1, AttemptState.completed),
  attempt('gym', 1, AttemptState.unverifiable),
  attempt('walk', 2, AttemptState.abandoned),
  attempt('walk', 3, AttemptState.expired),
];

Future<AppController> previewApp({
  required List<Commitment> commitments,
  required List<Attempt> attempts,
}) async {
  SharedPreferences.setMockInitialValues({
    'previewData': jsonEncode({
      'commitments': [
        for (final c in commitments) {'id': c.id, ...c.toJson()},
      ],
      'attempts': [
        for (final a in attempts) {'id': a.id, ...a.toJson()},
      ],
    }),
  });
  return AppController(PreviewRepository(await SharedPreferences.getInstance()));
}

/// A signed-in session without Firebase, for screens that differ when live.
class FakeLiveRepository implements Repository {
  FakeLiveRepository(this.cs, this.as, {this.offline = false});
  final List<Commitment> cs;
  final List<Attempt> as;
  final bool offline;
  final calls = <String>[];
  @override
  bool get isPreview => false;
  @override
  Stream<List<Commitment>> commitments() => Stream.value(cs);
  @override
  Stream<List<Attempt>> attempts() => Stream.value(as);
  @override
  Stream<AppUser> profile() => Stream.value(
    const AppUser(
      uid: 'u',
      displayName: 'Asha Verma-Krishnamurthy',
      timezone: 'Asia/Kolkata',
    ),
  );
  @override
  Future<void> create(Map<String, dynamic> data) async => calls.add('create');
  @override
  Future<void> update(String id, Map<String, dynamic> patch) async =>
      calls.add('update:$id');
  @override
  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    calls.add(name);
    if (offline) throw StateError('unavailable');
    return {};
  }

  @override
  Future<void> close() async {}
}

Future<void> pumpWith(
  WidgetTester tester,
  AppController app,
  Widget home,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appProvider.overrideWith((ref) => app)],
      child: MaterialApp(theme: buildTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// A host route so screens that pop themselves have somewhere to return to.
Widget host(Widget screen) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => screen),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

/// Scrolls the main vertical list end to end so lazily built children are
/// laid out, failing on the first layout exception.
Future<void> expectCleanThroughout(WidgetTester tester, String reason) async {
  expect(tester.takeException(), isNull, reason: reason);
  final vertical = find.byWidgetPredicate(
    (w) =>
        w is Scrollable &&
        axisDirectionToAxis(w.axisDirection) == Axis.vertical,
  );
  if (vertical.evaluate().isEmpty) return;
  final position = tester.state<ScrollableState>(vertical.first).position;
  var guard = 0;
  while (position.pixels < position.maxScrollExtent && guard++ < 80) {
    position.jumpTo(
      math.min(
        position.maxScrollExtent,
        position.pixels + position.viewportDimension * .6,
      ),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: '$reason (scrolled to ${position.pixels.round()})',
    );
  }
  position.jumpTo(0);
  await tester.pump();
  expect(tester.takeException(), isNull, reason: reason);
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  expect(finder, findsWidgets, reason: 'tapVisible missing $finder');
  final element = tester.element(finder.first);
  final scrollable = Scrollable.maybeOf(element);
  if (scrollable != null) {
    await Scrollable.ensureVisible(
      element,
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
  }
  var hittable = finder.hitTestable();
  if (hittable.evaluate().isEmpty) {
    try {
      await tester.scrollUntilVisible(finder.first, 64);
      await tester.pumpAndSettle();
    } catch (_) {}
    hittable = finder.hitTestable();
  }
  expect(hittable, findsWidgets, reason: 'tapVisible not hittable $finder');
  await tester.tap(hittable.first);
  await tester.pumpAndSettle();
}

/// Builds lazy list children and scrolls until [finder] hits the tree.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    try {
      await tester.ensureVisible(finder.first);
    } catch (_) {}
    await tester.pump();
    return;
  }
  final vertical = find.byWidgetPredicate(
    (w) =>
        w is Scrollable &&
        axisDirectionToAxis(w.axisDirection) == Axis.vertical,
  );
  for (var i = 0; i < vertical.evaluate().length; i++) {
    final position = tester.state<ScrollableState>(vertical.at(i)).position;
    var guard = 0;
    position.jumpTo(0);
    await tester.pump();
    while (finder.evaluate().isEmpty &&
        position.pixels < position.maxScrollExtent &&
        guard++ < 80) {
      position.jumpTo(
        math.min(
          position.maxScrollExtent,
          position.pixels + position.viewportDimension * .6,
        ),
      );
      await tester.pump();
    }
    if (finder.evaluate().isNotEmpty) {
      try {
        await tester.ensureVisible(finder.first);
      } catch (_) {}
      await tester.pumpAndSettle();
      return;
    }
  }
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUpAll(tz.initializeTimeZones);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final v in viewports) {
    group(v.name, () {
      testWidgets('welcome, recoverable error, and entry to auth', (
        tester,
      ) async {
        useViewport(tester, v);
        await tester.pumpWidget(
          ShowdUpApp(prefs: await SharedPreferences.getInstance()),
        );
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'welcome');

        var retried = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: WelcomeScreen(
              onPreview: () {},
              onAuthenticated: () async {},
              error: 'You’re offline. Reconnect to sync and verify completion.',
              onRetry: () => retried++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'welcome with error');
        await tapVisible(tester, find.text('Retry'));
        expect(retried, 1);
        await tapVisible(tester, find.byType(FilledButton));
        expect(find.byType(AuthScreen), findsOneWidget);
        await expectCleanThroughout(tester, 'auth from welcome');
        await finish(tester);
      });

      testWidgets('auth: both modes, validation and unconfigured errors', (
        tester,
      ) async {
        useViewport(tester, v);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: AuthScreen(onAuthenticated: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'auth create');
        final submit = find.widgetWithText(FilledButton, 'Create account');
        await tapVisible(tester, submit);
        expect(find.text('Enter your name'), findsOneWidget);
        await expectCleanThroughout(tester, 'auth validation');
        for (final (label, text) in [
          ('Your name', 'Asha'),
          ('Email address', 'asha@example.com'),
          ('Password', 'long enough'),
        ]) {
          final field = find.widgetWithText(TextFormField, label);
          await tester.ensureVisible(field);
          await tester.enterText(field, text);
        }
        await tapVisible(tester, submit);
        expect(find.textContaining('not connected to Firebase'), findsOneWidget);
        await expectCleanThroughout(tester, 'auth error');
        await tapVisible(tester, find.text('Already have an account? Sign in'));
        expect(find.text('Welcome back.'), findsOneWidget);
        await tapVisible(tester, find.text('Forgot password?'));
        expect(
          find.text('Firebase is not configured in this build.'),
          findsOneWidget,
        );
        await expectCleanThroughout(tester, 'auth sign-in');
        await finish(tester);
      });

      testWidgets('home tabs and history filters with mixed data', (
        tester,
      ) async {
        useViewport(tester, v);
        mockAlarmChannel(tester);
        final app = await previewApp(
          commitments: richCommitments(),
          attempts: richAttempts(),
        );
        await pumpWith(tester, app, HomeShell(onLogout: () async {}));
        expect(find.textContaining('LOCAL PREVIEW'), findsOneWidget);
        expect(find.text('SAMPLE PROGRESS'), findsOneWidget);
        await expectCleanThroughout(tester, 'today');
        for (final tab in ['Commitments', 'History', 'Settings', 'Today']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          await expectCleanThroughout(tester, tab);
        }
        await tester.tap(find.text('History').last);
        await tester.pumpAndSettle();
        for (final s in AttemptState.values.where(
          (s) => s != AttemptState.pending,
        )) {
          await tapVisible(
            tester,
            find.widgetWithText(ChoiceChip, stateLabelFor(s)),
          );
          await expectCleanThroughout(tester, 'history ${s.wire}');
        }
        await finish(tester);
      });

      testWidgets('getLaunchAttempt from a reminder opens the attempt', (
        tester,
      ) async {
        useViewport(tester, v);
        final a = attempt('walk', 0, AttemptState.pending);
        mockAlarmChannel(tester, launchAttemptId: a.id);
        final app = await previewApp(commitments: [walk()], attempts: [a]);
        await pumpWith(tester, app, HomeShell(onLogout: () async {}));
        expect(find.byType(AttemptScreen), findsOneWidget);
        expect(find.text('Morning walk'), findsWidgets);
        expect(find.text('Start verification'), findsNothing);
        await expectCleanThroughout(tester, 'launched attempt');
        await finish(tester);
      });

      testWidgets('today: offline empty state and planned state', (
        tester,
      ) async {
        useViewport(tester, v);
        mockAlarmChannel(tester);
        final offline = AppController(
          FakeLiveRepository([], [], offline: true),
        );
        await pumpWith(tester, offline, const Scaffold(body: TodayScreen()));
        expect(find.text('Create a commitment  +'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        await expectCleanThroughout(tester, 'today offline empty');
        await finish(tester);

        final planned = await previewApp(commitments: [walk()], attempts: []);
        await pumpWith(tester, planned, const Scaffold(body: TodayScreen()));
        expect(find.text('You have a plan.'), findsOneWidget);
        await expectCleanThroughout(tester, 'today planned');
        await finish(tester);
      });

      testWidgets('leaving preview returns to welcome', (tester) async {
        useViewport(tester, v);
        mockAlarmChannel(tester);
        await tester.pumpWidget(
          ShowdUpApp(prefs: await SharedPreferences.getInstance()),
        );
        await tester.pumpAndSettle();
        final previewCta =
            find.text('Explore the app · local preview').evaluate().isNotEmpty
            ? find.text('Explore the app · local preview')
            : find.text('Explore local preview');
        await tapVisible(tester, previewCta);
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Leave preview'));
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(find.byType(HomeShell), findsNothing);
        await finish(tester);
      });

      testWidgets('settings when signed in: delete needs a password', (
        tester,
      ) async {
        useViewport(tester, v);
        mockAlarmChannel(tester);
        final repo = FakeLiveRepository(
          [walk()],
          [attempt('walk', 0, AttemptState.pending)],
        );
        var loggedOut = 0;
        await pumpWith(
          tester,
          AppController(repo),
          Scaffold(
            body: SettingsScreen(
              onLogout: () async {
                loggedOut++;
              },
            ),
          ),
        );
        await expectCleanThroughout(tester, 'settings live');
        await tapVisible(tester, find.text('Delete account'));
        expect(find.text('Delete your account?'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'delete dialog');
        await tester.tap(
          find.widgetWithText(TextButton, 'Delete account').last,
        );
        await tester.pumpAndSettle();
        expect(find.text('Enter your password to confirm.'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'delete validation');
        await tester.tap(find.text('Keep account'));
        await tester.pumpAndSettle();
        expect(repo.calls, isNot(contains('deleteAccount')));
        await tapVisible(tester, find.text('Sign out'));
        expect(loggedOut, 1);
        await finish(tester);
      });

      for (final state in AttemptState.values) {
        testWidgets('attempt ${state.wire}', (tester) async {
          useViewport(tester, v);
          final a = attempt('walk', 0, state);
          final app = await previewApp(commitments: [walk()], attempts: [a]);
          await pumpWith(tester, app, AttemptScreen(attemptId: a.id));
          expect(find.text('PREVIEW · NOT A VERIFIED RESULT'), findsOneWidget);
          await expectCleanThroughout(tester, 'attempt ${state.wire}');
          await finish(tester);
        });
      }

      testWidgets('attempt: location failure offers permissions and exit', (
        tester,
      ) async {
        useViewport(tester, v);
        mockAlarmChannel(tester);
        final a = attempt('gym', 0, AttemptState.pending);
        final app = await previewApp(
          commitments: [gym(status: CommitmentStatus.active)],
          attempts: [a],
        );
        app.failures[a.id] =
            'Allow precise location in Android settings, then try again.';
        await pumpWith(tester, app, AttemptScreen(attemptId: a.id));
        expect(find.text('Record as unable to verify'), findsOneWidget);
        await expectCleanThroughout(tester, 'attempt location failure');
        await tapVisible(tester, find.text('Check permissions'));
        expect(find.byType(PermissionsScreen), findsOneWidget);
        await expectCleanThroughout(tester, 'permissions from attempt');
        await finish(tester);
      });

      testWidgets('attempt: window not open yet', (tester) async {
        useViewport(tester, v);
        final a = attempt('walk', 0, AttemptState.pending, future: true);
        final app = await previewApp(commitments: [walk()], attempts: [a]);
        await pumpWith(tester, app, AttemptScreen(attemptId: a.id));
        expect(find.text('Reminders start when your window opens.'), findsOne);
        await expectCleanThroughout(tester, 'attempt not open');
        await finish(tester);
      });

      testWidgets('attempt: preview actions never claim verification', (
        tester,
      ) async {
        useViewport(tester, v);
        final a = attempt('walk', 0, AttemptState.pending);
        final app = await previewApp(commitments: [walk()], attempts: [a]);
        await pumpWith(tester, app, AttemptScreen(attemptId: a.id));
        expect(find.text('Start verification'), findsNothing);
        await tapVisible(tester, find.text('Show sample progress'));
        await expectCleanThroughout(tester, 'attempt sample progress');
        await tapVisible(tester, find.text('Snooze · silence this reminder'));
        expect(find.text('Reminders don’t ring in local preview.'), findsOne);
        await tapVisible(tester, find.text('Preview the completion screen'));
        expect(find.text('Done'), findsOneWidget);
        expect(find.text('PREVIEW · NOT A VERIFIED RESULT'), findsOneWidget);
        await expectCleanThroughout(tester, 'attempt preview completed');
        await finish(tester);
      });

      testWidgets('wizard: steps commitment, every step, then create', (
        tester,
      ) async {
        useViewport(tester, v);
        final app = await previewApp(commitments: [], attempts: []);
        await pumpWith(tester, app, host(const CommitmentWizard()));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'wizard steps: goal');
        await tester.tap(find.textContaining('Continue'));
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'wizard steps: schedule');
        await tapVisible(tester, find.text('06:30'));
        expect(tester.takeException(), isNull, reason: 'time picker');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Continue'));
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'wizard steps: reminders');
        await tapVisible(tester, find.byType(Switch));
        await expectCleanThroughout(tester, 'wizard steps: loud reminders');
        await tester.tap(find.textContaining('Continue'));
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'wizard steps: review');
        await tester.tap(find.text('I’m showing up  →'));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget, reason: 'wizard closes');
        expect(app.commitments.single.title, 'Morning walk');
        await finish(tester);
      });

      testWidgets('wizard: location commitment, validation and save error', (
        tester,
      ) async {
        useViewport(tester, v);
        final app = await previewApp(commitments: [walk()], attempts: []);
        await pumpWith(tester, app, host(const CommitmentWizard()));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Arrive & stay'));
        await expectCleanThroughout(tester, 'wizard location: goal');
        await tester.tap(find.textContaining('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('Invalid latitude.'), findsOneWidget);
        await expectCleanThroughout(tester, 'wizard location: invalid');
        for (final (label, text) in [
          ('Place name', 'Neighbourhood gym'),
          ('Latitude', '12.9716'),
          ('Longitude', '77.5946'),
        ]) {
          final field = find.widgetWithText(TextField, label);
          await tester.ensureVisible(field);
          await tester.enterText(field, text);
        }
        await tester.pumpAndSettle();
        for (final step in ['schedule', 'reminders', 'review']) {
          await tester.tap(find.textContaining('Continue'));
          await tester.pumpAndSettle();
          await expectCleanThroughout(tester, 'wizard location: $step');
        }
        await tester.tap(find.text('I’m showing up  →'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Free includes one active commitment'),
          findsOneWidget,
        );
        await expectCleanThroughout(tester, 'wizard location: save error');
        await finish(tester);
      });

      testWidgets('wizard: edit an existing location commitment', (
        tester,
      ) async {
        useViewport(tester, v);
        final existing = gym(status: CommitmentStatus.active);
        final app = await previewApp(commitments: [existing], attempts: []);
        await pumpWith(tester, app, host(CommitmentWizard(existing: existing)));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Edit commitment'), findsOneWidget);
        await expectCleanThroughout(tester, 'wizard edit: goal');
        for (final step in ['schedule', 'reminders', 'review']) {
          await tester.tap(find.textContaining('Continue'));
          await tester.pumpAndSettle();
          await expectCleanThroughout(tester, 'wizard edit: $step');
        }
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget, reason: 'wizard closes');
        await finish(tester);
      });

      testWidgets('commitments: pause, resume, and confirmed archive', (
        tester,
      ) async {
        useViewport(tester, v);
        final app = await previewApp(commitments: [walk()], attempts: []);
        await pumpWith(tester, app, const Scaffold(body: CommitmentsScreen()));
        await tapVisible(tester, find.text('Pause'));
        expect(find.text('Resume'), findsOneWidget);
        await tapVisible(tester, find.text('Resume'));
        expect(find.text('Pause'), findsOneWidget);
        await tapVisible(tester, find.byTooltip('More actions'));
        await tester.tap(find.text('Archive commitment'));
        await tester.pumpAndSettle();
        expect(find.text('Archive this commitment?'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'archive dialog');
        await tester.tap(find.text('Keep it'));
        await tester.pumpAndSettle();
        expect(app.commitments.single.status, CommitmentStatus.active);
        await tapVisible(tester, find.byTooltip('More actions'));
        await tester.tap(find.text('Archive commitment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        expect(app.commitments.single.status, CommitmentStatus.archived);
        expect(find.textContaining('No commitments yet'), findsOneWidget);
        await expectCleanThroughout(tester, 'commitments archived');
        await finish(tester);
      });

      testWidgets('permissions: loaded status and channel failure', (
        tester,
      ) async {
        useViewport(tester, v);
        mockAlarmChannel(tester);
        await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: const PermissionsScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open settings / allow'), findsWidgets);
        await expectCleanThroughout(tester, 'permissions');
        await tapVisible(tester, find.text('Open settings / allow').first);
        await expectCleanThroughout(tester, 'permissions after request');
        await finish(tester);

        mockAlarmChannel(
          tester,
          handler: (call) async =>
              throw PlatformException(code: 'error', message: 'No service.'),
        );
        await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: const PermissionsScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('No service.'), findsOneWidget);
        await expectCleanThroughout(tester, 'permissions error');
        await finish(tester);
      });

      testWidgets('pro: preview cannot purchase; signed in can', (
        tester,
      ) async {
        useViewport(tester, v);
        final preview = await previewApp(
          commitments: richCommitments(),
          attempts: [],
        );
        await pumpWith(tester, preview, const ProScreen());
        expect(
          find.textContaining('Local preview can’t make purchases'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'View plans & pricing'),
              )
              .onPressed,
          isNull,
        );
        await expectCleanThroughout(tester, 'pro preview');
        await finish(tester);

        mockAlarmChannel(tester);
        final live = AppController(FakeLiveRepository([walk()], []));
        await pumpWith(tester, live, const ProScreen());
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'View plans & pricing'),
              )
              .onPressed,
          isNotNull,
        );
        await expectCleanThroughout(tester, 'pro live');
        await finish(tester);
      });

      testWidgets('privacy', (tester) async {
        useViewport(tester, v);
        await tester.pumpWidget(
          MaterialApp(theme: buildTheme(), home: const PrivacyScreen()),
        );
        await tester.pumpAndSettle();
        await expectCleanThroughout(tester, 'privacy');
        await finish(tester);
      });
    });
  }
}

String stateLabelFor(AttemptState s) => switch (s) {
  AttemptState.pending => 'In progress',
  AttemptState.completed => 'Showed up',
  AttemptState.abandoned => 'Ended for today',
  AttemptState.expired => 'Window ended',
  AttemptState.unverifiable => 'Unable to verify',
};
