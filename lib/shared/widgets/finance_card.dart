import 'package:flutter/material.dart';

import 'collect_components.dart';

class FinanceCard extends StatelessWidget {
  const FinanceCard({required this.child, this.padding, this.onTap, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      onTap: onTap,
      padding: padding ?? CollectSpacing.cardPadding,
      child: child,
    );
  }
}
