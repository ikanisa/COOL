import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';

/// A plain Admin section for recorded data and its associated controls.
class AdminDataSection extends StatelessWidget {
  const AdminDataSection({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.collectColors.borderSoft),
        ),
      ),
      child: child,
    ),
  );
}

/// A Label/Value listing row that retains the complete recorded value.
class AdminDataFieldRow extends StatelessWidget {
  const AdminDataFieldRow({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.collectColors.textSecondary,
                ),
              ),
            ),
            SelectableText(value),
          ],
        ),
      ],
    ),
  );
}
