import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/buttons.dart';
import '../../design/chrome.dart';
import '../../design/icons.dart';
import '../../design/layout.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../models/commitment.dart';
import '../../models/enums.dart';
import '../../services/controller.dart';
import '../app_provider.dart';
import 'common.dart';

/// Every proof alarm as one row: what, when, and an on/off switch.
class CommitmentsScreen extends ConsumerWidget {
  const CommitmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final items = app.commitments
        .where((c) => c.status != CommitmentStatus.archived)
        .toList();
    final isPro = app.user?.isPro == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ShowdSpace.gutter,
        ShowdSpace.s4,
        ShowdSpace.gutter,
        ShowdSpace.s8,
      ),
      children: [
        if (items.isEmpty) ...[
          Text('No proof alarms yet.', style: ShowdType.titleL),
          const SizedBox(height: ShowdSpace.s2),
          Text(
            'A proof alarm keeps ringing until your phone sees you did it.',
            style: ShowdType.bodyM,
          ),
          const SizedBox(height: ShowdSpace.s6),
        ],
        for (final c in items) _CommitmentRow(app: app, commitment: c),
        const SizedBox(height: ShowdSpace.s6),
        ShowdButton(
          label: 'New proof alarm',
          icon: ShowdIcons.add,
          tone: items.isEmpty
              ? ShowdButtonTone.primary
              : ShowdButtonTone.outline,
          onPressed: () => openWizard(context),
        ),
        const SizedBox(height: ShowdSpace.s3),
        Text(
          isPro ? 'Pro · up to 20 on at once' : 'Free · one on at a time',
          textAlign: TextAlign.center,
          style: ShowdType.caption,
        ),
      ],
    );
  }
}

class _CommitmentRow extends StatelessWidget {
  const _CommitmentRow({required this.app, required this.commitment});

  final AppController app;
  final Commitment commitment;

  Future<void> _setStatus(BuildContext context, CommitmentStatus status) async {
    try {
      await app.repository.update(commitment.id, {'status': status.wire});
    } catch (e) {
      if (context.mounted) await showLimitOrMessage(context, e);
    }
  }

  Future<void> _actions(BuildContext context) => showShowdSheet<void>(
    context,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(commitment.title, style: ShowdType.titleL),
        const SizedBox(height: ShowdSpace.s1),
        Text(scheduleLine(commitment), style: ShowdType.bodyM),
        const SizedBox(height: ShowdSpace.s4),
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.edit),
          title: commitment.status == CommitmentStatus.draft
              ? 'Finish setup'
              : 'Edit',
          onTap: () {
            Navigator.pop(sheetContext);
            openWizard(context, commitment: commitment);
          },
        ),
        ShowdRow(
          leading: const ShowdIcon(ShowdIcons.close, color: ShowdColors.alert),
          title: 'Archive',
          subtitle: 'It stops ringing. History stays.',
          danger: true,
          onTap: () {
            Navigator.pop(sheetContext);
            _setStatus(context, CommitmentStatus.archived);
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = commitment;
    final active = c.status == CommitmentStatus.active;
    final draft = c.status == CommitmentStatus.draft;
    final caught = c.restrictions.enabled && c.restrictions.packages.isNotEmpty;
    return ShowdRow(
      onTap: () => _actions(context),
      leading: ShowdIcon(
        kindIcon(c.kind),
        color: active ? ShowdColors.accent : ShowdColors.stone,
      ),
      title: c.title,
      subtitle: draft
          ? 'Draft · needs Android access'
          : [
              scheduleLine(c),
              if (caught)
                'catches ${c.restrictions.packages.length} app${c.restrictions.packages.length == 1 ? '' : 's'}',
            ].join(' · '),
      trailing: draft
          ? TextButton(
              onPressed: () => openWizard(context, commitment: c),
              child: const Text('Finish'),
            )
          : Semantics(
              label: active ? 'Turn off ${c.title}' : 'Turn on ${c.title}',
              child: Switch(
                value: active,
                onChanged: (on) => _setStatus(
                  context,
                  on ? CommitmentStatus.active : CommitmentStatus.paused,
                ),
              ),
            ),
    );
  }
}
