import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'tokens.dart';
import 'type.dart';

enum ShowdButtonTone {
  /// Accent fill. One per screen, bottom-anchored.
  primary,

  /// Ink fill, for use on an accent background.
  onAccent,

  /// Hairline outline.
  outline,

  /// Text only, 48 px tall.
  quiet,
}

class ShowdButton extends StatelessWidget {
  const ShowdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = ShowdButtonTone.primary,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.underline = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ShowdButtonTone tone;
  final ShowdIcons? icon;
  final bool busy;
  final bool expand;
  final bool underline;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (tone) {
      ShowdButtonTone.primary => (
        enabled ? ShowdColors.accent : ShowdColors.graphite,
        enabled ? ShowdColors.onAccent : ShowdColors.stone,
        null,
      ),
      ShowdButtonTone.onAccent => (ShowdColors.ink, ShowdColors.paper, null),
      ShowdButtonTone.outline => (
        Colors.transparent,
        enabled ? ShowdColors.paper : ShowdColors.stone,
        ShowdColors.graphiteStrong,
      ),
      ShowdButtonTone.quiet => (
        Colors.transparent,
        enabled ? ShowdColors.paper : ShowdColors.stone,
        null,
      ),
    };
    final loud =
        tone == ShowdButtonTone.primary || tone == ShowdButtonTone.onAccent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ShowdRadius.control),
      side: border == null ? BorderSide.none : BorderSide(color: border),
    );
    final text = Text(
      busy ? 'One moment…' : label,
      textAlign: TextAlign.center,
      style: (loud ? ShowdType.button : ShowdType.bodyL).copyWith(
        color: fg,
        decoration: underline ? TextDecoration.underline : null,
        decorationColor: ShowdColors.graphiteStrong,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: bg,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: tone == ShowdButtonTone.quiet ? 48 : 56,
            width: expand ? double.infinity : null,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 12),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    ShowdIcon(icon!, size: 20, color: fg),
                    const SizedBox(width: 10),
                  ],
                  Flexible(child: text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A deliberate action: press and hold to confirm. Screen-reader users get a
/// confirmation dialog instead, since a hold gesture is hard to perform there.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmTitle = 'End today?',
    this.confirmBody =
        'Reminders stop and today counts as ended. Tomorrow is a fresh start.',
    this.confirmLabel = 'End today',
    this.enabled = true,
  });

  final String label;
  final VoidCallback onConfirmed;
  final String confirmTitle;
  final String confirmBody;
  final String confirmLabel;
  final bool enabled;

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: ShowdMotion.hold,
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
    _hold.value = 0;
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _confirmWithDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.confirmTitle),
        content: Text(widget.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
    if (ok == true) widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final fg = widget.enabled ? ShowdColors.paper : ShowdColors.stone;
    final body = Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShowdRadius.control),
        border: Border.all(color: ShowdColors.graphiteStrong),
      ),
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 22,
              child: CustomPaint(painter: _RingPainter(_hold.value)),
            ),
            const SizedBox(width: 10),
            Text(
              _hold.value > 0 ? 'Keep holding…' : widget.label,
              style: ShowdType.bodyL.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: widget.enabled,
      hint: accessible ? null : 'Press and hold to confirm',
      onTap: widget.enabled ? _confirmWithDialog : null,
      excludeSemantics: false,
      child: accessible
          ? InkWell(
              borderRadius: BorderRadius.circular(ShowdRadius.control),
              onTap: widget.enabled ? _confirmWithDialog : null,
              child: body,
            )
          : Listener(
              onPointerDown: widget.enabled
                  ? (_) {
                      HapticFeedback.selectionClick();
                      _hold.forward();
                    }
                  : null,
              onPointerUp: (_) {
                if (_hold.status != AnimationStatus.completed) _hold.reverse();
              },
              onPointerCancel: (_) => _hold.reverse(),
              child: body,
            ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ShowdColors.graphiteStrong;
    canvas.drawArc(rect.deflate(2), 0, math.pi * 2, false, track);
    final sweep = math.max(.12, progress) * math.pi * 2;
    canvas.drawArc(
      rect.deflate(2),
      -math.pi / 2,
      sweep,
      false,
      track
        ..color = ShowdColors.accent
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
