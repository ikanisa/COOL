import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/components/admin_data_listing.dart';
import 'admin_sender_retention_controller.dart';

class AdminSenderRetentionView extends StatefulWidget {
  const AdminSenderRetentionView({required this.controller, super.key});
  final AdminRetentionController controller;
  @override
  State<AdminSenderRetentionView> createState() => _ViewState();
}

class _ViewState extends State<AdminSenderRetentionView> {
  final _batch = TextEditingController(),
      _bytes = TextEditingController(),
      _reason = TextEditingController();
  bool _enabled = false;
  int? _revision;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(widget.controller.refresh());
  }

  @override
  void didUpdateWidget(AdminSenderRetentionView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _revision = null;
      _batch.clear();
      _bytes.clear();
      _reason.clear();
      _enabled = false;
      unawaited(widget.controller.refresh());
    }
  }

  void _changed() {
    if (!mounted) return;
    final s = widget.controller.snapshot;
    if (s == null) {
      _revision = null;
      _enabled = false;
      _batch.clear();
      _bytes.clear();
      _reason.clear();
    }
    if (s != null && s.revision != _revision) {
      _revision = s.revision;
      _enabled = s.configuration['enabled'] as bool;
      _batch.text = s.configuration['batch_limit'].toString();
      _bytes.text = s.configuration['byte_limit'].toString();
      _reason.clear();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    _batch.dispose();
    _bytes.dispose();
    _reason.dispose();
    super.dispose();
  }

  Widget _value(String label, String value) =>
      AdminDataFieldRow(label: label, value: value);
  @override
  Widget build(BuildContext context) {
    final c = widget.controller, s = c.snapshot;
    final fresh = s?.fresh(c.now()) ?? false;
    return AdminDataSection(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Evidence retention',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.loading ? null : c.refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Lossless maintenance moves eligible evidence to retained storage. It does not erase financial records or change receipt sending.',
            ),
            if (c.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Loading retention controls',
                ),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(c.error!)),
              ),
            if (s != null) ...[
              _value(
                'Database maintenance',
                (s.configuration['enabled'] as bool) ? 'Enabled' : 'Disabled',
              ),
              _value('Owned cron schedule', switch (s.cron['state']) {
                'active' => 'Active · every minute',
                'inactive' => 'Inactive · every minute',
                'absent' => 'No owned schedule recorded',
                _ => 'Unavailable',
              }),
              _value('Configuration revision', s.revision.toString()),
              _value(
                'Evidence holds',
                'Uncertain outcomes and late callback bindings remain protected. No cold expiry or raw financial erasure is authorized.',
              ),
              for (final key in ['scheduler', 'android'])
                _value(
                  key == 'scheduler'
                      ? 'Scheduler policy'
                      : 'Android archive policy',
                  (s.policies[key] as Map)['verification_state'] ==
                          'release_declared'
                      ? 'Release-declared · runtime observation unavailable'
                      : 'Unavailable',
                ),
              if (!fresh)
                const Text(
                  'This observation has expired. Refresh before changing controls.',
                ),
              if (!s.mutationAllowed)
                const Text(
                  'Current Settings manage permission is required to change maintenance.',
                ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable lossless maintenance'),
                subtitle: const Text(
                  'Future maintenance only; retained evidence and recovery remain available.',
                ),
                value: _enabled,
                onChanged: c.canApply
                    ? (v) => setState(() => _enabled = v)
                    : null,
              ),
              TextField(
                controller: _batch,
                enabled: c.canApply,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Batch limit',
                  helperText: '1–25 candidates per maintenance call',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bytes,
                enabled: c.canApply,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Byte limit',
                  helperText: '1–4,194,304 bytes per call',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: c.canApply,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Reason for change',
                  helperText:
                      '10–500 characters; recorded with the original request',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: c.canApply
                    ? () async {
                        final batch = int.tryParse(_batch.text),
                            bytes = int.tryParse(_bytes.text);
                        if (batch == null ||
                            bytes == null ||
                            batch < 1 ||
                            batch > 25 ||
                            bytes < 1 ||
                            bytes > 4194304 ||
                            _reason.text.trim() != _reason.text ||
                            _reason.text.runes.length < 10) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Enter limits within the shown ranges and a complete reason.',
                              ),
                            ),
                          );
                          return;
                        }
                        await c.apply(
                          enabled: _enabled,
                          batchLimit: batch,
                          byteLimit: bytes,
                          reason: _reason.text,
                        );
                      }
                    : null,
                child: const Text('Record maintenance change'),
              ),
            ],
            if (c.store == null)
              const Text(
                'Durable original-request storage is unavailable. Changes are disabled.',
              ),
            if (c.pending != null) ...[
              const SizedBox(height: 16),
              _value(
                'Original request awaiting recovery',
                c.pending!.requestId,
              ),
              OutlinedButton(
                onPressed: c.busy ? null : c.recover,
                child: const Text('Recover original request'),
              ),
            ],
            if (c.receipt != null)
              _value(
                'Original request result',
                c.receipt!.recorded ? 'Recorded' : 'Not recorded at lookup',
              ),
          ],
        ),
      ),
    );
  }
}
