import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../platform/alarm_channel.dart';
import '../services/billing.dart';
import '../services/controller.dart';
import '../services/repository.dart';
import 'widgets.dart';
import 'screens.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw StateError('App session not initialized'),
);

class AppEntry extends StatefulWidget {
  const AppEntry({super.key, required this.prefs, this.startupError});
  final SharedPreferences prefs;
  final String? startupError;
  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  AppController? controller;
  bool entering = false;
  String? error;
  OnPushSubscriptionChangeObserver? _pushObserver;
  @override
  void initState() {
    super.initState();
    if (AppConfig.configured &&
        widget.startupError == null &&
        FirebaseAuth.instance.currentUser != null) {
      entering = true;
      _live();
    }
  }

  Future<void> _live() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      // A billing outage must never prevent free verification or signing in.
      try {
        await Billing.identify(user.uid);
      } catch (_) {}
      await const MethodChannel(
        'app.showdup/alarm',
      ).invokeMethod('configureBackend', {
        'apiKey': AppConfig.apiKey,
        'appId': AppConfig.appId,
        'projectId': AppConfig.projectId,
        'senderId': AppConfig.senderId,
        'emulators': AppConfig.useEmulators,
        'host': AppConfig.emulatorHost,
      });
      final doc = FirebaseFirestore.instance.doc('users/${user.uid}');
      final snap = await doc.get();
      if (!snap.exists) {
        String zone = 'Asia/Kolkata';
        try {
          zone = (await FlutterTimezone.getLocalTimezone()).identifier;
        } catch (_) {}
        await doc.set({
          'displayName': user.displayName ?? '',
          'timezone': zone,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (AppConfig.oneSignalId.isNotEmpty) {
        unawaited(OneSignal.Notifications.requestPermission(true));
        if (_pushObserver != null) {
          OneSignal.User.pushSubscription.removeObserver(_pushObserver!);
        }
        _pushObserver = (state) {
          final id = state.current.id;
          if (id != null) {
            // Best effort: a failed push-id sync must not surface as an
            // uncaught error; the observer fires again on the next change.
            unawaited(
              doc
                  .set({'oneSignalId': id}, SetOptions(merge: true))
                  .catchError((Object _) {}),
            );
          }
        };
        OneSignal.User.pushSubscription.addObserver(_pushObserver!);
      }
      if (mounted) {
        setState(() {
          controller = AppController(FirebaseRepository(user.uid));
          entering = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          entering = false;
          error = friendlyError(e);
        });
      }
    }
  }

  void preview() {
    setState(() {
      error = null;
      controller = AppController(PreviewRepository(widget.prefs));
    });
  }

  /// Retries entering the signed-in session after a startup failure (for
  /// example, first launch while offline) without forcing a new sign-in.
  void retry() {
    if (!AppConfig.configured || FirebaseAuth.instance.currentUser == null) {
      setState(() => error = null);
      return;
    }
    setState(() {
      error = null;
      entering = true;
    });
    _live();
  }

  bool _leaving = false;
  Future<void> logout() async {
    if (_leaving) return;
    _leaving = true;
    final old = controller;
    if (_pushObserver != null) {
      OneSignal.User.pushSubscription.removeObserver(_pushObserver!);
      _pushObserver = null;
    }
    // Leave the session immediately so sign-out never waits on native
    // teardown; HomeShell would otherwise stay on screen until shutdown
    // finishes, which widget tests treat as idle.
    if (mounted) {
      setState(() {
        error = null;
        controller = null;
      });
    }
    try {
      await old?.shutdown();
    } finally {
      try {
        await Billing.logout();
      } catch (_) {}
      _leaving = false;
    }
  }

  @override
  void dispose() {
    if (_pushObserver != null) {
      OneSignal.User.pushSubscription.removeObserver(_pushObserver!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ProviderScope(
        overrides: [appProvider.overrideWith((ref) => controller!)],
        child: _material(HomeShell(onLogout: logout)),
      );
    }
    if (entering) {
      return _material(
        const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return _material(
      WelcomeScreen(
        onPreview: preview,
        onAuthenticated: _live,
        error: widget.startupError ?? error,
        onRetry: widget.startupError == null && error != null ? retry : null,
      ),
    );
  }

  Widget _material(Widget home) => MaterialApp(
    title: 'ShowdUp',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: home,
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onPreview,
    required this.onAuthenticated,
    this.error,
    this.onRetry,
  });
  final VoidCallback onPreview;
  final Future<void> Function() onAuthenticated;
  final String? error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Brand(),
                const SizedBox(height: 36),
                const Eyebrow(
                  'Less negotiating. More living.',
                  color: T.accent,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Keep the promise\nyou made to\nyourself.',
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                    letterSpacing: -2.4,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Set your commitment. Choose what counts as done. Your phone follows through.',
                  style: TextStyle(color: T.muted, fontSize: 16, height: 1.6),
                ),
                const SizedBox(height: 26),
                const Center(
                  child: ProgressOrbit(
                    progress: .72,
                    value: '1,000',
                    label: 'SMALL STEPS. REAL CHANGE.',
                    size: 210,
                  ),
                ),
                const SizedBox(height: 26),
                const Panel(
                  padding: 18,
                  child: Row(
                    children: [
                      Icon(Icons.wb_sunny_outlined, color: T.accent),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Your morning scroll starts after\nyour morning walk.',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (error != null) ErrorNotice(error!, onRetry: onRetry),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AuthScreen(onAuthenticated: onAuthenticated),
                    ),
                  ),
                  child: Text(
                    MediaQuery.textScalerOf(context).scale(16) > 22
                        ? 'Get started'
                        : 'Make my first commitment  →',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: onPreview,
                    child: Text(
                      MediaQuery.textScalerOf(context).scale(16) > 22
                          ? 'Explore local preview'
                          : 'Explore the app · local preview',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Snooze buys time. Only evidence completes it.',
                    style: TextStyle(color: T.muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});
  final Future<void> Function() onAuthenticated;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  final form = GlobalKey<FormState>();
  bool signingIn = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    if (!AppConfig.configured) {
      setState(
        () => error =
            'This build is not connected to Firebase yet. You can explore every screen using local preview from the welcome screen.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (signingIn) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        final c = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
        await c.user!.updateDisplayName(name.text.trim());
      }
      await widget.onAuthenticated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (busy) return;
    if (!AppConfig.configured) {
      setState(() => error = 'Firebase is not configured in this build.');
      return;
    }
    final address = email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
      setState(() => error = 'Enter your email address to reset your password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: address);
      if (mounted) {
        showMessage(
          context,
          'If an account exists, a reset email is on its way.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            const Brand(),
            const SizedBox(height: 36),
            Text(
              signingIn ? 'Welcome back.' : 'A fresh start.',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your commitments, safely synced across devices.',
              style: TextStyle(color: T.muted),
            ),
            const SizedBox(height: 28),
            Form(
              key: form,
              child: Column(
                children: [
                  if (!signingIn) ...[
                    TextFormField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    validator: (v) =>
                        !RegExp(
                          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                        ).hasMatch(v!.trim())
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) =>
                        v!.length < 8 ? 'Use at least 8 characters' : null,
                    onFieldSubmitted: (_) => submit(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (error != null)
              ErrorNotice(error!, onRetry: busy ? null : () => submit()),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                busy
                    ? 'Connecting…'
                    : signingIn
                    ? 'Sign in'
                    : 'Create account',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      signingIn = !signingIn;
                      error = null;
                    }),
              child: Text(
                signingIn
                    ? 'New here? Create an account'
                    : 'Already have an account? Sign in',
              ),
            ),
            if (signingIn)
              TextButton(
                onPressed: busy ? null : resetPassword,
                child: const Text('Forgot password?'),
              ),
            const SizedBox(height: 22),
            const Text(
              'You choose the volume, timing, and finish line. You can always end today without completing.',
              style: TextStyle(color: T.muted, fontSize: 13, height: 1.6),
            ),
          ],
          ),
        ),
      ),
    ),
  );
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.onLogout});
  final Future<void> Function() onLogout;
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int tab = 0;
  String? _handledLaunch;
  bool _launching = false;
  bool _attemptOpen = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeLaunch());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appProvider).refresh();
      unawaited(_consumeLaunch());
    }
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final uri = routeInformation.uri;
    final ours = uri.scheme == 'showdup';
    if (ours && mounted) setState(() => tab = 0);
    unawaited(_consumeLaunch(fromNewIntent: ours));
    return ours
        ? Future.value(true)
        : super.didPushRouteInformation(routeInformation);
  }

  @override
  @Deprecated('Use didPushRouteInformation instead')
  Future<bool> didPushRoute(String route) {
    final ours = route.contains('showdup');
    if (ours && mounted) setState(() => tab = 0);
    unawaited(_consumeLaunch(fromNewIntent: ours));
    return ours ? Future.value(true) : super.didPushRoute(route);
  }

  /// Opens Today, then the attempt named by the native launch extra / URI.
  /// The same id is ignored on a later resume so recents do not re-push;
  /// a fresh VIEW intent (`fromNewIntent`) may open it again.
  Future<void> _consumeLaunch({bool fromNewIntent = false}) async {
    if (!mounted || _launching) return;
    _launching = true;
    try {
      final id = await AlarmChannel.getLaunchAttempt();
      if (!mounted) return;
      if (id == null || id.isEmpty) {
        if (fromNewIntent) setState(() => tab = 0);
        return;
      }
      if (id == _handledLaunch && (_attemptOpen || !fromNewIntent)) return;
      _handledLaunch = id;
      setState(() => tab = 0);
      _attemptOpen = true;
      unawaited(
        Navigator.of(context)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => AttemptScreen(attemptId: id),
              ),
            )
            .whenComplete(() => _attemptOpen = false),
      );
    } catch (_) {
      _attemptOpen = false;
    } finally {
      _launching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                if (app.preview)
                  Container(
                    width: double.infinity,
                    color: T.accent.withValues(alpha: .12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: const Text(
                      'LOCAL PREVIEW  ·  Sample data, no live verification',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: T.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                Expanded(
                  child: switch (tab) {
                    0 => const TodayScreen(),
                    1 => const CommitmentsScreen(),
                    2 => const HistoryScreen(),
                    _ => SettingsScreen(onLogout: widget.onLogout),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny_rounded),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag_rounded),
            label: 'Commitments',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
