import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/theme/collect_spacing.dart';
import '../shared/widgets/collect_chrome.dart';
import 'gateway_recovery_platform.dart';

class GatewayRecoveryPage extends StatefulWidget {
  const GatewayRecoveryPage({required this.platform, super.key});
  final GatewayRecoveryPlatform platform;
  @override
  State<GatewayRecoveryPage> createState() => _GatewayRecoveryPageState();
}

class _GatewayRecoveryPageState extends State<GatewayRecoveryPage> {
  final _digest = TextEditingController();
  GatewayRecoveryStatus? _status;
  Timer? _timer;
  bool _busy = false, _checking = true, _unavailable = false, _polling = false;
  bool _requestPending = false;
  int _revision = 0;
  bool get _validDigest => RegExp(r'^[0-9a-f]{64}$').hasMatch(_digest.text);
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_busy) {
      unawaited(
        widget.platform.cancel().then<void>((_) {}, onError: (Object _) {}),
      );
    }
    _digest.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_polling) return;
    _polling = true;
    final revision = _revision;
    try {
      final value = await widget.platform.status();
      if (!mounted || revision != _revision) return;
      setState(() {
        _status = value;
        _checking = false;
        _unavailable = false;
        _busy = value.working || _requestPending;
      });
      if (value.working) {
        _startPolling();
      } else {
        _timer?.cancel();
        _timer = null;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _unavailable = true;
        });
      }
    } finally {
      _polling = false;
    }
  }

  void _startPolling() {
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refresh(),
    );
  }

  Future<void> _run(Future<GatewayRecoveryStatus> Function() action) async {
    if (_busy || _checking || _unavailable) return;
    _revision++;
    _requestPending = true;
    setState(() {
      _busy = true;
      _unavailable = false;
      _status = null;
    });
    _startPolling();
    try {
      final value = await action();
      _revision++;
      _requestPending = false;
      if (mounted) {
        setState(() {
          _status = value;
          _busy = value.working;
        });
      }
    } catch (_) {
      _revision++;
      _requestPending = false;
      // An unknown reply is not permission to repeat an export/restore.
      if (mounted) {
        setState(() {
          _unavailable = true;
        });
      }
      await _refresh();
    } finally {
      if (mounted && !_busy) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  Future<void> _cancel() async {
    try {
      final value = await widget.platform.cancel();
      if (mounted) {
        setState(() {
          _status = value;
          _busy = value.working || _requestPending;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unavailable = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Journal recovery')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: CollectSpacing.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CollectHeadingText(
                    title: 'Preserve gateway evidence',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: CollectSpacing.x2),
                  const Text(
                    'Export encrypted journal evidence during an emergency pause. Keep the archive and its manifest fingerprint in approved separate custody.',
                  ),
                  const SizedBox(height: CollectSpacing.x4),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(CollectSpacing.x4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Encrypted archive',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: CollectSpacing.x2),
                          const Text(
                            'A durable local pause is required. Snapshotting can delay callbacks. Dispatch stays paused after export.',
                          ),
                          const SizedBox(height: CollectSpacing.x4),
                          OutlinedButton.icon(
                            onPressed: _busy || _checking || _unavailable
                                ? null
                                : () => _run(widget.platform.export),
                            icon: const Icon(Icons.file_upload_outlined),
                            label: const Text('Export journal archive'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CollectSpacing.x4),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(CollectSpacing.x4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Inactive recovery',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: CollectSpacing.x2),
                          const Text(
                            'Choose an archive and provide its trusted manifest fingerprint. Recovery creates separate inactive evidence. It cannot activate a sender. Validation requires the original Android storage key; another device cannot decrypt this archive.',
                          ),
                          const SizedBox(height: CollectSpacing.x4),
                          TextField(
                            controller: _digest,
                            enabled: !_busy,
                            maxLength: 64,
                            onChanged: (_) => setState(() {}),
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: const InputDecoration(
                              labelText: 'Trusted manifest SHA256',
                              helperText: '64 lowercase hexadecimal characters',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _busy ||
                                    _checking ||
                                    _unavailable ||
                                    !_validDigest
                                ? null
                                : () => _run(
                                    () => widget.platform.restore(_digest.text),
                                  ),
                            icon: const Icon(Icons.file_download_outlined),
                            label: const Text('Restore inactive evidence'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: CollectSpacing.x4),
                  if (_busy || _checking) ...[
                    Semantics(
                      label: _checking
                          ? 'Checking recovery status'
                          : 'Recovery in progress',
                      liveRegion: true,
                      child: const LinearProgressIndicator(),
                    ),
                    const SizedBox(height: CollectSpacing.x2),
                    Text(_phase(value)),
                    if (_busy)
                      TextButton(
                        onPressed: _cancel,
                        child: const Text('Cancel recovery'),
                      ),
                  ],
                  if (_unavailable) ...[
                    const Text(
                      'Recovery status is unavailable. Check the current operation before trying again.',
                    ),
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('Check recovery status'),
                    ),
                  ],
                  if (value?.state == 'complete') ...[
                    CollectHeadingText(
                      title: value!.operation == 'export'
                          ? 'Archive exported and read back'
                          : 'Inactive evidence retained',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('${value.files} ciphertext files'),
                    if (value.operation == 'restore')
                      Text(
                        value.keyValidated == true
                            ? 'Validated with the existing storage key. Sender authority remains inactive; re-enrollment is required.'
                            : 'Storage key unavailable. Opaque ciphertext retained; contents are not validated. Sender authority remains inactive.',
                      ),
                    const SizedBox(height: CollectSpacing.x2),
                    const Text('Manifest SHA256'),
                    SelectableText(value.manifestSha256!),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: value.manifestSha256!),
                      ),
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy manifest fingerprint'),
                    ),
                  ],
                  if (value?.state == 'cancelled')
                    const Text(
                      'Recovery cancelled. Any partial evidence remains in private quarantine. Dispatch authority is unchanged.',
                    ),
                  if (value?.state == 'failed')
                    Text(
                      value?.reasonCode == 'gateway_recovery_pause_required'
                          ? 'Turn on Emergency pause and check it before exporting.'
                          : 'Recovery could not be completed. Retained evidence stays inactive. Investigate before selecting another archive.',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _phase(GatewayRecoveryStatus? value) => switch (value?.phase) {
    'picker' => 'Choose an archive location in the Android file picker.',
    'snapshot' => 'Preserving the encrypted journal snapshot.',
    'writing' => 'Writing ${value!.completedFiles} ciphertext files.',
    'verifying' => 'Reading back the exported archive.',
    'reading' =>
      'Reading ${value!.completedFiles} ciphertext files into quarantine.',
    'validating' => 'Validating separate inactive evidence.',
    _ => 'Preparing recovery.',
  };
}
