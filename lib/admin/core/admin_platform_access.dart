part of 'admin_runtime.dart';

/// Platform-only controls. Group ownership and membership do not use this gate.
class AdminPlatformAccessPanel extends ConsumerStatefulWidget {
  const AdminPlatformAccessPanel({required this.userId, super.key});
  final String userId;

  @override
  ConsumerState<AdminPlatformAccessPanel> createState() =>
      _AdminPlatformAccessPanelState();
}

class _AdminPlatformAccessPanelState
    extends ConsumerState<AdminPlatformAccessPanel> {
  Future<Map<String, dynamic>>? _snapshot;
  bool _busy = false;
  bool _saving = false;
  String? _error;

  @override
  void didUpdateWidget(covariant AdminPlatformAccessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _snapshot = null;
      _error = null;
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final target = widget.userId;
    final result = await ref.read(adminRepositoryProvider).action(
      'admin_get_whatsapp_approval',
      {'p_user_id': target},
    );
    if (result['user_id'] != target ||
        result['approved'] is! bool ||
        result['role_granted'] is! bool) {
      throw const FormatException('Invalid platform access response');
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    if (!_adminHasPermission(identity, 'admin_users.read')) {
      return const SizedBox.shrink();
    }
    _snapshot ??= _load();
    return FutureBuilder<Map<String, dynamic>>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Semantics(
            label: 'Loading platform Admin access',
            child: const LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Platform access could not be loaded.'),
              TextButton(
                onPressed: () => setState(() {
                  _snapshot = _load();
                }),
                child: const Text('Retry'),
              ),
            ],
          );
        }
        final data = snapshot.data!;
        final approved = data['approved'] == true;
        final granted = data['role_granted'] == true;
        final canManage = _adminHasPermission(identity, 'admin_users.manage');
        final ownAccount = identity?.userId == widget.userId;
        final approvalLabel = switch (data['status']) {
          'approved' => granted ? 'Active' : 'Awaiting activation',
          'expired' => 'Approval expired',
          'identity_changed' => 'Identity needs review',
          'revoked' => 'Approval revoked',
          _ => 'WhatsApp approval required',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Platform Admin',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                AdminStatusChip(label: approvalLabel),
              ],
            ),
            if ('${data['phone_masked'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${data['phone_masked']}'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
            if (canManage && ownAccount) ...[
              const SizedBox(height: 12),
              const Text('Changes require another Admin.'),
            ],
            if (canManage && !ownAccount) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _change(
                            !approved
                                ? 'approve'
                                : granted
                                ? 'deactivate'
                                : 'activate',
                          ),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            !approved
                                ? Icons.verified_user_outlined
                                : granted
                                ? Icons.person_remove_outlined
                                : Icons.person_add_alt_1_outlined,
                          ),
                    label: Text(
                      !approved
                          ? 'Approve WhatsApp'
                          : granted
                          ? 'Deactivate Admin'
                          : 'Activate Admin',
                    ),
                  ),
                  if (approved)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _change('revoke'),
                      child: const Text('Revoke approval'),
                    ),
                  if (!approved && granted)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _change('deactivate'),
                      child: const Text('Deactivate Admin'),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _change(String operation) async {
    if (_busy) return;
    final target = widget.userId;
    final operatorId = ref.read(adminIdentityProvider).valueOrNull?.userId;
    final repository = ref.read(adminRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await showDialog<_PlatformAccessRequest>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (_) => _PlatformAccessDialog(operation: operation),
      );
      if (!mounted || request == null || widget.userId != target) return;
      setState(() => _saving = true);
      final actor = await repository.currentIdentity();
      if (!mounted || widget.userId != target) return;
      if (actor?.userId != operatorId ||
          !_adminHasPermission(actor, 'admin_users.manage')) {
        throw StateError('Admin session changed');
      }
      final approving = operation == 'approve';
      final revoking = operation == 'revoke';
      final active = operation == 'activate';
      final result = await repository.action(
        approving
            ? 'admin_approve_whatsapp'
            : revoking
            ? 'admin_revoke_whatsapp_approval'
            : 'admin_set_user_access',
        {
          'p_user_id': target,
          'p_reason': request.reason,
          if (approving) 'p_whatsapp_phone': request.phone,
          if (!approving && !revoking) 'p_active': active,
        },
      );
      final status = approving
          ? 'approved'
          : active
          ? 'active'
          : 'revoked';
      // Never show success for an empty, rejected or wrong-account receipt.
      if (result['ok'] != true ||
          result['status'] != status ||
          result.length != (approving || revoking ? 3 : 2) ||
          ((approving || revoking) && result['user_id'] != target)) {
        throw const FormatException('Unconfirmed Admin access change');
      }
      if (!mounted || widget.userId != target) return;
      setState(() {
        _snapshot = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approving
                ? 'WhatsApp approved. A new sign-in is required.'
                : revoking
                ? 'Approval and platform access revoked.'
                : active
                ? 'Platform Admin access activated.'
                : 'Platform Admin access deactivated.',
          ),
        ),
      );
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
    } catch (_) {
      if (mounted && widget.userId == target) {
        setState(() {
          _error = 'Change not confirmed. Refresh access before trying again.';
          _snapshot = _load();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }
}

class _PlatformAccessRequest {
  const _PlatformAccessRequest(this.reason, this.phone);
  final String reason;
  final String phone;
}

class _PlatformAccessDialog extends StatefulWidget {
  const _PlatformAccessDialog({required this.operation});
  final String operation;
  @override
  State<_PlatformAccessDialog> createState() => _PlatformAccessDialogState();
}

class _PlatformAccessDialogState extends State<_PlatformAccessDialog> {
  final _phone = TextEditingController();
  final _reason = TextEditingController();
  @override
  void dispose() {
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final approving = widget.operation == 'approve';
    final title = switch (widget.operation) {
      'approve' => 'Approve WhatsApp',
      'revoke' => 'Revoke approval',
      'activate' => 'Activate Admin',
      _ => 'Deactivate Admin',
    };
    final valid =
        _reason.text.trim().isNotEmpty &&
        _reason.text.trim().length <= 1000 &&
        (!approving ||
            RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_phone.text.trim()));
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Platform Admin only. Group roles stay unchanged.'),
            if (approving) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 16,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Verified WhatsApp number',
                  hintText: '+250…',
                  helperText: 'Must match this account’s verified number.',
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              autofocus: !approving,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Reason',
                counterText: '',
              ),
            ),
          ],
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
              : () => Navigator.of(context).pop(
                  _PlatformAccessRequest(
                    _reason.text.trim(),
                    _phone.text.trim(),
                  ),
                ),
          child: Text(title),
        ),
      ],
    );
  }
}
