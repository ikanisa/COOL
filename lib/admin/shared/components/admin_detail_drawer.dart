import 'package:flutter/material.dart';

class AdminDetailDrawer extends StatelessWidget {
  const AdminDetailDrawer({
    required this.title,
    required this.children,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 420,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}
