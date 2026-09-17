import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/config.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  tz.initializeTimeZones();
  String? startupError;
  if (AppConfig.configured) {
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.apiKey,
          appId: AppConfig.appId,
          messagingSenderId: AppConfig.senderId,
          projectId: AppConfig.projectId,
        ),
      );
      if (AppConfig.useEmulators) {
        await FirebaseAuth.instance.useAuthEmulator(
          AppConfig.emulatorHost,
          9099,
        );
        FirebaseFirestore.instance.useFirestoreEmulator(
          AppConfig.emulatorHost,
          8080,
        );
        FirebaseFunctions.instance.useFunctionsEmulator(
          AppConfig.emulatorHost,
          5001,
        );
      }
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode || AppConfig.useEmulators
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (_) {
      startupError =
          'Optional Firebase backup is unavailable. On-device commitments, reminders, and verification still work.';
    }
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      child: ShowdUpApp(prefs: prefs, startupError: startupError),
    ),
  );
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (package, file) in const [
      ('Big Shoulders', 'OFL-BigShouldersDisplay.txt'),
      ('Bricolage Grotesque', 'OFL-BricolageGrotesque.txt'),
    ]) {
      final text = await rootBundle.loadString('assets/licenses/$file');
      yield LicenseEntryWithLineBreaks([package], text);
    }
  });
}

class ShowdUpApp extends StatelessWidget {
  const ShowdUpApp({super.key, required this.prefs, this.startupError});
  final SharedPreferences prefs;
  final String? startupError;
  @override
  Widget build(BuildContext context) =>
      AppEntry(prefs: prefs, startupError: startupError);
}
