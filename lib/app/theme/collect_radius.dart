import 'package:flutter/material.dart';

class CollectRadius {
  const CollectRadius._();

  static const double sm = 4;
  static const double md = 8;
  static const double control = 8;
  static const double panel = 16;
  static const double card = 16;
  static const double cardLarge = 24;
  static const double bottomSheet = 28;
  static const double pill = 999;

  static BorderRadius get smBorder => BorderRadius.circular(sm);
  static BorderRadius get mdBorder => BorderRadius.circular(md);
  static BorderRadius get controlBorder => BorderRadius.circular(control);
  static BorderRadius get panelBorder => BorderRadius.circular(panel);
  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get cardLargeBorder => BorderRadius.circular(cardLarge);
  static BorderRadius get pillBorder => BorderRadius.circular(pill);
}
