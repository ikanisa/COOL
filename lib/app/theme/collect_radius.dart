import 'package:flutter/material.dart';

class CollectRadius {
  const CollectRadius._();

  static const double sm = 2;
  static const double md = 4;
  static const double card = 8;
  static const double cardLarge = 8;
  static const double bottomSheet = 8;
  static const double pill = 999;

  static BorderRadius get smBorder => BorderRadius.circular(sm);
  static BorderRadius get mdBorder => BorderRadius.circular(md);
  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get cardLargeBorder => BorderRadius.circular(cardLarge);
  static BorderRadius get pillBorder => BorderRadius.circular(pill);
}
