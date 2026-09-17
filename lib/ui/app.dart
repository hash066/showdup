import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/features.dart';
import '../design/chrome.dart';
import '../design/icons.dart';
import '../design/layout.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../platform/alarm_channel.dart';
import '../platform/blocker_channel.dart';
import '../platform/overlay_channel.dart';
import '../services/billing.dart';
import '../services/controller.dart';
import '../services/pro_nudge_policy.dart';
import '../services/repository.dart';
import '../services/social_service.dart';
import 'app_provider.dart';
import 'battle_screen.dart';
import 'keys.dart';
import 'onboarding.dart';
import 'screens.dart';

export 'app_provider.dart';
export 'onboarding.dart' show WelcomeScreen;

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
        freeCatch: Features.catchEnabled,
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
    theme: buildShowdTheme(),
    themeMode: ThemeMode.dark,
    home: home,
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
  ProNudgeMoment? _nudge;

  static const _firstAlarmOffered = 'onboarding.firstAlarmOffered.v1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeLaunchAttempt());
      unawaited(_consumeInviteLink());
      unawaited(_enablePendingOverlay());
      unawaited(_maybePromptGoogle());
      unawaited(_maybeShowProMoment());
      unawaited(_offerFirstAlarm());
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
      unawaited(_maybeShowProMoment());
    }
  }

  bool get _battleTab => SocialService.instance.available;

  List<ShowdNavItem> get _tabs => [
    const ShowdNavItem(
      key: ShowdKeys.navAlarms,
      icon: ShowdIcons.alarm,
      label: 'Alarms',
    ),
    const ShowdNavItem(
      key: ShowdKeys.navCommitments,
      icon: ShowdIcons.calendar,
      label: 'Commitments',
    ),
    const ShowdNavItem(
      key: ShowdKeys.navHistory,
      icon: ShowdIcons.history,
      label: 'History',
    ),
    if (_battleTab)
      const ShowdNavItem(
        key: ShowdKeys.navBattle,
        icon: ShowdIcons.battle,
        label: 'Battle',
      ),
  ];

  /// Straight into setup the first time someone arrives with no alarm.
  Future<void> _offerFirstAlarm() async {
    final app = ref.read(appProvider);
    if (app.preview || widget.prefs.getBool(_firstAlarmOffered) == true) {
      return;
    }
    await widget.prefs.setBool(_firstAlarmOffered, true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || ref.read(appProvider).commitments.isNotEmpty) return;
    openWizard(context);
  }

  /// Upgrade moments show as a quiet card on Alarms, at most every 48 hours.
  Future<void> _maybeShowProMoment() async {
    if (!mounted || _nudge != null) return;
    final app = ref.read(appProvider);
    if (app.preview || app.loading || app.user?.isPro == true) return;
    final moment = ProNudgePolicy.next(
      app.attempts,
      isPro: false,
      reaches: app.attempts.fold(0, (sum, a) => sum + app.reachesFor(a.id)),
    );
    if (moment == null ||
        widget.prefs.getBool('pro.nudge.${moment.key}') == true) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = widget.prefs.getInt('pro.nudge.lastShownAt') ?? 0;
    if (now - last < const Duration(hours: 48).inMilliseconds) return;
    await widget.prefs.setBool('pro.nudge.${moment.key}', true);
    await widget.prefs.setInt('pro.nudge.lastShownAt', now);
    if (mounted) setState(() => _nudge = moment);
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
        title: const Text('Keep your battle name?'),
        content: const Text(
          'Connect Google to invite friends and keep your weekly rank. Your alarms stay on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Connect Google'),
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
      if (code != null && code.length == 6 && mounted && _battleTab) {
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

  void _openSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (settingsContext) => SettingsScreen(
        onLogout: widget.onLogout,
        onWhyThisWorks: () => Navigator.push(
          settingsContext,
          MaterialPageRoute<void>(
            builder: (whyContext) => WhyThisWorksScreen(
              onContinue: () async => Navigator.pop(whyContext),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final tabs = _tabs;
    final index = tab.clamp(0, tabs.length - 1);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                if (app.preview)
                  Container(
                    key: ShowdKeys.previewBanner,
                    width: double.infinity,
                    color: ShowdColors.carbon,
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShowdSpace.gutter,
                      vertical: 8,
                    ),
                    child: Text(
                      'Preview · sample data',
                      textAlign: TextAlign.center,
                      style: ShowdType.caption.copyWith(
                        color: ShowdColors.accent,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ShowdSpace.gutter,
                    ShowdSpace.s2,
                    4,
                    0,
                  ),
                  child: ScreenHeader(
                    leading: const Wordmark(size: 22),
                    trailing: ShowdIconButton(
                      key: ShowdKeys.navSettings,
                      icon: ShowdIcons.settings,
                      semanticLabel: 'Settings',
                      onPressed: _openSettings,
                    ),
                  ),
                ),
                Expanded(
                  child: switch (tabs[index].key) {
                    ShowdKeys.navAlarms => AlarmsScreen(
                      nudge: _nudge,
                      onNudgeDismiss: () => setState(() => _nudge = null),
                      onNudgeOpen: () {
                        setState(() => _nudge = null);
                        openPro(context);
                      },
                    ),
                    ShowdKeys.navCommitments => const CommitmentsScreen(),
                    ShowdKeys.navHistory => const HistoryScreen(),
                    _ => const BattleScreen(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: ShowdNavBar(
        items: tabs,
        index: index,
        onSelect: (value) => setState(() => tab = value),
      ),
    );
  }
}
