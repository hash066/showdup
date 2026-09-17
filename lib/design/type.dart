import 'package:flutter/painting.dart';

import 'tokens.dart';

/// ShowdUp type scale. Big Shoulders Display carries numbers and one-word
/// shouts; Bricolage Grotesque carries everything else.
class ShowdType {
  ShowdType._();

  static const display = 'BigShoulders';
  static const text = 'Bricolage';
  static const _tabular = [FontFeature.tabularFigures()];

  static const numeralXL = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w800,
    fontSize: 120,
    height: .85,
    letterSpacing: .5,
    fontFeatures: _tabular,
    color: ShowdColors.paper,
  );
  static const numeralL = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w800,
    fontSize: 96,
    height: .85,
    letterSpacing: .5,
    fontFeatures: _tabular,
    color: ShowdColors.paper,
  );
  static const numeralM = TextStyle(
    fontFamily: display,
    fontWeight: FontWeight.w800,
    fontSize: 64,
    height: .9,
    letterSpacing: .5,
    fontFeatures: _tabular,
    color: ShowdColors.paper,
  );
  static const hero = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w700,
    fontSize: 42,
    height: 1.02,
    letterSpacing: -1.2,
    color: ShowdColors.paper,
  );
  static const titleXL = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w700,
    fontSize: 32,
    height: 1.1,
    letterSpacing: -.8,
    color: ShowdColors.paper,
  );
  static const titleL = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w700,
    fontSize: 28,
    height: 1.1,
    letterSpacing: -.5,
    color: ShowdColors.paper,
  );
  static const titleM = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w700,
    fontSize: 22,
    height: 1.15,
    letterSpacing: -.3,
    color: ShowdColors.paper,
  );
  static const bodyL = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 1.5,
    color: ShowdColors.paper,
  );
  static const bodyM = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 1.45,
    color: ShowdColors.stone,
  );
  static const label = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 1.4,
    color: ShowdColors.stone,
  );
  static const caption = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 1.45,
    color: ShowdColors.stone,
  );
  static const button = TextStyle(
    fontFamily: text,
    fontWeight: FontWeight.w700,
    fontSize: 17,
    height: 1.2,
  );
}
