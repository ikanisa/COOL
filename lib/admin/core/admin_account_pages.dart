import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_universal_tokens.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_models.dart';

// Signed-out task forms and operator settings adapt the selected Revolut web
// patterns through Collect's existing semantic theme. Account workflows and
// permissions come from Collect's service, not the visual reference.

class AdminAccountLoginPage extends ConsumerStatefulWidget {
  const AdminAccountLoginPage({
    required this.onSignedIn,
    required this.onForgotPassword,
    super.key,
  });
  final VoidCallback onSignedIn;
  final VoidCallback onForgotPassword;

  @override
  ConsumerState<AdminAccountLoginPage> createState() => _LoginState();
}

class _LoginState extends _RequestState<AdminAccountLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !_form.currentState!.validate()) return;
    final accepted = await request(
      () => ref
          .read(adminAccountApiProvider)
          .signIn(_email.text.trim().toLowerCase(), _password.text),
    );
    if (accepted && mounted) {
      TextInput.finishAutofillContext();
      _password.clear();
      widget.onSignedIn();
    }
  }

  @override
  Widget build(BuildContext context) => _PublicAccountPage(
    title: 'Welcome to Collect',
    subtitle: 'Sign in to your admin workspace.',
    child: AutofillGroup(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EmailField(controller: _email, enabled: !busy),
            const SizedBox(height: 18),
            _PasswordField(
              controller: _password,
              label: 'Password',
              enabled: !busy,
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
              onSubmitted: (_) => _submit(),
            ),
            _Feedback(error: error, status: status),
            const SizedBox(height: 24),
            _SubmitButton(label: 'Sign in', busy: busy, onPressed: _submit),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : widget.onForgotPassword,
              child: const Text('Forgot password?'),
            ),
            const SizedBox(height: 16),
            const Text(
              'New to the team? Open the invitation sent to your email to set your password.',
            ),
          ],
        ),
      ),
    ),
  );
}

class AdminAccountForgotPasswordPage extends ConsumerStatefulWidget {
  const AdminAccountForgotPasswordPage({
    required this.onBackToLogin,
    super.key,
  });
  final VoidCallback onBackToLogin;

  @override
  ConsumerState<AdminAccountForgotPasswordPage> createState() => _ForgotState();
}

class _ForgotState extends _RequestState<AdminAccountForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !_form.currentState!.validate()) return;
    await request(
      () => ref
          .read(adminAccountApiProvider)
          .requestPasswordReset(_email.text.trim().toLowerCase()),
      success:
          'If this email has access to Collect admin, a password setup or reset email has been requested. Check your inbox and spam folder.',
    );
  }

  @override
  Widget build(BuildContext context) => _PublicAccountPage(
    title: 'Reset your password',
    subtitle: 'Enter the email you use for Collect admin.',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmailField(
            controller: _email,
            enabled: !busy,
            onSubmitted: (_) => _submit(),
          ),
          _Feedback(error: error, status: status),
          const SizedBox(height: 24),
          _SubmitButton(
            label: 'Send reset email',
            busy: busy,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : widget.onBackToLogin,
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    ),
  );
}

class AdminAccountPasswordSetupPage extends ConsumerStatefulWidget {
  const AdminAccountPasswordSetupPage({
    required this.token,
    required this.invite,
    required this.onBackToLogin,
    required this.onRequestReset,
    super.key,
  });
  final String token;
  final bool invite;
  final VoidCallback onBackToLogin;
  final VoidCallback onRequestReset;

  @override
  ConsumerState<AdminAccountPasswordSetupPage> createState() => _SetupState();
}

class _SetupState extends _RequestState<AdminAccountPasswordSetupPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  var _complete = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || securityOutcomeUnknown || !_form.currentState!.validate()) {
      return;
    }
    final accepted = await request(
      () => ref
          .read(adminAccountApiProvider)
          .completePasswordSetup(
            widget.token,
            _password.text,
            invite: widget.invite,
          ),
    );
    if ((accepted || securityOutcomeUnknown) && mounted) {
      TextInput.finishAutofillContext();
      _password.clear();
      _confirm.clear();
      if (accepted) setState(() => _complete = true);
    }
  }

  @override
  Widget build(BuildContext context) => _PublicAccountPage(
    title: _complete
        ? 'Your password is ready'
        : widget.invite
        ? 'Join your Collect team'
        : 'Choose a new password',
    subtitle: _complete
        ? 'Sign in with your email and new password.'
        : widget.invite
        ? 'Set a password to accept your invitation.'
        : 'Use a password you do not use elsewhere.',
    child: _complete
        ? FilledButton(
            onPressed: widget.onBackToLogin,
            child: const Text('Continue to sign in'),
          )
        : widget.token.trim().isEmpty
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Feedback(
                error: widget.invite
                    ? 'This invitation link is incomplete. Ask the owner to resend your invitation.'
                    : 'This reset link is incomplete. Request a new reset email.',
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: widget.invite
                    ? widget.onBackToLogin
                    : widget.onRequestReset,
                child: Text(
                  widget.invite ? 'Back to sign in' : 'Request reset email',
                ),
              ),
            ],
          )
        : AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PasswordField(
                    controller: _password,
                    label: 'New password',
                    enabled: !busy && !securityOutcomeUnknown,
                    isNew: true,
                    validator: _validateNewPassword,
                  ),
                  const SizedBox(height: 18),
                  _PasswordField(
                    controller: _confirm,
                    label: 'Confirm new password',
                    enabled: !busy && !securityOutcomeUnknown,
                    isNew: true,
                    validator: (value) => value != _password.text
                        ? 'The passwords do not match.'
                        : null,
                    onSubmitted: (_) => _submit(),
                  ),
                  _Feedback(error: error, status: status),
                  const SizedBox(height: 24),
                  _SubmitButton(
                    label: widget.invite
                        ? 'Accept invitation'
                        : 'Save password',
                    busy: busy,
                    onPressed: securityOutcomeUnknown ? null : _submit,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : widget.onBackToLogin,
                    child: const Text('Back to sign in'),
                  ),
                  if (!widget.invite)
                    TextButton(
                      onPressed: busy ? null : widget.onRequestReset,
                      child: const Text('Request another reset email'),
                    ),
                ],
              ),
            ),
          ),
  );
}

class AdminAccountSecurityPage extends ConsumerStatefulWidget {
  const AdminAccountSecurityPage({this.onSignIn, super.key});
  final VoidCallback? onSignIn;

  @override
  ConsumerState<AdminAccountSecurityPage> createState() => _SecurityState();
}

class _SecurityState extends _RequestState<AdminAccountSecurityPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || securityOutcomeUnknown || !_form.currentState!.validate()) {
      return;
    }
    final accepted = await request(
      () => ref
          .read(adminAccountApiProvider)
          .changePassword(_current.text, _password.text),
      success: 'Your password has been changed.',
    );
    if ((accepted || securityOutcomeUnknown) && mounted) {
      TextInput.finishAutofillContext();
      _form.currentState!.reset();
      _current.clear();
      _password.clear();
      _confirm.clear();
    }
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: 'Account security',
    subtitle: 'Manage the password you use to sign in to Collect.',
    child: Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _AccountCard(
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Change password',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  _PasswordField(
                    controller: _current,
                    label: 'Current password',
                    enabled: !busy && !securityOutcomeUnknown,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                  const SizedBox(height: 18),
                  _PasswordField(
                    controller: _password,
                    label: 'New password',
                    enabled: !busy && !securityOutcomeUnknown,
                    isNew: true,
                    validator: (value) =>
                        _validateNewPassword(value) ??
                        (value == _current.text
                            ? 'Choose a different password.'
                            : null),
                  ),
                  const SizedBox(height: 18),
                  _PasswordField(
                    controller: _confirm,
                    label: 'Confirm new password',
                    enabled: !busy && !securityOutcomeUnknown,
                    isNew: true,
                    validator: (value) => value != _password.text
                        ? 'The passwords do not match.'
                        : null,
                    onSubmitted: (_) => _submit(),
                  ),
                  _Feedback(error: error, status: status),
                  if (securityOutcomeUnknown && widget.onSignIn != null)
                    TextButton(
                      onPressed: widget.onSignIn,
                      child: const Text('Sign in to check password'),
                    ),
                  const SizedBox(height: 24),
                  _SubmitButton(
                    label: 'Change password',
                    busy: busy,
                    onPressed: securityOutcomeUnknown ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AdminAccountTeamPage extends ConsumerStatefulWidget {
  const AdminAccountTeamPage({super.key});

  @override
  ConsumerState<AdminAccountTeamPage> createState() => _TeamState();
}

class _TeamState extends _RequestState<AdminAccountTeamPage> {
  AdminAccountTeam? _team;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await request(() async {
      final team = await ref.read(adminAccountApiProvider).loadTeam();
      if (mounted) setState(() => _team = team);
    });
  }

  Future<void> _invite() async {
    String? invitationError;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InviteDialog(onFailure: (message) => invitationError = message),
    );
    if (!mounted) return;
    // Creating the account may succeed before sending its email fails. Always
    // reconcile the roster so its pending row and resend action are reachable.
    await _refreshAfterAction(
      actionError: accepted == true ? null : invitationError,
      actionStatus: accepted == true
          ? 'Invitation accepted for sending. The account becomes active when the invitation is accepted.'
          : null,
    );
  }

  Future<void> _refreshAfterAction({
    String? actionError,
    String? actionStatus,
  }) async {
    await _load();
    if (mounted) {
      setState(() {
        final messages = <String>{?actionError, ?error};
        error = messages.isEmpty ? null : messages.join('\n');
        status = actionStatus;
      });
    }
  }

  Future<void> _resend(AdminAccountMember member) async {
    await request(
      () => ref.read(adminAccountApiProvider).resendInvitation(member.id),
      success: 'A new invitation for ${member.email} was accepted for sending.',
    );
    if (mounted) {
      await _refreshAfterAction(actionError: error, actionStatus: status);
    }
  }

  Future<void> _revoke(AdminAccountMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Remove team access?'),
        content: Text(
          '${member.email} will lose access to Collect admin. Any pending invitation will stop working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep access'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.collectColors.dangerForeground,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove access'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final accepted = await request(
      () => ref.read(adminAccountApiProvider).revokeMember(member.id),
    );
    if (accepted && mounted) {
      await _load();
      if (mounted) {
        setState(() => status = 'Access removed for ${member.email}.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    return AdminPage(
      title: 'Team access',
      subtitle: 'Admins and staff who can use the Collect workspace.',
      trailing: team?.canManage == true
          ? FilledButton.icon(
              onPressed: busy ? null : _invite,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Invite teammate'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy)
            const LinearProgressIndicator(
              semanticsLabel: 'Updating team access',
            ),
          _Feedback(error: error, status: status),
          if (error != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : _load,
                child: const Text('Refresh team'),
              ),
            ),
          if (team != null) ...[
            if (team.permissionsByRole.isNotEmpty) ...[
              const Text(
                'Role access',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _AccessPolicyTable(policy: team.permissionsByRole),
              const SizedBox(height: 24),
            ],
            if (!team.canManage)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'The account owner manages invitations and team access.',
                ),
              ),
            if (team.members.isEmpty)
              const Text('No team accounts to display.')
            else
              AdminDataTable(
                tableLabel: 'Staff and administrators',
                rows: [
                  for (final member in team.members)
                    AdminTableRowData(
                      id: member.id,
                      title: member.email,
                      subtitle: '',
                      status: member.status.label,
                      amount: '',
                      extra: {
                        'public_id': member.publicId ?? '—',
                        'name': (member.displayName?.isNotEmpty ?? false)
                            ? member.displayName
                            : '—',
                        'email': member.email,
                        'role': member.role.label,
                        'status': member.status.label,
                        'invitation_email':
                            member.status == AdminAccountStatus.invited
                            ? switch (member.emailStatus) {
                                'accepted' =>
                                  'Invitation email accepted for sending.',
                                'failed' =>
                                  'Invitation email was not accepted for sending. Resend the invitation.',
                                _ =>
                                  'Invitation email sending is not confirmed.',
                              }
                            : '—',
                      },
                    ),
                ],
                columns: [
                  for (final field in {
                    'public_id': 'User ID',
                    'name': 'Name',
                    'email': 'Email',
                    'role': 'Role',
                    'status': 'Access status',
                    'invitation_email': 'Invitation email',
                  }.entries)
                    AdminTableColumn(
                      label: field.value,
                      value: (row) => '${row.extra[field.key]}',
                    ),
                ],
                trailingBuilder: (row) {
                  final member = team.members.firstWhere(
                    (member) => member.id == row.id,
                  );
                  return _TeamActions(
                    member: member,
                    canManage:
                        team.canManage &&
                        member.role != AdminAccountRole.owner &&
                        member.email.toLowerCase() !=
                            team.currentEmail.toLowerCase(),
                    busy: busy,
                    onResend: () => _resend(member),
                    onRevoke: () => _revoke(member),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

const _permissionLabels = <String, String>{
  'overview.read': 'View overview',
  'account.manage': 'Change own password',
  'collections.read': 'View groups',
  'collections.create': 'Create private groups',
  'collections.manage': 'Edit groups and publish public groups',
  'users.read': 'View users and members',
  'users.manage': 'Edit people and memberships',
  'receivers.read': 'View payees',
  'receivers.manage': 'Edit and activate payees',
  'payments.read': 'View transactions and member receipts',
  'payments.manage': 'Record evidence and verify transactions',
  'reconciliations.read': 'View reconciliation queue',
  'reconciliations.propose': 'Propose a member allocation',
  'reconciliations.review': 'Independently approve or reject proposals',
  'ledger.read': 'View ledgers',
  'ledger.manage': 'Prepare and post balanced journals',
  'sms.read': 'View SMS facts',
  'sms.extract': 'Extract preserved SMS facts',
  'sms.reveal': 'Reveal SMS content with an audit reason',
  'email.read': 'View email notifications',
  'email.manage': 'Dispatch email notifications',
  'gateway.read': 'View gateway devices',
  'gateway.manage': 'Manage gateway enrollment and access',
  'admin_users.read': 'Review team accounts and role access',
  'admin_users.manage': 'Invite and remove team access',
};

class _AccessPolicyTable extends StatelessWidget {
  const _AccessPolicyTable({required this.policy});
  final Map<String, List<String>> policy;
  @override
  Widget build(BuildContext context) {
    final permissions = policy.values.expand((value) => value).toSet().toList()
      ..sort();
    return AdminDataTable(
      tableLabel: 'Role access policy',
      rows: [
        for (final permission in permissions)
          AdminTableRowData(
            id: permission,
            title: _permissionLabels[permission] ?? permission,
            subtitle: '',
            status: '',
            amount: '',
            extra: {
              for (final role in ['owner', 'admin', 'staff'])
                role: policy[role]?.contains(permission) == true
                    ? 'Allowed'
                    : '—',
            },
          ),
      ],
      columns: [
        AdminTableColumn(label: 'Action', value: (row) => row.title),
        for (final role in ['owner', 'admin', 'staff'])
          AdminTableColumn(
            label: '${role[0].toUpperCase()}${role.substring(1)}',
            value: (row) => '${row.extra[role]}',
          ),
      ],
    );
  }
}

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.onFailure});
  final ValueChanged<String> onFailure;
  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends _RequestState<_InviteDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  var _role = AdminAccountRole.staff;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || !_form.currentState!.validate()) return;
    final accepted = await request(
      () => ref
          .read(adminAccountApiProvider)
          .invite(
            _email.text.trim().toLowerCase(),
            _role,
            displayName: _name.text.trim(),
          ),
    );
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context, true);
    } else if (error != null) {
      widget.onFailure(error!);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Invite a teammate'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'They will receive an email to set their own password.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                key: const ValueKey('admin-account-name'),
                controller: _name,
                enabled: !busy,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Recorded full name (optional)',
                ),
                validator: (value) =>
                    value != null &&
                        value.trim().isNotEmpty &&
                        value.trim().length < 2
                    ? 'Enter the full name.'
                    : null,
              ),
              const SizedBox(height: 18),
              _EmailField(controller: _email, enabled: !busy),
              const SizedBox(height: 18),
              DropdownButtonFormField<AdminAccountRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Workspace role'),
                isExpanded: true,
                items: [
                  for (final role in [
                    AdminAccountRole.staff,
                    AdminAccountRole.admin,
                  ])
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: busy
                    ? null
                    : (role) => setState(() => _role = role!),
              ),
              const SizedBox(height: 12),
              Text(
                _role == AdminAccountRole.staff
                    ? 'Staff can read operational records, create private groups and propose reconciliation allocations. They cannot publish groups or approve allocations.'
                    : 'Admins can manage workspace operations. Only the owner manages team access.',
              ),
              _Feedback(error: error),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        _SubmitButton(label: 'Send invitation', busy: busy, onPressed: _submit),
      ],
    ),
  );
}

class _TeamActions extends StatelessWidget {
  const _TeamActions({
    required this.member,
    required this.canManage,
    required this.busy,
    required this.onResend,
    required this.onRevoke,
  });
  final AdminAccountMember member;
  final bool canManage;
  final bool busy;
  final VoidCallback onResend;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    if (!canManage || member.status == AdminAccountStatus.revoked) {
      return const Text('—');
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (member.status == AdminAccountStatus.invited)
          TextButton(
            onPressed: busy ? null : onResend,
            child: const Text('Resend invitation'),
          ),
        if (member.status == AdminAccountStatus.invited)
          const SizedBox(width: 8),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: context.collectColors.dangerForeground,
          ),
          onPressed: busy ? null : onRevoke,
          child: const Text('Remove access'),
        ),
      ],
    );
  }
}

abstract class _RequestState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  bool busy = false;
  bool securityOutcomeUnknown = false;
  String? error;
  String? status;

  Future<bool> request(
    Future<void> Function() operation, {
    String? success,
  }) async {
    if (busy) return false;
    setState(() {
      busy = true;
      error = null;
      status = null;
    });
    try {
      await operation();
      if (!mounted) return false;
      setState(() => status = success);
      return true;
    } on AdminAccountException catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.message;
          securityOutcomeUnknown =
              failure is AdminAccountSecurityOutcomeUnknown;
        });
      }
      return false;
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'We could not confirm this request. Check your connection and try again.',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _PublicAccountPage extends StatelessWidget {
  const _PublicAccountPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.collectColors.canvas,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _AccountCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.lock_outline,
                      size: 32,
                      color: context.collectColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: context.collectColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.collectColors.surfaceReadable,
      borderRadius: BorderRadius.circular(
        context.collectUniversalTokens.cardRadius,
      ),
      border: Border.all(color: context.collectColors.border),
    ),
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
}

class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.enabled,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: const Key('admin-account-email'),
    controller: controller,
    enabled: enabled,
    keyboardType: TextInputType.emailAddress,
    textInputAction: onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    autofillHints: const [AutofillHints.username, AutofillHints.email],
    autocorrect: false,
    decoration: const InputDecoration(labelText: 'Email address'),
    onFieldSubmitted: onSubmitted,
    validator: (value) {
      final email = value?.trim() ?? '';
      return email.length <= 254 &&
              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
          ? null
          : 'Enter a valid email address.';
    },
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.validator,
    this.isNew = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool isNew;
  final FormFieldValidator<String> validator;
  final ValueChanged<String>? onSubmitted;
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('admin-account-${widget.label}'),
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: [
      widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
    ],
    textInputAction: widget.onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.isNew && widget.label == 'New password'
          ? 'Use 12–128 characters.'
          : null,
      helperMaxLines: 2,
      errorMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: '${_hidden ? 'Show' : 'Hide'} ${widget.label.toLowerCase()}',
        onPressed: widget.enabled
            ? () => setState(() => _hidden = !_hidden)
            : null,
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
  );
}

String? _validateNewPassword(String? value) =>
    value == null ||
        value.runes.length < 12 ||
        value.runes.length > 128 ||
        utf8.encode(value).length > 512
    ? 'Use between 12 and 128 characters.'
    : null;

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Text(busy ? 'Please wait…' : label),
        ],
      ),
    ),
  );
}

class _Feedback extends StatelessWidget {
  const _Feedback({this.error, this.status});
  final String? error;
  final String? status;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final message in [?error, ?status])
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: message == error
                    ? context.collectColors.dangerForeground
                    : context.collectColors.textPrimary,
              ),
            ),
          ),
        ),
    ],
  );
}
