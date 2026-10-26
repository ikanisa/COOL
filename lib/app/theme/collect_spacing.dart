import 'package:flutter/widgets.dart';

class CollectSpacing {
  const CollectSpacing._();

  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x7 = 28;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;

  static const double screenCompact = x4;
  static const double screen = x5;
  static const double cardCompact = x4;
  static const double card = x6;
  static const double iconTarget = 44;
  static const double target = 48;
  static const double metricCardWidth = 220;
  static const double contentMaxWidth = 840;

  static const gap4 = SizedBox(height: x1);
  static const gap8 = SizedBox(height: x2);
  static const gap12 = SizedBox(height: x3);
  static const gap16 = SizedBox(height: x4);
  static const gap20 = SizedBox(height: x5);
  static const gap24 = SizedBox(height: x6);
  static const gap32 = SizedBox(height: x8);

  static const gapW4 = SizedBox(width: x1);
  static const gapW8 = SizedBox(width: x2);
  static const gapW12 = SizedBox(width: x3);
  static const gapW16 = SizedBox(width: x4);

  static const screenPadding = EdgeInsets.all(screenCompact);
  static const screenPaddingWide = EdgeInsets.all(screen);
  static const cardPadding = EdgeInsets.all(cardCompact);
  static const cardPaddingComfortable = EdgeInsets.all(card);
}
