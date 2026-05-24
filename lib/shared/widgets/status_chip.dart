import 'package:flutter/material.dart';

import 'collect_components.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    this.tone = StatusTone.neutral,
    super.key,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    return CollectStatusChip(
      label: label,
      tone: switch (tone) {
        StatusTone.neutral => CollectStatusTone.neutral,
        StatusTone.good => CollectStatusTone.success,
        StatusTone.warning => CollectStatusTone.warning,
        StatusTone.danger => CollectStatusTone.danger,
      },
    );
  }
}

enum StatusTone { neutral, good, warning, danger }
