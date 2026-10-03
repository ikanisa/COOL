import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Widget Function(BuildContext, Widget)? dialogWrapper,
}) async {
  final returnFocus = FocusManager.instance.primaryFocus;
  final result = await showDialog<String>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (context) {
      final dialog = _AdminReasonDialog(title: title, actionLabel: actionLabel);
      return dialogWrapper?.call(context, dialog) ?? dialog;
    },
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
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, child) {
        final reason = value.text.trim();
        final count = reason.runes.length;
        final valid = count > 0 && count <= 1000;
        return AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: InputDecoration(
              labelText: 'Reason',
              helperText:
                  'Required for the audit trail. Up to 1000 characters.',
              counterText: '$count / 1000',
              errorText: count > 1000
                  ? 'Shorten the reason to 1000 characters.'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: !valid
                  ? null
                  : () => Navigator.of(context).pop(reason),
              child: Text(widget.actionLabel),
            ),
          ],
        );
      },
    );
  }
}
