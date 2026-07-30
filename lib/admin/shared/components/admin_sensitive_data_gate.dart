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
  static const _revealReasons = <String>[
    'Support case review',
    'Compliance investigation',
    'Internal audit evidence',
  ];

  String? _selectedReason;
  String? _revealed;
  String? _error;
  var _isBusy = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Reveal only for support, compliance, or audit work. The reason is written to the audit trail.',
            ),
            const SizedBox(height: 12),
            Text(
              'Select an accountable purpose',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in _revealReasons)
                  ChoiceChip(
                    label: Text(reason),
                    selected: _selectedReason == reason,
                    onSelected: _isBusy
                        ? null
                        : (selected) {
                            setState(() {
                              _selectedReason = selected ? reason : null;
                              _error = null;
                            });
                          },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isBusy || _selectedReason == null
                  ? null
                  : () => _reveal(_selectedReason!),
              icon: const Icon(Icons.visibility),
              label: const Text('Reveal raw SMS'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                label: _error!,
                child: ExcludeSemantics(
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ],
            if (_revealed != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                label: 'Sensitive data revealed. ${_revealed!}',
                child: ExcludeSemantics(child: SelectableText(_revealed!)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reveal(String reason) async {
    if (_isBusy) return;
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
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
      final value = await widget.onReveal(normalizedReason);
      if (mounted) setState(() => _revealed = value);
    } catch (error) {
      if (mounted) setState(() => _error = adminSafeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }
}
