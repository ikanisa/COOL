import 'package:flutter/material.dart';

import '../../../app/theme/collect_motion.dart';

class AdminConfirmDialog extends StatelessWidget {
  const AdminConfirmDialog({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(title: Text(title));
  }
}

Future<String?> showAdminReasonDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              Navigator.of(context).pop(reason.isEmpty ? null : reason);
            },
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
}
