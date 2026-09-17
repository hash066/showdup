// Renders every main screen with the real brand fonts into tool/capture/out/.
//
//   flutter test --update-goldens tool/capture/screens_test.dart
//
// Used for design review and as the starting point for store screenshots.
// Output is ignored by git.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showdup/design/theme.dart';
import 'package:showdup/models/enums.dart';
import 'package:showdup/services/controller.dart';
import 'package:showdup/services/repository.dart';
import 'package:showdup/ui/app.dart';
import 'package:showdup/ui/battle_screen.dart';
import 'package:showdup/ui/onboarding.dart';
import 'package:showdup/ui/screens.dart';
import 'package:showdup/ui/wizard.dart';
import 'package:showdup/ui/keys.dart';
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
  // Material widgets (chips, sliders, dialogs) default to Roboto.
  await (FontLoader(
    'Roboto',
  )..addFont(font('BricolageGrotesque-Medium.ttf'))).load();
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await _loadFonts();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget home, {
    AppController? controller,
    Future<void> Function()? before,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildShowdTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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
      matchesGoldenFile('out/$name.png'),
    );
    expect(tester.takeException(), isNull, reason: name);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Future<AppController> preview({String? state}) async {
    final prefs = await SharedPreferences.getInstance();
    if (state != null) {
      final seed = PreviewRepository(prefs);
      final cs = await seed.commitments().first;
      final as = await seed.attempts().first;
      await prefs.setString(
        'previewData',
        jsonEncode({
          'commitments': cs.map((c) => {'id': c.id, ...c.toJson()}).toList(),
          'attempts': [
            for (final (i, a) in as.indexed)
              {'id': a.id, ...a.toJson(), if (i == 0) 'state': state},
          ],
        }),
      );
      await seed.close();
    }
    return AppController(PreviewRepository(prefs));
  }

  Future<String> firstAttemptId() async {
    final repository = PreviewRepository(await SharedPreferences.getInstance());
    final id = (await repository.attempts().first).first.id;
    await repository.close();
    return id;
  }

  testWidgets('welcome', (t) async {
    await shoot(
      t,
      '01-welcome',
      WelcomeScreen(onPreview: () {}, onAuthenticated: () async {}),
    );
  });

  for (var page = 0; page < 4; page++) {
    testWidgets('story $page', (t) async {
      await shoot(
        t,
        '02-story-$page',
        StoryScreen(onDone: () async {}),
        before: () async {
          for (var i = 0; i < page; i++) {
            await t.tap(find.text('Next'));
            await t.pumpAndSettle();
          }
        },
      );
    });
  }

  testWidgets('why this works', (t) async {
    await shoot(t, '02-why', WhyThisWorksScreen(onContinue: () async {}));
  });

  for (final (name, tabKey) in [
    ('03-alarms', ShowdKeys.navAlarms),
    ('04-commitments', ShowdKeys.navCommitments),
    ('05-history', ShowdKeys.navHistory),
  ]) {
    testWidgets(name, (t) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = await preview();
      await shoot(
        t,
        name,
        HomeShell(onLogout: () async {}, prefs: prefs),
        controller: controller,
        before: () => t.tap(find.byKey(tabKey)),
      );
    });
  }

  testWidgets('alarms large text', (t) async {
    final prefs = await SharedPreferences.getInstance();
    await shoot(
      t,
      '03b-alarms-2x',
      HomeShell(onLogout: () async {}, prefs: prefs),
      controller: await preview(),
      textScale: 2,
    );
  });

  testWidgets('settings', (t) async {
    await shoot(
      t,
      '06-settings',
      SettingsScreen(onLogout: () async {}, onWhyThisWorks: () {}),
      controller: await preview(),
    );
  });

  testWidgets('companion sheet', (t) async {
    final controller = await preview();
    await shoot(
      t,
      '07-companions',
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showCompanionSheet(context, controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      controller: controller,
      before: () => t.tap(find.text('open')),
    );
  });

  for (final (name, state) in [
    ('08-proof', null),
    ('09-released', AttemptState.completed.wire),
    ('10-missed', AttemptState.expired.wire),
  ]) {
    testWidgets(name, (t) async {
      final controller = await preview(state: state);
      await shoot(
        t,
        name,
        AttemptScreen(attemptId: await firstAttemptId()),
        controller: controller,
        before: () async {},
      );
    });
  }

  for (var step = 0; step < 4; step++) {
    testWidgets('wizard $step', (t) async {
      await shoot(
        t,
        '11-wizard-$step',
        const CommitmentWizard(),
        controller: await preview(),
        before: () async {
          for (var i = 0; i < step; i++) {
            await t.ensureVisible(find.byKey(ShowdKeys.wizardNext));
            await t.tap(find.byKey(ShowdKeys.wizardNext));
            await t.pumpAndSettle();
          }
        },
      );
    });
  }

  testWidgets('pro', (t) async {
    await shoot(t, '12-pro', const ProScreen(), controller: await preview());
  });

  testWidgets('battle', (t) async {
    await shoot(
      t,
      '13-battle',
      const Scaffold(body: SafeArea(child: BattleScreen())),
      controller: await preview(),
    );
  });
}
