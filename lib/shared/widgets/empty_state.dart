import 'package:flutter/material.dart';

import 'collect_components.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CollectEmptyState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}
