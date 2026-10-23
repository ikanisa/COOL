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
  int minLength = 1,
  int maxLength = 1000,
  Widget Function(BuildContext, Widget)? dialogWrapper,
}) async {
  assert(minLength > 0 && maxLength >= minLength);
  final returnFocus = FocusManager.instance.primaryFocus;
  final result = await showDialog<String>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (context) {
      final dialog = _AdminReasonDialog(
        title: title,
        actionLabel: actionLabel,
        minLength: minLength,
        maxLength: maxLength,
      );
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
  const _AdminReasonDialog({
    required this.title,
    required this.actionLabel,
    required this.minLength,
    required this.maxLength,
  });

  final String title;
  final String actionLabel;
  final int minLength;
  final int maxLength;

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
        final valid = count >= widget.minLength && count <= widget.maxLength;
        return AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: widget.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            decoration: InputDecoration(
              labelText: 'Reason',
              helperText: widget.minLength == 1
                  ? 'Required for the audit trail. Up to ${widget.maxLength} characters.'
                  : 'Required for the audit trail. ${widget.minLength}–${widget.maxLength} characters.',
              counterText: '$count / ${widget.maxLength}',
              errorText: count > widget.maxLength
                  ? 'Shorten the reason to ${widget.maxLength} characters.'
                  : count > 0 && count < widget.minLength
                  ? 'Enter at least ${widget.minLength} characters.'
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
