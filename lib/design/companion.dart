import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/pet.dart';
import 'svg_path.dart';
import 'tokens.dart';

/// How the companion looks today. It never punishes: after a miss it looks
/// determined, and when you come back it wears a bandage.
enum CompanionMood { happy, steady, determined, resting, comeback }

CompanionMood companionMoodFor(PetMood mood, {bool resting = false}) {
  if (resting) return CompanionMood.resting;
  return switch (mood) {
    PetMood.happy => CompanionMood.happy,
    PetMood.uneasy => CompanionMood.steady,
    PetMood.sad || PetMood.cracked => CompanionMood.determined,
    PetMood.recovery => CompanionMood.comeback,
  };
}

/// The dot companion (free) or an illustrated animal (Pro).
class CompanionView extends StatelessWidget {
  const CompanionView({
    super.key,
    this.mascot = MascotId.dot,
    this.mood = CompanionMood.happy,
    this.size = 64,
  });

  final MascotId mascot;
  final CompanionMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${mascot.label} companion, ${mood.name}',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: CompanionPainter(mascot, mood)),
    ),
  );
}

class CompanionPainter extends CustomPainter {
  const CompanionPainter(this.mascot, this.mood);
  final MascotId mascot;
  final CompanionMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (mascot == MascotId.dot) {
      canvas.scale(size.width / 120, size.height / 120);
      _paintDot(canvas, mood);
    } else {
      canvas.scale(size.width / 160, size.height / 160);
      _paintAnimal(canvas, mascot, mood);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CompanionPainter old) =>
      old.mascot != mascot || old.mood != mood;
}

const _ink = ShowdColors.ink;
const _paper = ShowdColors.paper;
const _stone = ShowdColors.stone;
const _graphite = ShowdColors.graphiteStrong;

void _fill(Canvas c, String d, Color color) =>
    c.drawPath(svgPath(d), Paint()..color = color);

void _stroke(Canvas c, String d, Color color, double width) => c.drawPath(
  svgPath(d),
  Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color,
);

void _circle(Canvas c, double x, double y, double r, Color color) =>
    c.drawCircle(Offset(x, y), r, Paint()..color = color);

void _ellipse(
  Canvas c,
  double cx,
  double cy,
  double rx,
  double ry,
  Color color, [
  double rotateDegrees = 0,
]) {
  c.save();
  c.translate(cx, cy);
  if (rotateDegrees != 0) c.rotate(rotateDegrees * math.pi / 180);
  c.drawOval(
    Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
    Paint()..color = color,
  );
  c.restore();
}

void _rrect(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
  double r,
  Color color,
) => c.drawRRect(
  RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
  Paint()..color = color,
);

// Dot companion, 120 unit grid.
void _paintDot(Canvas c, CompanionMood mood) {
  _circle(c, 60, 48, 22, ShowdColors.accent);
  switch (mood) {
    case CompanionMood.happy:
      _stroke(c, 'M47 49q5-6 10 0M63 49q5-6 10 0', _ink, 3);
    case CompanionMood.steady:
      _circle(c, 52, 48, 3, _ink);
      _circle(c, 68, 48, 3, _ink);
    case CompanionMood.determined:
      _circle(c, 52, 48, 3, _ink);
      _circle(c, 68, 48, 3, _ink);
      _stroke(c, 'M45 41L56 44M75 41L64 44', _ink, 2.6);
    case CompanionMood.resting:
      _stroke(c, 'M47 49H57M63 49H73', _ink, 3);
      _stroke(c, 'M88 20h8l-8 8h8M99 7h6l-6 6h6', _stone, 2.2);
    case CompanionMood.comeback:
      _circle(c, 52, 48, 3, _ink);
      _circle(c, 68, 48, 3, _ink);
      c.save();
      c.translate(70, 34);
      c.rotate(-24 * math.pi / 180);
      c.translate(-70, -34);
      _rrect(c, 60, 30, 20, 8, 3, _paper);
      _circle(c, 67, 34, 1.1, _stone);
      _circle(c, 73, 34, 1.1, _stone);
      c.restore();
  }
  _stroke(
    c,
    mood == CompanionMood.resting
        ? 'M38 84V86a22 12 0 0 0 44 0V84'
        : 'M38 80V86a22 22 0 0 0 44 0V80',
    _paper,
    9,
  );
}

// Illustrated animals, 160 unit grid. Each carries one accent detail.
void _paintAnimal(Canvas c, MascotId mascot, CompanionMood mood) {
  final face = switch (mood) {
    CompanionMood.determined => _Face.determined,
    CompanionMood.resting => _Face.resting,
    _ => _Face.happy,
  };
  switch (mascot) {
    case MascotId.fox:
      _fill(c, 'M40 70L36 22L72 50ZM120 70L124 22L88 50Z', _stone);
      _fill(c, 'M46 60L43 34L64 50ZM114 60L117 34L96 50Z', _graphite);
      _fill(
        c,
        'M80 128L40 94C30 76 34 58 50 50C60 45 70 46 80 52C90 46 100 45 110 50C126 58 130 76 120 94Z',
        _stone,
      );
      _fill(
        c,
        'M80 128L50 102C44 96 42 90 44 84C56 86 70 94 80 106C90 94 104 86 116 84C118 90 116 96 110 102Z',
        _paper,
      );
      _ellipse(c, 80, 120, 7, 5, _ink);
      _eyes(c, face, lx: 62, rx: 98, y: 82);
      _fill(
        c,
        'M50 136C62 144 98 144 110 136L110 146C98 154 62 154 50 146Z',
        ShowdColors.accent,
      );
      _fill(c, 'M96 146L110 159L93 156Z', ShowdColors.accentDeep);
    case MascotId.cat:
      _fill(c, 'M40 78L44 30L76 58ZM120 78L116 30L84 58Z', _graphite);
      _fill(c, 'M48 68L50 42L68 58ZM112 68L110 42L92 58Z', _stone);
      _ellipse(c, 80, 92, 48, 42, _graphite);
      _ellipse(c, 80, 112, 20, 14, _paper);
      _fill(c, 'M74 104H86L80 111Z', _ink);
      switch (face) {
        case _Face.happy:
          _stroke(c, 'M52 90q8-9 16 0M92 90q8-9 16 0', ShowdColors.accent, 4);
        case _Face.determined:
          _ellipse(c, 60, 88, 9, 7, ShowdColors.accent);
          _ellipse(c, 100, 88, 9, 7, ShowdColors.accent);
          _ellipse(c, 60, 88, 2.5, 6, _ink);
          _ellipse(c, 100, 88, 2.5, 6, _ink);
          _stroke(c, 'M48 75L68 80M112 75L92 80', _paper, 3.5);
        case _Face.resting:
          _stroke(c, 'M51 90H69M91 90H109', ShowdColors.accent, 4);
          _zzz(c);
      }
      _stroke(
        c,
        'M28 106H56M28 116L56 112M132 106H104M132 116L104 112',
        _paper,
        2.5,
      );
    case MascotId.puppy:
      _ellipse(c, 80, 84, 42, 40, _paper);
      _ellipse(c, 98, 80, 13, 12, const Color(0xFFDCD6CA));
      _fill(c, 'M40 56C22 60 18 96 30 112C40 116 50 100 52 80Z', _stone);
      _fill(c, 'M120 56C138 60 142 96 130 112C120 116 110 100 108 80Z', _stone);
      _ellipse(c, 80, 104, 20, 15, const Color(0xFFE4DFD4));
      _ellipse(c, 80, 98, 8, 6, _ink);
      _stroke(c, 'M80 104V110M72 112q8 6 16 0', _ink, 2.5);
      _eyes(c, face, lx: 64, rx: 96, y: 80);
      _fill(
        c,
        'M48 124C62 132 98 132 112 124L112 132C98 140 62 140 48 132Z',
        _graphite,
      );
      _circle(c, 80, 143, 8, ShowdColors.accent);
    case MascotId.penguin:
      _stroke(c, 'M74 34C70 22 82 16 86 26', _graphite, 5);
      _circle(c, 80, 84, 54, _graphite);
      _fill(
        c,
        'M80 132C52 132 36 112 40 86C44 66 60 58 80 72C100 58 116 66 120 86C124 112 108 132 80 132Z',
        _paper,
      );
      _fill(c, 'M70 100H90L80 112Z', ShowdColors.accent);
      _eyes(c, face, lx: 64, rx: 96, y: 88);
    case MascotId.capybara:
      _circle(c, 46, 54, 10, _stone);
      _circle(c, 46, 54, 5, _graphite);
      _circle(c, 114, 54, 10, _stone);
      _circle(c, 114, 54, 5, _graphite);
      _rrect(c, 34, 50, 92, 84, 38, _stone);
      _rrect(c, 50, 98, 60, 32, 16, const Color(0xFF6E6A62));
      _ellipse(c, 68, 108, 3, 2, _ink);
      _ellipse(c, 92, 108, 3, 2, _ink);
      _stroke(c, 'M74 120q6 4 12 0', _ink, 2.5);
      _eyes(c, face, lx: 62, rx: 98, y: 82, r: 3.5, w: 12);
      _fill(
        c,
        'M80 50C66 34 78 18 98 18C100 36 92 50 80 50Z',
        ShowdColors.accent,
      );
      _stroke(c, 'M80 50C86 40 90 32 96 22', ShowdColors.accentDeep, 2.5);
    case MascotId.dot:
      break;
  }
}

enum _Face { happy, determined, resting }

void _eyes(
  Canvas c,
  _Face face, {
  required double lx,
  required double rx,
  required double y,
  double r = 4.5,
  double w = 14,
}) {
  switch (face) {
    case _Face.happy:
      _stroke(
        c,
        'M${lx - w / 2} ${y + 2}q${w / 2} -8 $w 0M${rx - w / 2} ${y + 2}q${w / 2} -8 $w 0',
        _ink,
        3.5,
      );
    case _Face.determined:
      _circle(c, lx, y, r, _ink);
      _circle(c, rx, y, r, _ink);
      _stroke(
        c,
        'M${lx - 10} ${y - 12}L${lx + 8} ${y - 8}M${rx + 10} ${y - 12}L${rx - 8} ${y - 8}',
        _ink,
        3.5,
      );
    case _Face.resting:
      _stroke(
        c,
        'M${lx - w / 2} ${y + 2}H${lx + w / 2}M${rx - w / 2} ${y + 2}H${rx + w / 2}',
        _ink,
        3.5,
      );
      _zzz(c);
  }
}

void _zzz(Canvas c) =>
    _stroke(c, 'M128 26h10l-10 10h10M142 10h7l-7 7h7', _stone, 3);
