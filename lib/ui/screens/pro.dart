import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/features.dart';
import '../../design/motion.dart';
import '../../design/buttons.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/mark.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../services/billing.dart';
import '../../services/controller.dart';
import '../../services/social_service.dart';
import '../app_provider.dart';
import 'common.dart';

/// Plan page shown when the store paywall is unavailable.
class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key, this.initialMessage});
  final String? initialMessage;

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  bool busy = false;
  late String? message = widget.initialMessage;

  /// The store's own prices once RevenueCat has loaded them.
  String? priceLine;

  @override
  void initState() {
    super.initState();
    Billing.priceLine().then((line) {
      if (mounted && line != null) setState(() => priceLine = line);
    });
  }

  Future<void> run(Future<BillingResult> Function() action) async {
    setState(() => busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      setState(
        () => message = switch (result) {
          BillingResult.purchased => 'Pro is on. Thank you.',
          BillingResult.restored when Billing.isPro => 'Pro is back on.',
          BillingResult.restored =>
            'No Pro purchase found on this Google Play account.',
          BillingResult.cancelled => 'Nothing changed.',
        },
      );
    } catch (e) {
      if (mounted) setState(() => message = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(appProvider).user?.isPro == true;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const PushedHeader(close: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ShowdSpace.gutter,
                  ShowdSpace.s2,
                  ShowdSpace.gutter,
                  ShowdSpace.s6,
                ),
                children: [
                  const Breathe(
                    child: ShowdMark(state: MarkState.showedUp, size: 72),
                  ),
                  const SizedBox(height: ShowdSpace.s6),
                  Text('More room\nto show up.', style: ShowdType.hero),
                  const SizedBox(height: ShowdSpace.s3),
                  AnimatedSwitcher(
                    duration: ShowdMotion.quick,
                    child: Text(
                      priceLine ?? '₹79 a month, or ₹399 a year with 7 days free.',
                      key: ValueKey(priceLine),
                      style: ShowdType.bodyL,
                    ),
                  ),
                  const SizedBox(height: ShowdSpace.s1),
                  Text(
                    'Google Play shows the final price before you pay.',
                    style: ShowdType.caption,
                  ),
                  const SizedBox(height: ShowdSpace.s6),
                  ...staggered([
                    // Only what this build actually delivers: an advertised
                    // perk that is switched off would be a misleading claim.
                    for (final (icon, title) in [
                      (ShowdIcons.alarm, '20 proof alarms'),
                      (ShowdIcons.gym, 'Gym, places, GPS walks'),
                      if (Features.catchEnabled)
                        (ShowdIcons.caught, 'Hold every app'),
                      (ShowdIcons.calendar, 'A time for each day'),
                      (ShowdIcons.history, 'Two years of history'),
                      (ShowdIcons.companion, 'Animal companions'),
                      if (SocialService.instance.available)
                        (ShowdIcons.battle, 'Battles of 10'),
                    ])
                      ShowdRow(
                        leading: ShowdIcon(icon, color: ShowdColors.accent),
                        title: title,
                      ),
                  ], start: const Duration(milliseconds: 200)),
                  const SizedBox(height: ShowdSpace.s4),

                  const SizedBox(height: ShowdSpace.s4),
                  if (message != null) ShowdNotice(message!),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ShowdSpace.gutter,
                0,
                ShowdSpace.gutter,
                ShowdSpace.s3,
              ),
              child: Column(
                children: [
                  ShowdButton(
                    label: isPro ? 'You have Pro' : 'See plans',
                    busy: busy,
                    onPressed: isPro ? null : () => run(Billing.paywall),
                  ),
                  ShowdButton(
                    label: 'Restore purchases',
                    tone: ShowdButtonTone.quiet,
                    onPressed: busy ? null : () => run(Billing.restore),
                  ),
                  Text(
                    'Renews until you cancel in Google Play. Uninstalling doesn’t cancel it.',
                    textAlign: TextAlign.center,
                    style: ShowdType.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
