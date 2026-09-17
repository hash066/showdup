import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/features.dart';
import '../../design/sensory.dart';
import '../../design/motion.dart';
import '../../design/buttons.dart';
import '../../design/chrome.dart';
import '../../design/companion.dart';
import '../../design/gallery.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../models/pet.dart';
import '../../platform/overlay_channel.dart';
import '../../services/controller.dart';
import '../../services/social_service.dart';
import '../app_provider.dart';
import 'common.dart';
import 'permissions.dart';

const _subscriptionsUrl =
    'https://play.google.com/store/account/subscriptions?package=com.rayyanshaikh.orbit';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({
    super.key,
    required this.onLogout,
    required this.onWhyThisWorks,
  });

  final Future<void> Function() onLogout;
  final VoidCallback onWhyThisWorks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final pet = app.petSnapshot;
    final isPro = app.user?.isPro == true;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const PushedHeader(title: 'Settings'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  ShowdSpace.gutter,
                  ShowdSpace.s4,
                  ShowdSpace.gutter,
                  ShowdSpace.s8,
                ),
                children: [
                  Row(
                    children: [
                      Breathe(
                        child: CompanionView(
                          mascot: pet.mascot,
                          mood: companionMoodFor(pet.mood),
                          size: 64,
                        ),
                      ),
                      const SizedBox(width: ShowdSpace.s4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.preview
                                  ? 'Local preview'
                                  : isPro
                                  ? 'ShowdUp Pro'
                                  : 'ShowdUp Free',
                              style: ShowdType.titleM,
                            ),
                            Text(
                              app.preview
                                  ? 'Sample data'
                                  : isPro
                                  ? 'Thank you'
                                  : '1 alarm · 1 app',
                              style: ShowdType.bodyM,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ShowdSpace.s6),
                  const _FeelSection(),
                  const SizedBox(height: ShowdSpace.s4),
                  ShowdRow(
                    leading: const ShowdIcon(ShowdIcons.shield),
                    title: isPro ? 'Manage subscription' : 'ShowdUp Pro',
                    trailing: isPro ? null : const ProPill(),
                    onTap: () => isPro
                        ? launchUrl(
                            Uri.parse(_subscriptionsUrl),
                            mode: LaunchMode.externalApplication,
                          )
                        : openPro(context),
                  ),
                  ShowdRow(
                    leading: const ShowdIcon(ShowdIcons.companion),
                    title: 'Companion',
                    onTap: () => showCompanionSheet(context, app),
                  ),
                  if (Features.overlay && !app.preview)
                    ShowdRow(
                      leading: const ShowdIcon(ShowdIcons.focus),
                      title: 'Companion bubble',
                      onTap: () => _toggleOverlay(context),
                    ),
                  ShowdRow(
                    leading: const ShowdIcon(ShowdIcons.bell),
                    title: 'Permissions',
                    onTap: () => Navigator.push(
                      context,
                      ShowdRoute<void>(
                        builder: (_) => const PermissionsScreen(),
                      ),
                    ),
                  ),
                  ShowdRow(
                    leading: const ShowdIcon(ShowdIcons.lock),
                    title: 'Privacy & proof',
                    onTap: () => Navigator.push(
                      context,
                      ShowdRoute<void>(builder: (_) => const PrivacyScreen()),
                    ),
                  ),
                  ShowdRow(
                    leading: const ShowdIcon(ShowdIcons.info),
                    title: 'Why this works',
                    onTap: onWhyThisWorks,
                  ),
                  ShowdRow(
                    leading: const ShowdIcon(ShowdIcons.history),
                    title: 'Open-source licenses',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'ShowdUp',
                      applicationVersion: '1.0.0',
                    ),
                  ),
                  if (kDebugMode)
                    ShowdRow(
                      leading: const ShowdIcon(ShowdIcons.edit),
                      title: 'Design gallery',
                      onTap: () => Navigator.push(
                        context,
                        ShowdRoute<void>(builder: (_) => const DesignGallery()),
                      ),
                    ),
                  const SizedBox(height: ShowdSpace.s8),
                  if (app.preview)
                    ShowdButton(
                      label: 'Leave preview',
                      tone: ShowdButtonTone.outline,
                      onPressed: onLogout,
                    )
                  else
                    ShowdRow(
                      title: 'Delete data on this phone',
                      danger: true,
                      onTap: () => _delete(context, app),
                    ),
                  const SizedBox(height: ShowdSpace.s6),
                  Center(
                    child: Text('ShowdUp 1.0.0', style: ShowdType.caption),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleOverlay(BuildContext context) async {
    try {
      final status = await OverlayChannel.status();
      if (!status.permissionGranted) {
        await OverlayChannel.requestPermission();
        return;
      }
      if (status.enabled) {
        await OverlayChannel.disable();
      } else {
        await OverlayChannel.enable();
      }
      if (context.mounted) {
        showMessage(
          context,
          status.enabled ? 'Companion bubble off.' : 'Companion bubble on.',
        );
      }
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _delete(BuildContext context, AppController app) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete data on this phone?'),
        content: const Text(
          'Your alarms and history are erased for good. A Google Play subscription keeps billing until you cancel it in Google Play.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ShowdColors.alert),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await SocialService.instance.deleteAccount();
      await app.repository.call('deleteAccount', {});
      await onLogout();
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e));
    }
  }
}

/// The dot is free. Animals unlock with Pro.
Future<void> showCompanionSheet(BuildContext context, AppController app) =>
    showShowdSheet<void>(
      context,
      builder: (sheetContext) {
        final isPro = app.user?.isPro == true;
        final current = app.petSnapshot.mascot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick a companion', style: ShowdType.titleL),
            const SizedBox(height: ShowdSpace.s1),
            Text(
              'It cheers when you show up and never sulks when you don’t.',
              style: ShowdType.bodyM,
            ),
            const SizedBox(height: ShowdSpace.s6),
            LayoutBuilder(
              builder: (context, constraints) {
                final tile = (constraints.maxWidth - ShowdSpace.s3 * 2) / 3;
                return Wrap(
                  spacing: ShowdSpace.s3,
                  runSpacing: ShowdSpace.s3,
                  children: [
                    for (final mascot in MascotId.values)
                      _CompanionTile(
                        mascot: mascot,
                        size: tile,
                        selected: mascot == current,
                        locked: mascot.isPremium && !isPro,
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          if (mascot.isPremium && !isPro) {
                            await openPro(context);
                            return;
                          }
                          try {
                            await app.setMascot(mascot);
                          } catch (e) {
                            if (context.mounted) {
                              showMessage(context, friendlyError(e));
                            }
                          }
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );

class _CompanionTile extends StatelessWidget {
  const _CompanionTile({
    required this.mascot,
    required this.size,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final MascotId mascot;
  final double size;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: locked ? '${mascot.label}, Pro' : mascot.label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ShowdRadius.card),
      child: Container(
        width: size,
        padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s3),
        decoration: BoxDecoration(
          color: selected ? ShowdColors.carbon : null,
          borderRadius: BorderRadius.circular(ShowdRadius.card),
          border: Border.all(
            color: selected ? ShowdColors.accent : ShowdColors.graphite,
          ),
        ),
        child: Column(
          children: [
            Opacity(
              opacity: locked ? .55 : 1,
              child: CompanionView(mascot: mascot, size: size * .56),
            ),
            const SizedBox(height: ShowdSpace.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (locked) ...[
                  const ShowdIcon(
                    ShowdIcons.lock,
                    size: 14,
                    color: ShowdColors.stone,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    mascot.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShowdType.bodyM.copyWith(
                      color: selected ? ShowdColors.paper : ShowdColors.stone,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const PushedHeader(title: 'Privacy & proof'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                ShowdSpace.gutter,
                ShowdSpace.s4,
                ShowdSpace.gutter,
                ShowdSpace.s8,
              ),
              children: [
                Text('Proof stays on your phone.', style: ShowdType.titleXL),
                const SizedBox(height: ShowdSpace.s6),
                for (final (title, body) in [
                  (
                    'Your data',
                    'Alarms, history, reminders and proof stay on this device. If you join Battles, Firebase receives your chosen name, companion, battle membership and weekly outcomes and scores. Alarm names, step counts, locations and proof are never uploaded for Battles. RevenueCat receives an anonymous ID and your subscription status.',
                  ),
                  (
                    'Steps',
                    'With physical activity access, Android’s step counter reports how many steps you took during the alarm window. Only the count and timing stay on this phone.',
                  ),
                  (
                    'Tag scans',
                    'Google Play services opens its own scanner, so ShowdUp never gets camera access. Only a scrambled fingerprint of the code is kept, never what it says.',
                  ),
                  (
                    'Walks',
                    'Walk proof starts when you open the alarm or its first reminder rings. GPS measures real movement and ignores fake, stale and blurry locations. It proves the phone moved, not how hard you worked.',
                  ),
                  (
                    'Places',
                    'Gym and place proof uses a foreground service to check that you stay near the place for a few minutes. Place search text goes to Google Places. The chosen place and your arrival stay on this phone. ShowdUp never asks for background location.',
                  ),
                  (
                    'Apps you choose',
                    'For Phone-down focus, and for apps you catch, Android Accessibility tells ShowdUp only which app came to the front. ShowdUp never reads what is on screen, what you type, your notifications or passwords. Settings, your phone app and emergency apps are never held. Turn it off any time in Android Accessibility settings.',
                  ),
                  if (Features.workout)
                    (
                      'Health Connect workouts',
                      'Workout proof reads only workout time, type, how it was recorded and which app recorded it. Typed-in entries, routes and heart rate are never read.',
                    ),
                  if (Features.leetcode)
                    (
                      'LeetCode',
                      'ShowdUp sends the username you enter to LeetCode and reads the accepted problems shown on that public profile. It never asks for your password, a token or a cookie. If LeetCode can’t be reached, the day counts as “couldn’t tell”, not missed.',
                    ),
                  if (Features.overlay)
                    (
                      'Companion bubble',
                      'With “Display over other apps”, your companion and next alarm float over other apps. A notification shows while it runs. It never reads the app underneath. Turn it off from the bubble, the notification or Settings.',
                    ),
                  (
                    'Your controls',
                    'Hold to end today whenever you need to. Revoke any permission in Android settings. Delete data on this phone from Settings.',
                  ),
                  (
                    'Subscriptions',
                    'Google Play shows prices and renewal terms and handles cancellations. Deleting data or uninstalling doesn’t cancel billing.',
                  ),
                  (
                    'When a sensor fails',
                    'Missing sensors, revoked permissions and lost GPS show “Your phone couldn’t tell”. You get no points for that day and your streak stays.',
                  ),
                ]) ...[
                  Text(title, style: ShowdType.titleM),
                  const SizedBox(height: ShowdSpace.s2),
                  Text(body, style: ShowdType.bodyM.copyWith(height: 1.6)),
                  const SizedBox(height: ShowdSpace.s6),
                ],
                if (AppConfig.privacyPolicyUrl.isNotEmpty)
                  ShowdButton(
                    label: 'Read the full privacy policy',
                    tone: ShowdButtonTone.outline,
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.parse(AppConfig.privacyPolicyUrl),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        showMessage(
                          context,
                          'Couldn’t open the privacy policy.',
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Sounds, haptics and the alarm tone.
class _FeelSection extends StatelessWidget {
  const _FeelSection();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Sensory.settings,
    builder: (context, feel, _) => Column(
      children: [
        _Toggle(
          icon: ShowdIcons.bell,
          title: 'Sounds',
          value: feel.sounds,
          onChanged: (on) async {
            await Sensory.configure(sounds: on);
            Sensory.play(on ? Cue.toggleOn : Cue.toggleOff, haptic: false);
          },
        ),
        _Toggle(
          icon: ShowdIcons.focus,
          title: 'Haptics',
          value: feel.haptics,
          onChanged: (on) async {
            await Sensory.configure(haptics: on);
            Sensory.play(on ? Cue.toggleOn : Cue.toggleOff, sound: false);
          },
        ),
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.alarm),
          title: 'Tone',
          trailing: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: ShowdType.bodyM,
              selectedBackgroundColor: ShowdColors.accent.withValues(
                alpha: .16,
              ),
              selectedForegroundColor: ShowdColors.accent,
              foregroundColor: ShowdColors.stone,
              side: const BorderSide(color: ShowdColors.graphiteStrong),
            ),
            segments: const [
              ButtonSegment(value: 'showdup', label: Text('ShowdUp')),
              ButtonSegment(value: 'system', label: Text('Phone')),
            ],
            selected: {feel.alarmSound},
            onSelectionChanged: (value) {
              Sensory.play(Cue.select);
              Sensory.configure(alarmSound: value.first);
            },
          ),
        ),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final ShowdIcons icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => ShowdRow(
    leading: ShowdIcon(icon),
    title: title,
    onTap: () => onChanged(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );
}
