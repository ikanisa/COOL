import 'package:flutter/material.dart';

class AdminTimelineItem {
  const AdminTimelineItem({
    required this.title,
    required this.timestamp,
    this.subtitle,
  });

  final String title;
  final DateTime timestamp;
  final String? subtitle;
}

class AdminTimeline extends StatelessWidget {
  const AdminTimeline({required this.items, super.key});

  final List<AdminTimelineItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        'No timeline events',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            dense: true,
            leading: const Icon(Icons.circle, size: 10),
            title: Text(item.title),
            subtitle: Text(
              [
                _dateTime(item.timestamp),
                if (item.subtitle != null) item.subtitle!,
              ].join(' - '),
            ),
          ),
      ],
    );
  }
}

String _dateTime(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
