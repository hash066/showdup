import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/enums.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 24});
  final double size;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: size + 10,
        height: size + 10,
        decoration: BoxDecoration(
          color: T.accent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.check_rounded, color: T.bg, size: size),
      ),
      const SizedBox(width: 10),
      // The wordmark must never wrap mid-word; on narrow screens with large
      // text it scales down to the space available instead of overflowing.
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            'ShowdUp',
            maxLines: 1,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = T.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: color,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 2,
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = T.surface,
    this.padding = 24,
  });
  final Widget child;
  final Color color;
  final double padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .055)),
    ),
    child: child,
  );
}

class ProgressOrbit extends StatelessWidget {
  const ProgressOrbit({
    super.key,
    required this.progress,
    this.label = 'SHOW UP',
    this.value,
    this.size = 220,
    this.color = T.accent,
  });
  final double progress;
  final String label;
  final String? value;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label.toLowerCase(),
    value: '${(progress * 100).round()} percent',
    readOnly: true,
    child: ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _OrbitPainter(progress, color),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                progress >= 1
                    ? Icons.check_rounded
                    : Icons.directions_walk_rounded,
                color: color,
                size: 30,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: size * .72,
                height: size * .25,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value ?? '${(progress * 100).round()}%',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: size * .2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: size * .72,
                height: 24,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: T.muted,
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.progress, this.color);
  final double progress;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2), radius = s.width / 2 - 14;
    final base = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11;
    c.drawCircle(center, radius, base);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 11;
    c.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      p,
    );
    for (var i = 0; i < 40; i++) {
      final a = i * math.pi / 20;
      final r = radius - 18;
      c.drawCircle(
        center + Offset(math.cos(a) * r, math.sin(a) * r),
        1,
        Paint()..color = Colors.white.withValues(alpha: .12),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.progress != progress || old.color != color;
}

String stateLabel(AttemptState state) => switch (state) {
  AttemptState.pending => 'In progress',
  AttemptState.completed => 'Showed up',
  AttemptState.abandoned => 'Ended for today',
  AttemptState.expired => 'Window ended',
  AttemptState.unverifiable => 'Unable to verify',
};
Color stateColor(AttemptState state) => switch (state) {
  AttemptState.completed => T.ok,
  AttemptState.pending => T.accent,
  AttemptState.unverifiable => T.muted,
  AttemptState.abandoned => T.muted,
  AttemptState.expired => T.danger,
};

class StatePill extends StatelessWidget {
  const StatePill(this.state, {super.key});
  final AttemptState state;
  @override
  Widget build(BuildContext context) {
    final color = stateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stateLabel(state),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Future<void> showMessage(BuildContext context, String text) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Panel(
      padding: 16,
      color: T.danger.withValues(alpha: .10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: T.accent),
          const SizedBox(width: 12),
          // Retry sits under the message so large text never squeezes the
          // message into a sliver beside the button.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: const TextStyle(fontSize: 13)),
                if (onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
