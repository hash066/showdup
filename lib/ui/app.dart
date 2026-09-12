import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/billing.dart';
import '../services/controller.dart';
import '../services/repository.dart';
import '../platform/alarm_channel.dart';
import '../platform/blocker_channel.dart';
import '../platform/overlay_channel.dart';
import '../services/social_service.dart';
import 'widgets.dart';
import 'screens.dart';
import 'battle_screen.dart';

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
  bool billingListenersAttached = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_initializeBilling());
  }

  Future<void> _initializeBilling() async {
    try {
      await Billing.initialize(widget.prefs);
      await _syncNativeEntitlement();
    } catch (_) {
      // A billing outage must never prevent local reminders or verification.
    }
  }

  Future<void> _startLocal() async {
    if (entering || controller != null) return;
    setState(() => entering = true);
    final repository = LocalRepository(widget.prefs);
    try {
      await _initializeBilling();
      await repository.setPro(Billing.isPro);
      if (!billingListenersAttached) {
        Billing.entitlementRevision.addListener(_syncLocalEntitlement);
        billingListenersAttached = true;
      }
      if (mounted) {
        setState(() {
          controller = AppController(repository);
          entering = false;
        });
        unawaited(SocialService.instance.ensureAnonymous());
        unawaited(SocialService.instance.startWatching());
      } else {
        await repository.close();
      }
    } catch (e) {
      await repository.close();
      if (mounted) {
        setState(() {
          entering = false;
          error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _syncLocalEntitlement() async {
    final repository = controller?.repository;
    if (repository is LocalRepository) {
      await repository.setPro(Billing.isPro);
    }
    await _syncNativeEntitlement();
  }

  Future<void> _syncNativeEntitlement() async {
    try {
      await BlockerChannel.setEntitlement(
        enabled: Billing.isPro,
        expiresAtEpochMs: Billing.proExpiresAtEpochMs.value,
      );
    } on MissingPluginException {
      // Non-Android tests and previews do not provide the blocker channel.
    }
  }

  void preview() {
    setState(() => controller = AppController(PreviewRepository(widget.prefs)));
  }

  Future<void> logout() async {
    final old = controller;
    await old?.shutdown();
    if (mounted) setState(() => controller = null);
  }

  @override
  void dispose() {
    if (billingListenersAttached) {
      Billing.entitlementRevision.removeListener(_syncLocalEntitlement);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller != null) {
      return ProviderScope(
        overrides: [appProvider.overrideWith((ref) => controller!)],
        child: _material(HomeShell(onLogout: logout, prefs: widget.prefs)),
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
        onAuthenticated: _startLocal,
        error: widget.startupError ?? error,
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
  });
  final VoidCallback onPreview;
  final Future<void> Function() onAuthenticated;
  final String? error;
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
                if (error != null) ErrorNotice(error!),
                FilledButton(
                  onPressed: onAuthenticated,
                  child: const Text(
                    'Make my first commitment  →',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: onPreview,
                    child: const Text('Explore the app · local preview'),
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

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.onLogout, required this.prefs});
  final Future<void> Function() onLogout;
  final SharedPreferences prefs;
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int tab = 0;
  bool _checkingLaunchAttempt = false;
  String? _openingAttemptId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeLaunchAttempt());
      unawaited(_consumeInviteLink());
      unawaited(_enablePendingOverlay());
      unawaited(_maybePromptGoogle());
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
      unawaited(_refreshAfterResume());
      unawaited(_consumeLaunchAttempt());
      unawaited(_consumeInviteLink());
      unawaited(_enablePendingOverlay());
      unawaited(_maybePromptGoogle());
    }
  }

  Future<void> _maybePromptGoogle() async {
    if (!mounted || widget.prefs.getBool('social.googlePromptedAt3') == true) {
      return;
    }
    final app = ref.read(appProvider);
    final resolved = app.attempts
        .where((attempt) => attempt.state.isTerminal)
        .length;
    if (resolved < 3 ||
        !SocialService.instance.available ||
        SocialService.instance.googleLinked) {
      return;
    }
    await widget.prefs.setBool('social.googlePromptedAt3', true);
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep your battle identity?'),
        content: const Text(
          'Connect Google to invite friends and keep your weekly rank. Solo commitments stay on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue with Google'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await SocialService.instance.linkGoogle();
      } catch (e) {
        if (mounted) showMessage(context, friendlyError(e));
      }
    }
  }

  Future<void> _refreshAfterResume() async {
    // The RevenueCat cache may have changed while Google Play was foregrounded
    // (renewal, cancellation, or expiry). Its listener updates local and
    // native entitlement state before the visible commitment data refreshes.
    try {
      await Billing.refresh();
    } catch (_) {
      // Never make the local product unusable because a billing refresh is
      // temporarily offline. The last verified subscription expiry still
      // fails closed in Billing/AppBlocker.
    }
    if (mounted) await ref.read(appProvider).refresh();
  }

  Future<void> _consumeLaunchAttempt() async {
    if (_checkingLaunchAttempt) return;
    _checkingLaunchAttempt = true;
    try {
      final attemptId = await AlarmChannel.getLaunchAttempt();
      if (attemptId == null || attemptId.isEmpty) return;

      // Local data may still be loading when Android delivers the intent.
      // Wait briefly for the exact attempt rather than opening a stale route.
      for (var retry = 0; retry != 15 && mounted; retry++) {
        final exists = ref
            .read(appProvider)
            .attempts
            .any((attempt) => attempt.id == attemptId);
        if (exists) {
          if (_openingAttemptId == attemptId) return;
          if (!mounted) return;
          _openingAttemptId = attemptId;
          try {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AttemptScreen(attemptId: attemptId),
              ),
            );
          } finally {
            _openingAttemptId = null;
          }
          return;
        }
        await ref.read(appProvider).refresh();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } on MissingPluginException {
      // Widget tests and non-Android platforms have no alarm channel.
    } on PlatformException {
      // The app remains usable if an older native build lacks this method.
    } finally {
      _checkingLaunchAttempt = false;
    }
  }

  Future<void> _consumeInviteLink() async {
    try {
      final code = await const MethodChannel(
        'app.showdup/social',
      ).invokeMethod<String>('getLaunchInvite');
      if (code != null && code.length == 6 && mounted) {
        SocialService.instance.pendingInviteCode = code.toUpperCase();
        setState(() => tab = 3);
      }
    } on PlatformException catch (_) {
      // Older builds have no social channel.
    } on MissingPluginException catch (_) {
      // Android-only link handoff.
    }
  }

  Future<void> _enablePendingOverlay() async {
    if (widget.prefs.getBool('overlay.pendingEnable') != true) return;
    try {
      final status = await OverlayChannel.status();
      if (!status.permissionGranted) return;
      await OverlayChannel.enable();
      await widget.prefs.setBool('overlay.pendingEnable', false);
    } on PlatformException catch (_) {
      // Leave pending so a later resume can retry safely.
    } on MissingPluginException catch (_) {}
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
                    3 => const BattleScreen(),
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
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'Battle',
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
