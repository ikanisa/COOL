import 'package:flutter/material.dart';

class AdminActionItem {
  const AdminActionItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool destructive;
}

class AdminActionMenu extends StatelessWidget {
  const AdminActionMenu({
    required this.items,
    required this.onSelected,
    super.key,
  });

  final List<AdminActionItem> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          for (final item in items)
            PopupMenuItem(
              value: item.value,
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 18,
                    color: item.destructive
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(item.label),
                ],
              ),
            ),
        ];
      },
    );
  }
}
