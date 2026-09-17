import 'package:flutter/widgets.dart';

import 'svg_path.dart';
import 'tokens.dart';

/// ShowdUp icon set: 24 unit grid, 2 unit round stroke, same ends as the mark.
enum ShowdIcons {
  alarm(['M12 10v3l2 1.5M5 3.5 3 5.5M19 3.5l2 2'], circles: [(12, 13, 7)]),
  check(['M5 12.5l4.5 4.5L19 7.5']),
  walk(
    [
      'M11.5 8.5 9.5 14l3.5 2.5.5 4.5M9.5 14 7 20M12 9l3.5 3H18M10.5 9 7.5 10.5 6.5 13.5',
    ],
    circles: [(13, 4.5, 1.8)],
  ),
  steps(
    ['M7.5 14.5h2M14.5 20.5h2'],
    ellipses: [(8.5, 8, 2.5, 4), (15.5, 14, 2.5, 4)],
  ),
  gym(['M6.5 8v8M17.5 8v8M3.5 10v4M20.5 10v4M6.5 12h11']),
  arrive(
    ['M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z'],
    circles: [(12, 10, 2.2)],
  ),
  focus([], circles: [(12, 12, 8), (12, 12, 3.5)]),
  tagScan(
    ['M14 14h2v2h-2zM18 18h2v2h-2zM14 20h1M20 14v1'],
    rects: [(4, 4, 6, 6, 1), (14, 4, 6, 6, 1), (4, 14, 6, 6, 1)],
  ),
  code(['M8.5 7 3.5 12l5 5M15.5 7l5 5-5 5M13.5 5l-3 14']),
  calendar(['M4 10h16M8.5 3v4M15.5 3v4'], rects: [(4, 5, 16, 15, 3)]),
  history(['M4 12a8 8 0 1 0 2.3-5.6M4 4v3.5h3.5M12 8v4l2.5 2']),
  battle([
    'M8 4h8v5a4 4 0 0 1-8 0V4zM8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8.5 20h7',
  ]),
  settings(['M4 7h9M17 7h3M4 17h3M11 17h9'], circles: [(15, 7, 2), (9, 17, 2)]),
  snooze(['M19 14.5A7.5 7.5 0 1 1 9.5 5a6 6 0 0 0 9.5 9.5z']),
  end([], rects: [(7, 7, 10, 10, 2.5)]),
  caught(['M7.5 13V9.5a4.5 4.5 0 0 1 9 0V13'], circles: [(12, 16.5, 3)]),
  released(['M7.5 11v2.5a4.5 4.5 0 0 0 9 0V11'], circles: [(12, 6, 2.5)]),
  share(['M12 15V4M8 7.5 12 3.5l4 4M5 12v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6']),
  add(['M12 5v14M5 12h14']),
  edit(['M4.5 19.5l1.2-4.6 9.7-9.7a2.1 2.1 0 0 1 3 3l-9.7 9.7zM13.6 7l3 3']),
  rest(['M7.5 11v2.5a4.5 4.5 0 0 0 9 0V11M10 6h4']),
  next(['M9.5 6l6 6-6 6']),
  back(['M14.5 6l-6 6 6 6']),
  close(['M6.5 6.5l11 11M17.5 6.5l-11 11']),
  info(['M12 11v5.5M12 7.8v.2'], circles: [(12, 12, 8.5)]),
  companion(['M8 9 7.5 4.5l3.5 3M16 9l.5-4.5-3.5 3'], circles: [(12, 13, 6)]),
  lock(['M8 11V8a4 4 0 0 1 8 0v3'], rects: [(5.5, 11, 13, 9, 2.5)]),
  bell(['M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 21h4']),
  shield(['M12 3l7 3v5.5c0 4.5-3 8-7 9.5-4-1.5-7-5-7-9.5V6z']);

  const ShowdIcons(
    this.paths, {
    this.circles = const [],
    this.ellipses = const [],
    this.rects = const [],
  });

  final List<String> paths;
  final List<(double, double, double)> circles;
  final List<(double, double, double, double)> ellipses;
  final List<(double, double, double, double, double)> rects;

  List<String> get allPaths => [
    ...paths,
    for (final (x, y, r) in circles) circlePath(x, y, r),
    for (final (x, y, rx, ry) in ellipses) ellipsePath(x, y, rx, ry),
    for (final (x, y, w, h, r) in rects) rectPath(x, y, w, h, r),
  ];
}

class ShowdIcon extends StatelessWidget {
  const ShowdIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color = ShowdColors.paper,
    this.semanticLabel,
  });

  final ShowdIcons icon;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IconPainter(icon, color)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: child);
    return Semantics(label: semanticLabel, image: true, child: child);
  }
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.icon, this.color);
  final ShowdIcons icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    for (final data in icon.allPaths) {
      canvas.drawPath(svgPath(data), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}
