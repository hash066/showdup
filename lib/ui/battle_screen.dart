import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../core/theme.dart';
import '../models/battle.dart';
import '../models/pet.dart';
import '../platform/overlay_channel.dart';
import '../services/controller.dart';
import '../services/social_service.dart';
import 'app.dart';
import 'screens.dart';
import 'widgets.dart';

class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key});
  @override
  ConsumerState<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends ConsumerState<BattleScreen> {
  final code = TextEditingController();
  StreamSubscription<Battle?>? battleSub;
  StreamSubscription<List<BattleMemberScore>>? scoreSub;
  Battle? battle;
  List<BattleMemberScore> scores = const [];
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final pending = SocialService.instance.pendingInviteCode;
    if (pending != null) {
      code.text = pending;
      SocialService.instance.pendingInviteCode = null;
    }
    if (SocialService.instance.available) {
      unawaited(SocialService.instance.startWatching());
      battleSub = SocialService.instance.battleStates().listen(
        (value) {
          if (mounted) {
            setState(() {
              battle = value;
            });
          }
        },
        onError: (Object e) {
          if (mounted) setState(() => error = friendlyError(e));
        },
      );
      scoreSub = SocialService.instance.scoreStates().listen(
        (items) {
          if (mounted) setState(() => scores = items);
        },
        onError: (Object e) {
          if (mounted) setState(() => error = friendlyError(e));
        },
      );
    }
  }

  @override
  void dispose() {
    code.dispose();
    battleSub?.cancel();
    scoreSub?.cancel();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final pet = app.petSnapshot;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const PageHeading('Your pet remembers.', 'Battle'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    pet.mascot.fallbackGlyph,
                    style: const TextStyle(fontSize: 52),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pet.weeklyScore} weekly points',
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${pet.mood.name} · ${pet.streak} day streak',
                          style: const TextStyle(color: T.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Choose your accountability pet',
                style: TextStyle(fontSize: 12, color: T.muted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final mascot in MascotId.values)
                    ChoiceChip(
                      avatar: Text(mascot.fallbackGlyph),
                      label: Text(mascot.label),
                      selected: pet.mascot == mascot,
                      onSelected: (_) => app.setMascot(mascot),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        var status = await OverlayChannel.status();
                        if (!status.permissionGranted) {
                          await OverlayChannel.requestPermission();
                          return;
                        }
                        if (status.enabled) {
                          await OverlayChannel.disable();
                        } else {
                          await OverlayChannel.enable();
                        }
                      }),
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
                label: const Text('Enable or disable pet overlay'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (!SocialService.instance.available)
          const Panel(
            child: Text(
              'Battles need the Firebase release configuration. Solo commitments and the overlay still work locally.',
            ),
          )
        else if (battle == null)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'A battle starts only when a friend joins.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create a private weekly group for up to 10 people, or enter a six-character invite code.',
                  style: TextStyle(color: T.muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final timezone = app.user?.timezone ?? 'Asia/Kolkata';
                          await SocialService.instance.createBattle(
                            timezone: timezone,
                            mascot: pet.mascot,
                          );
                        }),
                  child: const Text('Create battle and invite a friend'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: 'Invite code'),
                ),
                OutlinedButton(
                  onPressed: busy || code.text.trim().length != 6
                      ? null
                      : () => run(() => SocialService.instance.join(code.text)),
                  child: const Text('Join battle'),
                ),
              ],
            ),
          )
        else ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        battle!.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text('${battle!.memberUids.length}/10'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  battle!.active
                      ? 'Active this week'
                      : 'Waiting for one friend to join',
                  style: const TextStyle(color: T.muted),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: busy || battle!.memberUids.length >= 10
                      ? null
                      : () => run(() async {
                          final invite = await SocialService.instance
                              .createInvite(battle!.id);
                          await SharePlus.instance.share(
                            ShareParams(
                              text:
                                  'Battle me on ShowdUp: ${invite.url}\nJoin code: ${invite.code}',
                            ),
                          );
                        }),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Invite friend'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () =>
                            run(() => SocialService.instance.leave(battle!.id)),
                  child: const Text('Leave battle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                for (final member in scores)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(
                        MascotId.fromWire(member.mascot).fallbackGlyph,
                      ),
                    ),
                    title: Text('${member.rank}. ${member.displayName}'),
                    subtitle: Text(
                      member.provisional
                          ? '${member.eligibleAttempts}/3 · provisional'
                          : member.petMood,
                    ),
                    trailing: Text(
                      '${member.score}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                if (scores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Invite a friend to activate rankings.',
                      style: TextStyle(color: T.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(error!, style: const TextStyle(color: T.danger)),
          ),
      ],
    );
  }
}
