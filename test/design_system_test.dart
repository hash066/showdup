import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showdup/design/buttons.dart';
import 'package:showdup/design/companion.dart';
import 'package:showdup/design/icons.dart';
import 'package:showdup/design/layout.dart';
import 'package:showdup/design/mark.dart';
import 'package:showdup/design/svg_path.dart';
import 'package:showdup/design/theme.dart';
import 'package:showdup/design/tokens.dart';
import 'package:showdup/models/pet.dart';

void main() {
  group('tokens', () {
    test('text pairs meet WCAG AA', () {
      expect(contrastRatio(ShowdColors.paper, ShowdColors.ink), greaterThan(7));
      expect(
        contrastRatio(ShowdColors.accent, ShowdColors.ink),
        greaterThan(7),
      );
      expect(
        contrastRatio(ShowdColors.stone, ShowdColors.ink),
        greaterThan(4.5),
      );
      expect(
        contrastRatio(ShowdColors.stone, ShowdColors.carbon),
        greaterThan(4.5),
      );
      expect(
        contrastRatio(ShowdColors.alert, ShowdColors.ink),
        greaterThan(4.5),
      );
    });

    test('contrast is symmetric and bounded', () {
      final forward = contrastRatio(ShowdColors.paper, ShowdColors.ink);
      expect(contrastRatio(ShowdColors.ink, ShowdColors.paper), forward);
      expect(contrastRatio(ShowdColors.ink, ShowdColors.ink), closeTo(1, 1e-9));
    });
  });

  group('svgPath', () {
    test('absolute and relative commands produce the same bounds', () {
      final abs = svgPath('M2 2L10 2L10 10Z').getBounds();
      final rel = svgPath('m2 2l8 0 0 8z').getBounds();
      expect(rel, abs);
      expect(abs, const Rect.fromLTRB(2, 2, 10, 10));
    });

    test('H, V, arcs and curves stay inside the expected box', () {
      final bounds = svgPath('M28 46V56a20 20 0 0 0 40 0V46').getBounds();
      expect(bounds.left, closeTo(28, .01));
      expect(bounds.right, closeTo(68, .01));
      expect(bounds.bottom, closeTo(76, .5));
      expect(svgPath(circlePath(12, 12, 8)).getBounds().width, closeTo(16, .5));
      expect(
        svgPath(rectPath(4, 4, 6, 6, 1)).getBounds().width,
        closeTo(6, .01),
      );
    });

    test('every icon parses to a non-empty path', () {
      for (final icon in ShowdIcons.values) {
        for (final data in icon.allPaths) {
          final bounds = svgPath(data).getBounds();
          expect(
            bounds.width + bounds.height,
            greaterThan(0),
            reason: icon.name,
          );
        }
      }
    });
  });

  test('dot is the free default and animals are Pro', () {
    expect(MascotId.fromWire(null), MascotId.dot);
    expect(MascotId.fromWire('unknown'), MascotId.dot);
    expect(MascotId.dot.isPremium, isFalse);
    expect(
      MascotId.values.where((m) => m != MascotId.dot).every((m) => m.isPremium),
      isTrue,
    );
  });

  testWidgets('components render without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pressed = 0;
    var held = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShowdTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (final state in MarkState.values)
                  ShowdMark(state: state, size: 40),
                const FlippingMark(showedUp: true, size: 80),
                for (final mascot in MascotId.values)
                  for (final mood in CompanionMood.values)
                    CompanionView(mascot: mascot, mood: mood, size: 40),
                Wrap(
                  children: [
                    for (final icon in ShowdIcons.values) ShowdIcon(icon),
                  ],
                ),
                ShowdButton(label: 'Save alarm', onPressed: () => pressed++),
                const ShowdButton(label: 'Disabled', onPressed: null),
                ShowdButton(
                  label: 'Outline',
                  icon: ShowdIcons.add,
                  tone: ShowdButtonTone.outline,
                  onPressed: () {},
                ),
                HoldToConfirmButton(
                  label: 'Hold to end today',
                  onConfirmed: () => held++,
                ),
                const BigNumber('06:30'),
                const ProofBar(progress: .6),
                ShowdRow(
                  title: 'Row',
                  subtitle: 'Sub',
                  trailing: const ProPill(),
                  onTap: () {},
                ),
                ChoiceRow(
                  title: 'Gym',
                  subtitle: 'Arrive',
                  pro: true,
                  selected: true,
                  onTap: () {},
                ),
                DayPicker(selected: const {1, 3, 5}, onToggle: (_) {}),
                const ShowdNotice('Something to know'),
                const LetterAvatar('Instagram'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Save alarm'));
    expect(pressed, 1);

    final hold = find.text('Hold to end today');
    await tester.ensureVisible(hold);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(hold));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Keep holding…'), findsOneWidget);
    expect(held, 0);
    await tester.pump(ShowdMotion.hold);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(held, 1);
  });
}
