import 'package:flutter/material.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({required this.title, this.subtitle, this.child, super.key});

  final String title;
  final String? subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
        ],
        if (child != null) ...[const SizedBox(height: 16), child!],
      ],
    );
  }
}

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
