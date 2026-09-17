import 'dart:ui';

/// Parses SVG path data for the brand's own vector shapes.
///
/// Supports the absolute and relative M, L, H, V, C, Q, A and Z commands,
/// including implicit repeats. Parsed paths are cached by their source.
Path svgPath(String data) => _cache.putIfAbsent(data, () => _parse(data));

final _cache = <String, Path>{};
final _token = RegExp(
  r'[MmLlHhVvCcQqAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
);
final _command = RegExp(r'^[A-Za-z]$');

Path _parse(String data) {
  final tokens = _token.allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  String? cmd;
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  double n() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (_command.hasMatch(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd == null) {
      break;
    }
    switch (cmd) {
      case 'M' || 'm':
        final dx = n(), dy = n();
        x = cmd == 'm' ? x + dx : dx;
        y = cmd == 'm' ? y + dy : dy;
        path.moveTo(x, y);
        startX = x;
        startY = y;
        cmd = cmd == 'm' ? 'l' : 'L';
      case 'L' || 'l':
        final dx = n(), dy = n();
        x = cmd == 'l' ? x + dx : dx;
        y = cmd == 'l' ? y + dy : dy;
        path.lineTo(x, y);
      case 'H' || 'h':
        final dx = n();
        x = cmd == 'h' ? x + dx : dx;
        path.lineTo(x, y);
      case 'V' || 'v':
        final dy = n();
        y = cmd == 'v' ? y + dy : dy;
        path.lineTo(x, y);
      case 'C' || 'c':
        final rel = cmd == 'c';
        final x1 = n() + (rel ? x : 0), y1 = n() + (rel ? y : 0);
        final x2 = n() + (rel ? x : 0), y2 = n() + (rel ? y : 0);
        final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        path.cubicTo(x1, y1, x2, y2, ex, ey);
        x = ex;
        y = ey;
      case 'Q' || 'q':
        final rel = cmd == 'q';
        final x1 = n() + (rel ? x : 0), y1 = n() + (rel ? y : 0);
        final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        path.quadraticBezierTo(x1, y1, ex, ey);
        x = ex;
        y = ey;
      case 'A' || 'a':
        final rel = cmd == 'a';
        final rx = n(), ry = n(), rotation = n();
        final large = n() != 0, sweep = n() != 0;
        final ex = n() + (rel ? x : 0), ey = n() + (rel ? y : 0);
        path.arcToPoint(
          Offset(ex, ey),
          radius: Radius.elliptical(rx, ry),
          rotation: rotation,
          largeArc: large,
          clockwise: sweep,
        );
        x = ex;
        y = ey;
      case 'Z' || 'z':
        path.close();
        x = startX;
        y = startY;
      default:
        return path;
    }
  }
  return path;
}

/// Path data for a circle, for use alongside [svgPath].
String circlePath(double cx, double cy, double r) =>
    'M${cx - r} $cy a$r $r 0 1 0 ${2 * r} 0 a$r $r 0 1 0 ${-2 * r} 0Z';

/// Path data for an ellipse, for use alongside [svgPath].
String ellipsePath(double cx, double cy, double rx, double ry) =>
    'M${cx - rx} $cy a$rx $ry 0 1 0 ${2 * rx} 0 a$rx $ry 0 1 0 ${-2 * rx} 0Z';

/// Path data for a rounded rectangle, for use alongside [svgPath].
String rectPath(double x, double y, double w, double h, [double r = 0]) =>
    r <= 0
    ? 'M$x ${y}H${x + w}V${y + h}H${x}Z'
    : 'M${x + r} ${y}H${x + w - r}a$r $r 0 0 1 $r ${r}V${y + h - r}'
          'a$r $r 0 0 1 ${-r} ${r}H${x + r}a$r $r 0 0 1 ${-r} ${-r}'
          'V${y + r}a$r $r 0 0 1 $r ${-r}Z';
