import 'package:flutter/material.dart';

import '../models/pet.dart';
import 'buttons.dart';
import 'companion.dart';
import 'icons.dart';
import 'layout.dart';
import 'mark.dart';
import 'tokens.dart';
import 'type.dart';

/// Debug-only catalogue of the design system, opened from Settings.
class DesignGallery extends StatefulWidget {
  const DesignGallery({super.key});

  @override
  State<DesignGallery> createState() => _DesignGalleryState();
}

class _DesignGalleryState extends State<DesignGallery> {
  var _showedUp = false;
  var _days = {1, 2, 3, 4, 5};
  var _choice = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: ShowdSpace.gutter),
        children: [
          ScreenHeader(
            leading: ShowdIconButton(
              icon: ShowdIcons.back,
              semanticLabel: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
            title: 'Design gallery',
          ),
          const SizedBox(height: ShowdSpace.s6),
          const SectionLabel('Mark'),
          const SizedBox(height: ShowdSpace.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final state in MarkState.values)
                ShowdMark(state: state, size: 52),
            ],
          ),
          const SizedBox(height: ShowdSpace.s4),
          Center(
            child: GestureDetector(
              onTap: () => setState(() => _showedUp = !_showedUp),
              child: FlippingMark(showedUp: _showedUp, size: 120),
            ),
          ),
          const SizedBox(height: ShowdSpace.s8),
          const SectionLabel('Type'),
          const BigNumber('06:30'),
          Text('Walk 2,000 steps', style: ShowdType.hero),
          Text('Instagram is caught', style: ShowdType.titleL),
          Text('Body copy sits in Bricolage at 16.', style: ShowdType.bodyL),
          Text('Secondary copy is stone.', style: ShowdType.bodyM),
          const SizedBox(height: ShowdSpace.s8),
          const SectionLabel('Companions'),
          const SizedBox(height: ShowdSpace.s3),
          for (final mascot in MascotId.values)
            Padding(
              padding: const EdgeInsets.only(bottom: ShowdSpace.s3),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(mascot.label, style: ShowdType.bodyM),
                  ),
                  for (final mood in CompanionMood.values)
                    Expanded(
                      child: CompanionView(
                        mascot: mascot,
                        mood: mood,
                        size: 52,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: ShowdSpace.s6),
          const SectionLabel('Icons'),
          const SizedBox(height: ShowdSpace.s3),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final icon in ShowdIcons.values)
                ShowdIcon(icon, semanticLabel: icon.name),
            ],
          ),
          const SizedBox(height: ShowdSpace.s8),
          const SectionLabel('Controls'),
          const SizedBox(height: ShowdSpace.s3),
          ShowdButton(label: 'Save alarm', onPressed: () {}),
          const SizedBox(height: ShowdSpace.s3),
          ShowdButton(
            label: 'Add a proof alarm',
            icon: ShowdIcons.add,
            tone: ShowdButtonTone.outline,
            onPressed: () {},
          ),
          const SizedBox(height: ShowdSpace.s3),
          HoldToConfirmButton(label: 'Hold to end today', onConfirmed: () {}),
          const SizedBox(height: ShowdSpace.s6),
          const ProofBar(progress: .62),
          const SizedBox(height: ShowdSpace.s6),
          DayPicker(
            selected: _days,
            onToggle: (day) => setState(
              () => _days = _days.contains(day)
                  ? ({..._days}..remove(day))
                  : {..._days, day},
            ),
          ),
          const SizedBox(height: ShowdSpace.s6),
          for (final (i, (title, pro)) in const [
            ('Walk', false),
            ('Gym', true),
          ].indexed)
            ChoiceRow(
              title: title,
              subtitle: pro ? 'Arrive at a place' : 'Move for a set time',
              leading: ShowdIcon(i == 0 ? ShowdIcons.walk : ShowdIcons.gym),
              pro: pro,
              selected: _choice == i,
              onTap: () => setState(() => _choice = i),
            ),
          ShowdRow(
            title: 'ShowdUp Pro',
            subtitle: 'More alarms, places and apps',
            trailing: const ProPill(),
            onTap: () {},
          ),
          const SizedBox(height: ShowdSpace.s4),
          const ShowdNotice('Location is off, so arrival cannot be checked.'),
          const SizedBox(height: ShowdSpace.s12),
        ],
      ),
    ),
  );
}
