part of 'admin_runtime.dart';

class _GatewayEnrollmentDialog extends ConsumerStatefulWidget {
  const _GatewayEnrollmentDialog({required this.scope});
  final _AdminActionScope scope;
  @override
  ConsumerState<_GatewayEnrollmentDialog> createState() =>
      _GatewayEnrollmentDialogState();
}

class _GatewayEnrollmentDialogState
    extends ConsumerState<_GatewayEnrollmentDialog> {
  final _controller = TextEditingController();
  final _requestId = const Uuid().v4();
  AdminGatewayPublicIdentity? _identity;
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _review() {
    try {
      final identity = AdminGatewayPublicIdentity.parse(
        jsonDecode(_controller.text),
      );
      setState(() {
        _identity = identity;
        _error = null;
      });
    } catch (_) {
      setState(
        () => _error =
            'Paste the complete public identity from the Collect gateway. Its key and fingerprint must match.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => _AdminSessionDialog(
    scope: widget.scope,
    child: AlertDialog(
      title: const Text('Enroll SMS Gateway'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Review the public identity shown on the organization-owned handset. Enrollment records a pending device; it does not activate SMS dispatch.',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('gateway-public-identity'),
                controller: _controller,
                maxLength: 4096,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Handset public identity',
                  helperText:
                      'Paste the JSON from Public identity and enrollment.',
                ),
                onChanged: (_) => setState(() {
                  _identity = null;
                  _error = null;
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(_error!)),
              ],
              if (_identity case final identity?) ...[
                const SizedBox(height: 16),
                _GatewayEvidenceField(
                  'Installation ID',
                  identity.installationId,
                ),
                _GatewayEvidenceField(
                  'Public key fingerprint',
                  identity.keySha256,
                ),
                _GatewayEvidenceField(
                  'Signing certificate fingerprint',
                  identity.signingCertificateSha256,
                ),
                _GatewayEvidenceField('Request ID', _requestId),
                const Text(
                  'The backend validates this public key. Keep the request ID if the response is interrupted.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_identity == null)
          FilledButton(onPressed: _review, child: const Text('Review identity'))
        else
          FilledButton(
            onPressed: () {
              if (!widget.scope.isCurrent) return;
              Navigator.pop(
                context,
                AdminGatewayOwnerIntent.enroll(
                  requestId: _requestId,
                  identity: _identity!,
                ),
              );
            },
            child: const Text('Enroll pending device'),
          ),
      ],
    ),
  );
}

class _GatewayEvidenceField extends StatelessWidget {
  const _GatewayEvidenceField(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
}
