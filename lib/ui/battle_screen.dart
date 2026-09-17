import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../design/buttons.dart';
import '../design/companion.dart';
import '../design/icons.dart';
import '../design/layout.dart';
import '../design/tokens.dart';
import '../design/type.dart';
import '../models/battle.dart';
import '../models/pet.dart';
import '../services/controller.dart';
import '../services/social_service.dart';
import 'app_provider.dart';
import 'screens/settings.dart';

/// Private weekly scoreboard with friends.
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
          if (mounted) setState(() => battle = value);
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
    final capacity = app.user?.isPro == true ? 10 : 4;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ShowdSpace.gutter,
        ShowdSpace.s4,
        ShowdSpace.gutter,
        ShowdSpace.s8,
      ),
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => showCompanionSheet(context, app),
              borderRadius: BorderRadius.circular(ShowdRadius.card),
              child: CompanionView(
                mascot: pet.mascot,
                mood: companionMoodFor(pet.mood),
                size: 88,
              ),
            ),
            const SizedBox(width: ShowdSpace.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BigNumber(
                    '${pet.weeklyScore}',
                    style: ShowdType.numeralL,
                    semanticLabel: '${pet.weeklyScore} points this week',
                  ),
                  Text('points this week', style: ShowdType.bodyM),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ShowdSpace.s8),
        if (!SocialService.instance.available)
          const ShowdNotice(
            'Battles aren’t switched on in this build. Everything else works on this phone.',
          )
        else if (battle == null) ...[
          Text('A battle starts when a friend joins.', style: ShowdType.titleL),
          const SizedBox(height: ShowdSpace.s2),
          Text(
            'A private scoreboard that resets every Monday. Free: you and 3 friends. Pro: up to 10 people.',
            style: ShowdType.bodyM,
          ),
          const SizedBox(height: ShowdSpace.s6),
          ShowdButton(
            label: 'Start a battle',
            busy: busy,
            onPressed: () => run(
              () => SocialService.instance.createBattle(
                timezone: app.user?.timezone ?? 'Asia/Kolkata',
                mascot: pet.mascot,
              ),
            ),
          ),
          const SizedBox(height: ShowdSpace.s8),
          TextField(
            controller: code,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Invite code'),
          ),
          ShowdButton(
            label: 'Join',
            tone: ShowdButtonTone.outline,
            onPressed: busy || code.text.trim().length != 6
                ? null
                : () => run(() => SocialService.instance.join(code.text)),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(child: Text(battle!.name, style: ShowdType.titleL)),
              Text(
                '${battle!.memberUids.length}/$capacity',
                style: ShowdType.label,
              ),
            ],
          ),
          Text(
            battle!.active ? 'This week' : 'Waiting for a friend to join',
            style: ShowdType.bodyM,
          ),
          const SizedBox(height: ShowdSpace.s4),
          for (final member in scores) _ScoreRow(member: member),
          if (scores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s4),
              child: Text(
                'Invite a friend to start the scoreboard.',
                style: ShowdType.bodyM,
              ),
            ),
          const SizedBox(height: ShowdSpace.s6),
          ShowdButton(
            label: 'Invite a friend',
            icon: ShowdIcons.share,
            busy: busy,
            onPressed: battle!.memberUids.length >= capacity
                ? null
                : () => run(() async {
                    final invite = await SocialService.instance.createInvite(
                      battle!.id,
                    );
                    await SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Battle me on ShowdUp: ${invite.url}\nCode: ${invite.code}',
                      ),
                    );
                  }),
          ),
          ShowdButton(
            label: 'Leave battle',
            tone: ShowdButtonTone.quiet,
            onPressed: busy
                ? null
                : () => run(() => SocialService.instance.leave(battle!.id)),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: ShowdSpace.s4),
          ShowdNotice(error!),
        ],
      ],
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.member});
  final BattleMemberScore member;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: ShowdSpace.s3),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: ShowdColors.graphite)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: BigNumber(
            '${member.rank}',
            style: ShowdType.numeralM.copyWith(fontSize: 40),
            color: member.rank == 1 ? ShowdColors.accent : ShowdColors.stone,
          ),
        ),
        CompanionView(mascot: MascotId.fromWire(member.mascot), size: 40),
        const SizedBox(width: ShowdSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(member.displayName, style: ShowdType.bodyL),
              Text(
                member.provisional
                    ? '${member.eligibleAttempts} of 3 alarms to rank'
                    : '${member.eligibleAttempts} alarms this week',
                style: ShowdType.caption,
              ),
            ],
          ),
        ),
        BigNumber(
          '${member.score}',
          style: ShowdType.numeralM.copyWith(fontSize: 40),
          align: Alignment.centerRight,
        ),
      ],
    ),
  );
}
