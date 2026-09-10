import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:showdup/main.dart';
import 'package:showdup/core/theme.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/models/attempt.dart';
import 'package:showdup/services/controller.dart';
import 'package:showdup/services/repository.dart';
import 'package:showdup/ui/app.dart';
import 'package:showdup/ui/screens.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'welcome enters labeled preview and every navigation destination works',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ShowdUpApp(prefs: await SharedPreferences.getInstance()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Explore the app · local preview'));
      await tester.tap(find.text('Explore the app · local preview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('LOCAL PREVIEW'), findsOneWidget);
      expect(find.text('Morning walk'), findsOneWidget);
      for (final tab in ['Commitments', 'History', 'Settings', 'Today']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  for (final state in AttemptState.values) {
    testWidgets(
      'attempt state ${state.wire} renders honest copy and recovery',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prefs = await SharedPreferences.getInstance();
        final seed = PreviewRepository(prefs);
        final cs = await seed.commitments().first;
        final as = await seed.attempts().first;
        final a = as.first;
        await prefs.setString(
          'previewData',
          jsonEncode({
            'commitments': cs.map((c) => {'id': c.id, ...c.toJson()}).toList(),
            'attempts': [
              {'id': a.id, ...a.toJson(), 'state': state.wire},
            ],
          }),
        );
        await seed.close();
        final controller = AppController(PreviewRepository(prefs));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appProvider.overrideWith((ref) => controller)],
            child: MaterialApp(
              theme: buildTheme(),
              home: AttemptScreen(attemptId: a.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'screen overflow');
        if (state == AttemptState.pending) {
          expect(find.text('End today without completing'), findsOneWidget);
        } else if (state == AttemptState.unverifiable) {
          expect(
            find.textContaining('Your streak is preserved'),
            findsOneWidget,
          );
        } else if (state == AttemptState.completed) {
          expect(find.text('Done'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
  testWidgets('empty commitments and offline recovery render without errors', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'previewData',
      jsonEncode({'commitments': [], 'attempts': []}),
    );
    final c = AppController(PreviewRepository(prefs));
    c.error = 'You’re offline. Reconnect to sync and verify completion.';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: TodayScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create a commitment  +'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'screen overflow');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('preview remains usable on a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ShowdUpApp(prefs: await SharedPreferences.getInstance()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'welcome');
    await tester.ensureVisible(find.text('Explore local preview'));
    await tester.tap(find.text('Explore local preview'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final tab in ['Commitments', 'History', 'Settings', 'Today']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
    }
    await tester.pumpWidget(const SizedBox());
  });
  test('today prioritizes open, upcoming, then latest terminal attempts', () {
    final now = DateTime(2026, 9, 10, 10);
    Attempt attempt(
      String id,
      DateTime start,
      DateTime end,
      AttemptState state,
    ) => Attempt(
      id: id,
      commitmentId: id,
      ownerUid: 'u',
      date: '2026-09-10',
      windowStartAt: start,
      windowEndAt: end,
      state: state,
    );
    final ordered = prioritizedTodayAttempts([
      attempt(
        'older-result',
        now.subtract(const Duration(hours: 3)),
        now.subtract(const Duration(hours: 2)),
        AttemptState.completed,
      ),
      attempt(
        'upcoming',
        now.add(const Duration(hours: 2)),
        now.add(const Duration(hours: 3)),
        AttemptState.pending,
      ),
      attempt(
        'open',
        now.subtract(const Duration(minutes: 10)),
        now.add(const Duration(minutes: 20)),
        AttemptState.pending,
      ),
      attempt(
        'latest-result',
        now.subtract(const Duration(hours: 2)),
        now.subtract(const Duration(hours: 1)),
        AttemptState.abandoned,
      ),
    ], now);
    expect(ordered.map((a) => a.id), [
      'open',
      'upcoming',
      'latest-result',
      'older-result',
    ]);
  });
  test(
    'preview persists edits and ending; free gate remains enforced',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final r = PreviewRepository(prefs), cs = await r.commitments().first;
      final data = cs.first.toJson()
        ..remove('ownerUid')
        ..remove('status');
      await expectLater(r.create(data), throwsStateError);
      await r.update(cs.first.id, {'status': 'paused'});
      await r.create(data);
      final reopened = PreviewRepository(prefs);
      expect(
        (await reopened.commitments().first)
            .where((c) => c.status == CommitmentStatus.active)
            .length,
        1,
      );
      expect(
        (await reopened.attempts().first).first.state,
        AttemptState.abandoned,
      );
      await r.close();
      await reopened.close();
    },
  );
}
