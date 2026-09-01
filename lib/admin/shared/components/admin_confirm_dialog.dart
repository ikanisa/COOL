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
}) async {
  final returnFocus = FocusManager.instance.primaryFocus;
  final result = await showDialog<String>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (context) =>
        _AdminReasonDialog(title: title, actionLabel: actionLabel),
  );
  if (context.mounted && returnFocus != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (returnFocus.context != null && returnFocus.canRequestFocus) {
        returnFocus.requestFocus();
      }
    });
  }
  return result;
}

class _AdminReasonDialog extends StatefulWidget {
  const _AdminReasonDialog({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  State<_AdminReasonDialog> createState() => _AdminReasonDialogState();
}

class _AdminReasonDialogState extends State<_AdminReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Reason',
          helperText: 'Required for the audit trail.',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, child) {
            final reason = value.text.trim();
            return FilledButton(
              onPressed: reason.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(reason),
              child: Text(widget.actionLabel),
            );
          },
        ),
      ],
    );
  }
}
