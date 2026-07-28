import 'package:flutter/material.dart';

import '../../core/admin_error_boundary.dart';

class AdminSensitiveDataGate extends StatefulWidget {
  const AdminSensitiveDataGate({
    required this.label,
    required this.onReveal,
    super.key,
  });

  final String label;
  final Future<String> Function(String reason) onReveal;

  @override
  State<AdminSensitiveDataGate> createState() => _AdminSensitiveDataGateState();
}

class _AdminSensitiveDataGateState extends State<AdminSensitiveDataGate> {
  final _reason = TextEditingController();
  String? _revealed;
  String? _error;
  var _isBusy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${widget.label} sensitive data reveal gate',
      hint: 'Requires an audit reason before revealing sensitive admin data.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Reveal only for support, compliance, or audit work. The reason is written to the audit trail.',
              ),
              const SizedBox(height: 12),
              Semantics(
                textField: true,
                label: '${widget.label} reveal reason',
                hint:
                    'Audit reason required before this sensitive value can be revealed.',
                child: TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reveal reason',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Reveal ${widget.label}',
                hint:
                    'Reveals sensitive data after recording the entered audit reason.',
                enabled: !_isBusy,
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : _reveal,
                  icon: const Icon(Icons.visibility),
                  label: const Text('Reveal raw SMS'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (_revealed != null) ...[
                const SizedBox(height: 12),
                SelectableText(_revealed!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reveal() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter a reason before revealing sensitive data.',
      );
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final value = await widget.onReveal(reason);
      if (mounted) setState(() => _revealed = value);
    } catch (error) {
      if (mounted) setState(() => _error = adminSafeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
