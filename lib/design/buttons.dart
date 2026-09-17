import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'icons.dart';
import 'motion.dart';
import 'sensory.dart';
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
    this.cue = Cue.tap,
  });

  final String label;
  final VoidCallback? onPressed;
  final ShowdButtonTone tone;
  final ShowdIcons? icon;
  final bool busy;
  final bool expand;
  final bool underline;

  /// What the press sounds and feels like.
  final Cue cue;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (tone) {
      ShowdButtonTone.primary => (
        enabled || busy ? ShowdColors.accent : ShowdColors.graphite,
        enabled || busy ? ShowdColors.onAccent : ShowdColors.stone,
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
    final content = AnimatedSwitcher(
      duration: ShowdMotion.quick,
      child: busy
          ? BusyDots(key: const ValueKey('busy'), color: fg)
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  ShowdIcon(icon!, size: 20, color: fg),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: (loud ? ShowdType.button : ShowdType.bodyL).copyWith(
                      color: fg,
                      decoration: underline ? TextDecoration.underline : null,
                      decorationColor: ShowdColors.graphiteStrong,
                    ),
                  ),
                ),
              ],
            ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: busy ? '$label, working' : null,
      child: PressScale(
        enabled: enabled,
        child: AnimatedContainer(
          duration: ShowdMotion.quick,
          decoration: ShapeDecoration(color: bg, shape: shape),
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled
                  ? () {
                      Sensory.play(cue);
                      onPressed!();
                    }
                  : null,
              child: SizedBox(
                height: tone == ShowdButtonTone.quiet ? 48 : 56,
                width: expand ? double.infinity : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 12),
                  child: Center(child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that hop in turn, for buttons that are working.
class BusyDots extends StatefulWidget {
  const BusyDots({super.key, this.color = ShowdColors.ink});
  final Color color;

  @override
  State<BusyDots> createState() => _BusyDotsState();
}

class _BusyDotsState extends State<BusyDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.loops(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Transform.translate(
            offset: Offset(
              0,
              -6 *
                  math.max(
                    0,
                    math.sin((_controller.value - i * 0.18) * math.pi * 2),
                  ),
            ),
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    ),
  );
}

/// A deliberate action: press and hold to confirm. It fills as you hold,
/// ticking louder toward the end. Screen-reader users get a confirmation
/// dialog instead, since a hold gesture is hard to perform there.
class HoldToConfirmButton extends StatefulWidget {
  const HoldToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmTitle = 'End today?',
    this.confirmBody = 'Reminders stop. Tomorrow is a fresh start.',
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
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: ShowdMotion.hold)
        ..addListener(_onTick)
        ..addStatusListener(_onStatus);

  var _quarter = 0;

  void _onTick() {
    final quarter = (_hold.value * 4).floor();
    if (_hold.status == AnimationStatus.forward &&
        quarter > _quarter &&
        quarter < 4) {
      Sensory.play(Cue.holdTick, intensity: quarter / 4);
    }
    _quarter = quarter;
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    Sensory.play(Cue.land);
    widget.onConfirmed();
    _hold.value = 0;
    _quarter = 0;
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _confirmWithDialog() async {
    Sensory.play(Cue.tap);
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
    if (ok == true) {
      Sensory.play(Cue.land);
      widget.onConfirmed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final fg = widget.enabled ? ShowdColors.paper : ShowdColors.stone;
    final body = Container(
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ShowdRadius.control),
        border: Border.all(color: ShowdColors.graphiteStrong),
      ),
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, _) => Stack(
          children: [
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _hold.value,
                child: const ColoredBox(color: ShowdColors.graphite),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: CustomPaint(painter: _RingPainter(_hold.value)),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _hold.value > 0 ? 'Keep holding' : widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: ShowdType.bodyL.copyWith(color: fg),
                      ),
                    ),
                  ],
                ),
              ),
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
                      Sensory.play(Cue.select);
                      _hold.forward();
                    }
                  : null,
              onPointerUp: (_) {
                if (_hold.status != AnimationStatus.completed) _hold.reverse();
              },
              onPointerCancel: (_) => _hold.reverse(),
              child: PressScale(
                enabled: widget.enabled,
                scale: 0.98,
                child: body,
              ),
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
