import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'core/config.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    } catch (e) {
      startupError = e.toString();
    }
  }
  if (AppConfig.oneSignalId.isNotEmpty) {
    OneSignal.initialize(AppConfig.oneSignalId);
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      child: ShowdUpApp(prefs: prefs, startupError: startupError),
    ),
  );
}

class ShowdUpApp extends StatelessWidget {
  const ShowdUpApp({super.key, required this.prefs, this.startupError});
  final SharedPreferences prefs;
  final String? startupError;
  @override
  Widget build(BuildContext context) =>
      AppEntry(prefs: prefs, startupError: startupError);
}
