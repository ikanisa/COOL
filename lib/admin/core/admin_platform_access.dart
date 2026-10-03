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
  Future<AdminOperatorApproval>? _snapshot;
  bool _busy = false;
  bool _saving = false;
  String? _error;
  Object? _snapshotScope;

  @override
  void didUpdateWidget(covariant AdminPlatformAccessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _snapshot = null;
      _error = null;
    }
  }

  Future<AdminOperatorApproval> _load() async {
    final target = widget.userId;
    final scope = _AdminActionScope(ref);
    if (!scope.isCurrent) throw const AdminSessionChanged();
    final result = await scope.repository.action(
      'admin_get_operator_approval_v1',
      {'p_user_id': target},
    );
    if (!scope.isCurrent || widget.userId != target) {
      throw const AdminSessionChanged();
    }
    return AdminOperatorApproval.parse(result, targetUserId: target);
  }

  @override
  Widget build(BuildContext context) {
    final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
    if (!_adminHasPermission(identity, 'admin_users.read')) {
      return const SizedBox.shrink();
    }
    final snapshotScope = (
      ref.watch(adminAuthSessionScopeProvider),
      widget.userId,
      ref.watch(adminRealtimeTickProvider),
      ref.watch(adminRepositoryProvider),
      ref.watch(_adminIdentityRevisionProvider),
    );
    if (_snapshotScope != snapshotScope) {
      _snapshotScope = snapshotScope;
      _snapshot = null;
      _error = null;
    }
    _snapshot ??= _load();
    return FutureBuilder<AdminOperatorApproval>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Semantics(
            label: 'Loading platform Admin access',
            child: const LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = switch (error) {
            AdminSessionChanged() =>
              'Your Admin session changed. Reopen this page to view access.',
            PostgrestException(code: '42501') || AuthException() =>
              'Platform access is denied for this Admin session.',
            UnsupportedError() ||
            PostgrestException(
              code: 'PGRST202' || '42883',
            ) => 'Operator approval service is unavailable.',
            _ => 'Platform access could not be loaded.',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(liveRegion: true, child: Text(message)),
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
        final approved = data.approved;
        final granted = data.roleGranted;
        final legacy = data.legacyControls;
        final canManage = _adminHasPermission(identity, 'admin_users.manage');
        final ownAccount = identity?.userId == widget.userId;
        final approvalLabel = switch (data.status) {
          'approved' => granted ? 'Active' : 'Awaiting activation',
          'expired' => 'Approval expired',
          'identity_changed' => 'Identity needs review',
          'revoked' => 'Approval revoked',
          'pending_verification' => 'Email verification required',
          'legacy_disabled' => 'Legacy sign in disabled',
          _ =>
            legacy ? 'WhatsApp approval required' : 'Email approval required',
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
                AdminStatusChip(
                  label: approvalLabel,
                  tone: approved
                      ? (granted
                            ? CollectStatusTone.success
                            : CollectStatusTone.info)
                      : CollectStatusTone.warning,
                ),
              ],
            ),
            if (data.identityMasked != null) ...[
              const SizedBox(height: 8),
              Text(
                '${data.provider == 'email' ? 'Email' : 'WhatsApp'}: ${data.identityMasked}',
              ),
            ],
            if (data.approvedAt != null) ...[
              const SizedBox(height: 8),
              Text('Approved at: ${adminKigaliDateTime(data.approvedAt)}'),
            ],
            if (data.expiresAt != null) ...[
              const SizedBox(height: 4),
              Text('Approval expires: ${adminKigaliDateTime(data.expiresAt)}'),
            ],
            if (data.status == 'pending_verification' ||
                data.status == 'legacy_disabled') ...[
              const SizedBox(height: 8),
              const Text(
                'The existing account must verify its email before email approval. This does not create an account.',
              ),
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
                                ? (legacy
                                      ? 'approve_whatsapp'
                                      : 'approve_email')
                                : granted
                                ? 'deactivate'
                                : 'activate',
                          ),
                    icon: _saving
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.collectColors.textMuted,
                            ),
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
                          ? (legacy ? 'Approve WhatsApp' : 'Approve email')
                          : granted
                          ? 'Deactivate Admin'
                          : 'Activate Admin',
                    ),
                  ),
                  if (approved)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _change(
                              legacy ? 'revoke_whatsapp' : 'revoke_email',
                            ),
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
    final scope = _AdminActionScope(ref);
    final target = widget.userId;
    final operatorId = _adminResolvedIdentity(
      ref.read(adminIdentityProvider),
    )?.userId;
    final repository = scope.repository;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await showDialog<_PlatformAccessRequest>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (_) => _AdminSessionDialog(
          scope: scope,
          child: _PlatformAccessDialog(operation: operation),
        ),
      );
      if (!mounted ||
          request == null ||
          widget.userId != target ||
          !scope.isCurrent) {
        return;
      }
      setState(() => _saving = true);
      final actor = await repository.currentIdentity();
      if (!mounted || widget.userId != target || !scope.isCurrent) return;
      if (actor?.userId != operatorId ||
          !_adminHasPermission(actor, 'admin_users.manage')) {
        throw StateError('Admin session changed');
      }
      if (actor?.userId == target) {
        throw StateError('Another Admin must make this change');
      }
      final approving = operation.startsWith('approve_');
      final revoking = operation.startsWith('revoke_');
      final email = operation.endsWith('_email');
      final active = operation == 'activate';
      final current = await _load();
      if (!mounted || widget.userId != target || !scope.isCurrent) return;
      if (((approving || revoking) &&
              (email ? current.legacyControls : !current.legacyControls)) ||
          (active && !current.approved)) {
        throw StateError('Operator approval changed during this intent');
      }
      final result = await repository.action(
        approving
            ? (email
                  ? 'admin_approve_email_operator_v1'
                  : 'admin_approve_whatsapp')
            : revoking
            ? (email
                  ? 'admin_revoke_email_operator_v1'
                  : 'admin_revoke_whatsapp_approval')
            : 'admin_set_user_access',
        {
          'p_user_id': target,
          'p_reason': request.reason,
          if (approving)
            if (email)
              'p_email': request.identity
            else
              'p_whatsapp_phone': request.identity,
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
      if (!mounted || widget.userId != target || !scope.isCurrent) return;
      setState(() {
        _snapshot = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approving
                ? '${email ? 'Email' : 'WhatsApp'} approved. A new sign-in is required.'
                : revoking
                ? 'Approval and platform access revoked.'
                : active
                ? 'Platform Admin access activated.'
                : 'Platform Admin access deactivated.',
          ),
        ),
      );
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
    } catch (error) {
      if (mounted && widget.userId == target && scope.isCurrent) {
        setState(() {
          _error = error is PostgrestException && error.code == '42501'
              ? 'Change denied. Confirm the target’s verified email and your current approval and permission.'
              : 'Change not confirmed. Refresh access before trying again.';
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
  const _PlatformAccessRequest(this.reason, this.identity);
  final String reason;
  final String identity;
}

class _PlatformAccessDialog extends StatefulWidget {
  const _PlatformAccessDialog({required this.operation});
  final String operation;
  @override
  State<_PlatformAccessDialog> createState() => _PlatformAccessDialogState();
}

class _PlatformAccessDialogState extends State<_PlatformAccessDialog> {
  final _identity = TextEditingController();
  final _reason = TextEditingController();
  @override
  void dispose() {
    _identity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final approving = widget.operation.startsWith('approve_');
    final email = widget.operation.endsWith('_email');
    final title = switch (widget.operation) {
      'approve_email' => 'Approve email',
      'approve_whatsapp' => 'Approve WhatsApp',
      'revoke_email' || 'revoke_whatsapp' => 'Revoke approval',
      'activate' => 'Activate Admin',
      _ => 'Deactivate Admin',
    };
    String? normalizedIdentity;
    if (approving && email) {
      try {
        normalizedIdentity = normalizeAdminEmail(_identity.text);
      } on FormatException {
        // Keep submission unavailable until the field contains a valid email.
      }
    } else if (approving &&
        RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_identity.text.trim())) {
      normalizedIdentity = _identity.text.trim();
    }
    final reasonLength = _reason.text.trim().length;
    final valid =
        reasonLength >= (email ? 8 : 1) &&
        reasonLength <= (email ? 500 : 1000) &&
        (!approving || normalizedIdentity != null);
    return AlertDialog(
      scrollable: true,
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
                controller: _identity,
                autofocus: true,
                keyboardType: email
                    ? TextInputType.emailAddress
                    : TextInputType.phone,
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: email ? 254 : 16,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: email
                      ? 'Verified operator email'
                      : 'Verified WhatsApp number',
                  hintText: email ? 'operator@example.com' : '+250…',
                  helperText: email
                      ? 'Must match this existing account’s verified email.'
                      : 'Must match this account’s verified number.',
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
              maxLength: email ? 500 : 1000,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Reason',
                helperText: email ? '8–500 characters.' : null,
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
                    normalizedIdentity ?? '',
                  ),
                ),
          child: Text(title),
        ),
      ],
    );
  }
}
