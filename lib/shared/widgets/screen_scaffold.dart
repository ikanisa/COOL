import 'package:flutter/material.dart';

import 'collect_components.dart';

class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffoldLayout(
      title: title,
      subtitle: subtitle,
      actions: actions,
      children: children,
    );
  }
}
