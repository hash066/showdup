import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'tokens.dart';
import 'type.dart';

/// A 48 px header row: optional leading control, optional title, trailing.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, this.leading, this.title, this.trailing});

  final Widget? leading;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: ShowdSpace.touch,
    child: Row(
      children: [
        ?leading,
        if (title != null)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: leading == null ? 0 : 8),
              child: Text(title!, style: ShowdType.label, maxLines: 1),
            ),
          )
        else
          const Spacer(),
        ?trailing,
      ],
    ),
  );
}

/// A 48 px icon-only button with a required label for screen readers.
class ShowdIconButton extends StatelessWidget {
  const ShowdIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color = ShowdColors.paper,
  });

  final ShowdIcons icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: InkResponse(
      onTap: onPressed,
      radius: 24,
      child: SizedBox.square(
        dimension: ShowdSpace.touch,
        child: Center(child: ShowdIcon(icon, color: color)),
      ),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = ShowdColors.stone});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: ShowdType.label.copyWith(color: color)),
  );
}

/// A number that must never clip: it scales down to fit its width.
class BigNumber extends StatelessWidget {
  const BigNumber(
    this.text, {
    super.key,
    this.style = ShowdType.numeralXL,
    this.color,
    this.align = Alignment.centerLeft,
    this.semanticLabel,
  });

  final String text;
  final TextStyle style;
  final Color? color;
  final Alignment align;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel != null,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align,
      child: Text(
        text,
        maxLines: 1,
        style: color == null ? style : style.copyWith(color: color),
      ),
    ),
  );
}

/// A settings-style row separated by a top hairline.
class ShowdRow extends StatelessWidget {
  const ShowdRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.titleStyle,
    this.hairline = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final TextStyle? titleStyle;
  final bool hairline;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: hairline
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: ShowdColors.graphite)),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 16)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (titleStyle ?? ShowdType.bodyL.copyWith(fontSize: 17))
                      .copyWith(color: danger ? ShowdColors.alert : null),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: ShowdType.bodyM),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    ),
  );
}

class ProPill extends StatelessWidget {
  const ProPill({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: ShowdColors.accentDeep),
    ),
    child: Text(
      'Pro',
      style: ShowdType.caption.copyWith(
        color: ShowdColors.accent,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

/// Quiet inline message. Not an alert box: one icon, one or two lines.
class ShowdNotice extends StatelessWidget {
  const ShowdNotice(
    this.message, {
    super.key,
    this.onRetry,
    this.icon = ShowdIcons.info,
  });

  final String message;
  final VoidCallback? onRetry;
  final ShowdIcons icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: ShowdSpace.s4),
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
    decoration: BoxDecoration(
      color: ShowdColors.carbon,
      borderRadius: BorderRadius.circular(ShowdRadius.control),
    ),
    child: Row(
      children: [
        ShowdIcon(icon, size: 20, color: ShowdColors.stone),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: ShowdType.bodyM.copyWith(color: ShowdColors.paper),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

/// Progress for proof: a track, a fill and a knob at the edge.
class ProofBar extends StatelessWidget {
  const ProofBar({super.key, required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) => Semantics(
    value: '${(progress.clamp(0, 1) * 100).round()} percent',
    child: SizedBox(
      height: 20,
      width: double.infinity,
      child: CustomPaint(painter: _ProofBarPainter(progress.clamp(0, 1))),
    ),
  );
}

class _ProofBarPainter extends CustomPainter {
  const _ProofBarPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 4, size.width, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(track, Paint()..color = ShowdColors.graphite);
    if (progress <= 0) return;
    final end = 9 + (size.width - 18) * progress;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height / 2 - 4, end, 8),
        const Radius.circular(4),
      ),
      Paint()..color = ShowdColors.accent,
    );
    canvas.drawCircle(
      Offset(end, size.height / 2),
      9,
      Paint()..color = ShowdColors.accent,
    );
  }

  @override
  bool shouldRepaint(_ProofBarPainter old) => old.progress != progress;
}

/// A selectable row with a radio mark. Used for presets, apps and plans.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.pro = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final bool pro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    button: true,
    label: pro ? '$title, Pro' : title,
    excludeSemantics: true,
    child: InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ShowdColors.graphite)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 16)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: ShowdType.titleM.copyWith(fontSize: 19),
                        ),
                      ),
                      if (pro) ...[const SizedBox(width: 8), const ProPill()],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: ShowdType.bodyM),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            RadioDot(selected: selected),
          ],
        ),
      ),
    ),
  );
}

class RadioDot extends StatelessWidget {
  const RadioDot({super.key, required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: ShowdMotion.quick,
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? ShowdColors.accent : Colors.transparent,
      border: selected
          ? null
          : Border.all(color: ShowdColors.graphiteStrong, width: 2),
    ),
    child: selected
        ? const Center(
            child: SizedBox.square(
              dimension: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ShowdColors.ink,
                ),
              ),
            ),
          )
        : null,
  );
}

/// Seven day toggles, Monday first. ISO weekdays: 1 = Monday.
class DayPicker extends StatelessWidget {
  const DayPicker({super.key, required this.selected, required this.onToggle});
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (var day = 1; day <= 7; day++)
        Semantics(
          toggled: selected.contains(day),
          button: true,
          label: _names[day - 1],
          excludeSemantics: true,
          child: InkResponse(
            onTap: () {
              HapticFeedback.selectionClick();
              onToggle(day);
            },
            radius: 24,
            child: AnimatedContainer(
              duration: ShowdMotion.quick,
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected.contains(day)
                    ? ShowdColors.accent
                    : Colors.transparent,
                border: selected.contains(day)
                    ? null
                    : Border.all(color: ShowdColors.graphiteStrong, width: 2),
              ),
              child: Text(
                _letters[day - 1],
                style: ShowdType.titleM.copyWith(
                  fontSize: 16,
                  color: selected.contains(day)
                      ? ShowdColors.ink
                      : ShowdColors.paper,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// First-letter avatar for an app or a person.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar(this.name, {super.key, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: ShowdColors.graphiteStrong,
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: ShowdType.titleM.copyWith(fontSize: size * .42),
      ),
    ),
  );
}
