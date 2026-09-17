import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sensory.dart';
import 'svg_path.dart';
import 'tokens.dart';

/// The five states of the ShowdUp mark. One shape, drawn on a 96 unit grid.
enum MarkState {
  /// A bell (and a lock): the alarm is ringing or an app is caught.
  ringing,

  /// A person with arms up: proof landed.
  showedUp,

  /// An empty cup: the window passed without proof. No shame attached.
  missed,

  /// A cup with a dash: covered by a rest day.
  rest,

  /// A cup with a dotted dot: the phone couldn't tell.
  unverifiable,
}

const _cup = 'M28 46V56a20 20 0 0 0 40 0V46';
const _pivot = Offset(48, 51);

/// Static rendering of the mark. Stroke width scales with [size].
class ShowdMark extends StatelessWidget {
  const ShowdMark({
    super.key,
    this.state = MarkState.showedUp,
    this.size = 48,
    this.lineColor = ShowdColors.paper,
    this.dotColor = ShowdColors.accent,
    this.semanticLabel,
  });

  final MarkState state;
  final double size;
  final Color lineColor;
  final Color dotColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painter = MarkPainter(
      state: state,
      lineColor: lineColor,
      dotColor: dotColor,
    );
    final child = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: painter),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: child);
    return Semantics(label: semanticLabel, image: true, child: child);
  }
}

/// Paints the mark. [turn] rotates the person glyph around its centre:
/// 0 is the person, 1 is the bell. Values between animate the flip.
class MarkPainter extends CustomPainter {
  const MarkPainter({
    required this.state,
    this.lineColor = ShowdColors.paper,
    this.dotColor = ShowdColors.accent,
    this.turn,
  });

  final MarkState state;
  final Color lineColor;
  final Color dotColor;
  final double? turn;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 96, size.height / 96);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..color = state == MarkState.missed ? ShowdColors.missed : lineColor;
    final dot = Paint()..color = dotColor;

    switch (state) {
      case MarkState.showedUp || MarkState.ringing:
        final t = turn ?? (state == MarkState.ringing ? 1.0 : 0.0);
        canvas.translate(_pivot.dx, _pivot.dy);
        canvas.rotate(math.pi * t);
        canvas.translate(-_pivot.dx, -_pivot.dy);
        canvas.drawPath(svgPath(_cup), line);
        canvas.drawCircle(const Offset(48, 26), 10, dot);
      case MarkState.missed:
        canvas.drawPath(svgPath(_cup), line);
      case MarkState.rest:
        canvas.drawPath(svgPath(_cup), line);
        canvas.drawLine(
          const Offset(39, 26),
          const Offset(57, 26),
          Paint()
            ..color = ShowdColors.stone
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round,
        );
      case MarkState.unverifiable:
        canvas.drawPath(svgPath(_cup), line);
        final dash = Paint()
          ..color = ShowdColors.stone
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        const segments = 8;
        for (var i = 0; i < segments; i++) {
          final start = i * 2 * math.pi / segments;
          canvas.drawArc(
            Rect.fromCircle(center: const Offset(48, 26), radius: 9),
            start,
            math.pi / segments * .7,
            false,
            dash,
          );
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarkPainter old) =>
      old.state != state ||
      old.turn != turn ||
      old.lineColor != lineColor ||
      old.dotColor != dotColor;
}

/// The signature move: the ringing bell flips into a person when proof lands.
///
/// Set [showedUp] to true to play the flip. Reduce motion swaps instantly.
class FlippingMark extends StatefulWidget {
  const FlippingMark({
    super.key,
    required this.showedUp,
    this.size = 120,
    this.lineColor = ShowdColors.paper,
    this.dotColor = ShowdColors.accent,
    this.ringWhileWaiting = false,
    this.cue = true,
  });

  /// Plays the flip sound and haptic. Off when a louder cue covers it.
  final bool cue;

  final bool showedUp;
  final double size;
  final Color lineColor;
  final Color dotColor;

  /// Rocks the bell gently while it waits, like a ringing alarm.
  final bool ringWhileWaiting;

  @override
  State<FlippingMark> createState() => _FlippingMarkState();
}

class _FlippingMarkState extends State<FlippingMark>
    with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: ShowdMotion.flip,
    value: widget.showedUp ? 1 : 0,
  );
  late final AnimationController _rock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRock();
  }

  @override
  void didUpdateWidget(FlippingMark old) {
    super.didUpdateWidget(old);
    if (old.showedUp != widget.showedUp) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) {
        _flip.value = widget.showedUp ? 1 : 0;
      } else if (widget.showedUp) {
        _flip.forward();
        if (widget.cue) Sensory.play(Cue.flip);
      } else {
        _flip.reverse();
      }
    }
    _syncRock();
  }

  void _syncRock() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.ringWhileWaiting && !widget.showedUp && !reduce) {
      if (!_rock.isAnimating) _rock.repeat(reverse: true);
    } else {
      _rock.stop();
      _rock.value = .5;
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _rock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.showedUp ? 'Showed up' : 'Alarm waiting for proof',
    image: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_flip, _rock]),
        builder: (context, _) {
          final progress = ShowdMotion.flipCurve.transform(_flip.value);
          final wobble = widget.showedUp ? 0.0 : (_rock.value - .5) * .09;
          return CustomPaint(
            painter: MarkPainter(
              state: MarkState.ringing,
              lineColor: widget.lineColor,
              dotColor: widget.dotColor,
              turn: 1 - progress + wobble,
            ),
          );
        },
      ),
    ),
  );
}
