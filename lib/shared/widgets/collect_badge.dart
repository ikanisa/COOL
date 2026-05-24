import 'package:flutter/material.dart';

import 'collect_components.dart';

class CollectBadge extends StatelessWidget {
  const CollectBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CollectStatusChip(label: label, tone: CollectStatusTone.info);
  }
}
