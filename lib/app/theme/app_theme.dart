import 'package:flutter/material.dart';

import 'collect_theme.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => CollectTheme.light();
  static ThemeData dark() => CollectTheme.dark();
}
