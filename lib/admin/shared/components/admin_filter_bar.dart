import 'package:flutter/material.dart';

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    required this.searchController,
    required this.status,
    required this.onStatusChanged,
    required this.onRefresh,
    super.key,
  });

  final TextEditingController searchController;
  final String status;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: searchController,
            onSubmitted: (_) => onRefresh(),
            decoration: const InputDecoration(
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '', label: Text('All')),
            ButtonSegment(value: 'pending', label: Text('Pending')),
            ButtonSegment(value: 'active', label: Text('Active')),
            ButtonSegment(value: 'needs_review', label: Text('Review')),
          ],
          selected: {status},
          onSelectionChanged: (value) => onStatusChanged(value.single),
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}
