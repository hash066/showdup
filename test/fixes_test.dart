import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showdup/design/chrome.dart';
import 'package:showdup/design/theme.dart';
import 'package:showdup/services/controller.dart';
import 'package:showdup/services/social_service.dart';

void main() {
  group('friendly errors', () {
    test('a native message is shown as written, not read as offline', () {
      expect(
        friendlyError(
          PlatformException(
            code: 'unavailable',
            message: 'No location fix. Try outdoors.',
          ),
        ),
        'No location fix. Try outdoors.',
      );
      expect(
        friendlyError(PlatformException(code: 'x')),
        'Something went wrong. Try again.',
      );
    });

    test('a switched-off Firebase sign-in never reaches the screen', () {
      expect(
        friendlyError(
          Exception(
            '[firebase_auth/operation-not-allowed] This operation is not allowed. [ The identity provider configuration is not found. ]',
          ),
        ),
        'Battles aren’t available right now.',
      );
    });

    test('battles stay off unless the build switches them on', () {
      expect(SocialService.instance.available, isFalse);
    });
  });

  group('typing a number', () {
    Future<double?> open(WidgetTester tester, String typed) async {
      double? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildShowdTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showNumberEntry(
                  context,
                  title: 'How many steps?',
                  value: 3000,
                  min: 500,
                  max: 15000,
                  unit: 'steps',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('an exact number inside the range is returned', (tester) async {
      expect(await open(tester, '12345'), 12345);
    });

    testWidgets('a number outside the range cannot be saved', (tester) async {
      expect(await open(tester, '99999'), isNull);
      expect(find.text('Between 500–15000'), findsOneWidget);
    });
  });
}
