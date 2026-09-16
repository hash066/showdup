import 'package:flutter/material.dart';

import '../core/theme.dart';

class CoachMarkStep {
  const CoachMarkStep({
    required this.target,
    required this.title,
    required this.body,
  });

  final GlobalKey target;
  final String title;
  final String body;
}

Future<void> showCoachMarks(
  BuildContext context,
  List<CoachMarkStep> steps,
) async {
  final usable = steps
      .where(
        (step) => step.target.currentContext?.findRenderObject() is RenderBox,
      )
      .toList();
  if (usable.isEmpty || !context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    pageBuilder: (_, _, _) => _CoachMarks(steps: usable),
  );
}

class _CoachMarks extends StatefulWidget {
  const _CoachMarks({required this.steps});
  final List<CoachMarkStep> steps;

  @override
  State<_CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<_CoachMarks> {
  int index = 0;

  Rect? get targetRect {
    final render = widget.steps[index].target.currentContext
        ?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final rect =
        targetRect?.inflate(8) ?? Rect.fromLTWH(24, 100, size.width - 48, 100);
    final cardAbove = rect.center.dy > size.height * .56;
    final step = widget.steps[index];
    return Material(
      color: Colors.transparent,
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: '${step.title}. ${step.body}',
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _SpotlightPainter(rect)),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: cardAbove
                  ? null
                  : (rect.bottom + 18).clamp(24, size.height - 250),
              bottom: cardAbove
                  ? (size.height - rect.top + 18).clamp(24, size.height - 250)
                  : null,
              child: _CoachPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.body,
                      style: const TextStyle(color: T.muted, height: 1.5),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Skip'),
                        ),
                        const Spacer(),
                        if (index > 0)
                          TextButton(
                            onPressed: () => setState(() => index--),
                            child: const Text('Back'),
                          ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            if (index == widget.steps.length - 1) {
                              Navigator.pop(context);
                            } else {
                              setState(() => index++);
                            }
                          },
                          child: Text(
                            index == widget.steps.length - 1
                                ? 'Got it'
                                : 'Next',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(22)));
    final dimmed = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(
      dimmed,
      Paint()..color = Colors.black.withValues(alpha: .82),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = T.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

class _CoachPanel extends StatelessWidget {
  const _CoachPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: T.surface,
      borderRadius: BorderRadius.circular(T.radius),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: child,
  );
}
