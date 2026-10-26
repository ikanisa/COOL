import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_universal_tokens.dart';
import '../../core/cloudflare/collect_cloudflare_types.dart';
import '../../core/cloudflare/google_auth_browser.dart';
import '../../features/auth/widgets/collect_google_sign_in_button.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_public_account_page.dart';
import 'admin_account_api.dart';
import 'admin_email_otp.dart';
import 'admin_invitation_recovery.dart';
import 'admin_pending_attempt_store.dart';
import 'admin_models.dart';

// Signed-out task forms and operator settings adapt the selected Revolut web
// patterns through Collect's existing semantic theme. Account workflows and
// permissions come from Collect's service, not the visual reference.

class AdminAccountLoginPage extends ConsumerStatefulWidget {
  const AdminAccountLoginPage({
    required this.onSignedIn,
    required this.onForgotPassword,
    this.googleSignInEnabled = const bool.fromEnvironment(
      'GOOGLE_AUTH_ENABLED',
    ),
    super.key,
  });
  final VoidCallback onSignedIn;
  final VoidCallback onForgotPassword;
  final bool googleSignInEnabled;

  @override
  ConsumerState<AdminAccountLoginPage> createState() => _LoginState();
}

class _LoginState extends _RequestState<AdminAccountLoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  AdminEmailOtpReceipt? _receipt;
  String? _requestedEmail;
  Timer? _resendTimer;
  int _resendRemaining = 0;
  final _googleBrowser = GoogleAuthBrowser();
  AdminGoogleAccountApi? _activeGoogleApi;
  var _googlePending = false;
  var _googleAttempt = 0;

  bool get _googleAvailable {
    if (!widget.googleSignInEnabled) return false;
    final api = ref.watch(adminAccountApiProvider);
    if (api is! AdminGoogleAccountApi) return false;
    final googleApi = api as AdminGoogleAccountApi;
    return googleApi.googleSignInAvailable;
  }

  @override
  void dispose() {
    _cancelGoogleSignIn(rebuild: false);
    _googleBrowser.cancel();
    _email.dispose();
    _code.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  AdminEmailOtpAccountApi _emailApi() {
    final api = ref.read(adminAccountApiProvider);
    if (api is! AdminEmailOtpAccountApi) {
      throw const AdminAccountException(
        'Email sign-in is not configured. Contact your super admin.',
      );
    }
    return api as AdminEmailOtpAccountApi;
  }

  Future<void> _accessNotApproved() async {
    if (!mounted) return;
    await showDialog<void>(
      context: _form.currentContext ?? context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => AlertDialog(
        key: const Key('admin-access-not-approved'),
        constraints: const BoxConstraints(maxWidth: 480),
        scrollable: true,
        title: const Text('Contact your super admin'),
        content: const Text(
          'This email does not have access to Collect Admin. Ask your super admin to add you to the team, then sign in with your email.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCode() async {
    if (busy ||
        securityOutcomeUnknown ||
        (_receipt == null && !_form.currentState!.validate())) {
      return;
    }
    final wasResend = _receipt != null;
    final email = _requestedEmail ?? normalizeAdminEmail(_email.text);
    AdminEmailOtpReceipt? receipt;
    var noAccess = false;
    String? deliveryWarning;
    final accepted = await request(() async {
      try {
        receipt = await _emailApi().requestEmailOtp(email);
      } on AdminEmailOtpDeliveryUnknown catch (failure) {
        receipt = failure.receipt;
        deliveryWarning = failure.message;
      } on AdminAccountAccessNotApproved {
        noAccess = true;
        await _accessNotApproved();
      }
    });
    if (!mounted) return;
    if (!accepted || noAccess || receipt == null) {
      if (wasResend) {
        // A new request replaces the previous server challenge even when its
        // receipt is lost. Do not offer verification with that stale receipt.
        _resendTimer?.cancel();
        setState(() {
          _receipt = null;
          _requestedEmail = null;
          _resendRemaining = 0;
          _code.clear();
        });
      }
      return;
    }
    setState(() {
      _requestedEmail = email;
      _receipt = receipt;
      _code.clear();
      error = deliveryWarning;
      status = deliveryWarning == null
          ? 'A sign-in code was accepted for sending. Check your inbox and spam folder.'
          : null;
    });
    _startCooldown(receipt!.retryAfterSeconds);
  }

  Future<void> _verifyCode() async {
    if (busy || securityOutcomeUnknown || !_form.currentState!.validate()) {
      return;
    }
    final receipt = _receipt;
    final email = _requestedEmail;
    if (receipt == null || email == null) return;
    var noAccess = false;
    final accepted = await request(() async {
      try {
        await _emailApi().verifyEmailOtp(
          email: email,
          challengeId: receipt.challengeId,
          code: normalizeAdminEmailOtp(_code.text),
        );
      } on AdminAccountAccessNotApproved {
        noAccess = true;
        await _accessNotApproved();
      }
    });
    if (accepted && !noAccess && mounted) {
      TextInput.finishAutofillContext();
      _code.clear();
      _resendTimer?.cancel();
      widget.onSignedIn();
    }
  }

  void _startCooldown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendRemaining = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendRemaining <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendRemaining = 0);
        return;
      }
      setState(() => _resendRemaining--);
    });
  }

  void _changeEmail() {
    if (busy || securityOutcomeUnknown) return;
    _resendTimer?.cancel();
    setState(() {
      _receipt = null;
      _requestedEmail = null;
      _resendRemaining = 0;
      _code.clear();
      error = null;
      status = null;
    });
  }

  bool _currentGoogleAttempt(int attempt) =>
      mounted && attempt == _googleAttempt;

  Future<void> _signInWithGoogle() async {
    if (busy ||
        securityOutcomeUnknown ||
        _receipt != null ||
        !widget.googleSignInEnabled) {
      return;
    }
    final api = ref.read(adminAccountApiProvider);
    if (api is! AdminGoogleAccountApi) return;
    final googleApi = api as AdminGoogleAccountApi;
    if (!googleApi.googleSignInAvailable) return;
    final attempt = ++_googleAttempt;
    _activeGoogleApi = googleApi;
    setState(() {
      busy = true;
      _googlePending = true;
      error = null;
      status = null;
      securityOutcomeUnknown = false;
    });
    try {
      await googleApi.signInWithGoogle(authorize: _googleBrowser.authorize);
      if (!_currentGoogleAttempt(attempt)) return;
      TextInput.finishAutofillContext();
      widget.onSignedIn();
    } on AdminAccountAccessNotApproved {
      if (_currentGoogleAttempt(attempt)) await _accessNotApproved();
    } on AdminAccountSecurityOutcomeUnknown {
      if (_currentGoogleAttempt(attempt)) {
        setState(() {
          securityOutcomeUnknown = true;
          error =
              'Google sign-in could not be confirmed. Check your session before starting a fresh sign-in.';
        });
      }
    } on CollectAuthException catch (failure) {
      if (_currentGoogleAttempt(attempt) &&
          failure.code != 'google_cancelled') {
        setState(() {
          error = failure.code == 'google_popup_blocked'
              ? 'Allow the sign-in window in your browser, then try Google again.'
              : 'Google sign-in could not finish. Try again or use your email.';
        });
      }
    } catch (_) {
      if (_currentGoogleAttempt(attempt)) {
        setState(() {
          error =
              'Google sign-in could not finish. Try again or use your email.';
        });
      }
    } finally {
      if (_currentGoogleAttempt(attempt)) {
        _activeGoogleApi = null;
        setState(() {
          busy = false;
          _googlePending = false;
        });
      }
    }
  }

  void _cancelGoogleSignIn({bool rebuild = true}) {
    if (!_googlePending) return;
    _googleAttempt++;
    _activeGoogleApi?.cancelGoogleSignIn();
    _activeGoogleApi = null;
    _googleBrowser.cancel();
    void clearPending() {
      busy = false;
      _googlePending = false;
      error = null;
      status = null;
      securityOutcomeUnknown = false;
    }

    if (rebuild && mounted) {
      setState(clearPending);
    } else {
      clearPending();
    }
  }

  Future<void> _checkGoogleSession() async {
    if (busy || !securityOutcomeUnknown) return;
    final api = ref.read(adminAccountApiProvider);
    if (api is! AdminGoogleAccountApi) return;
    final googleApi = api as AdminGoogleAccountApi;
    final attempt = ++_googleAttempt;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      final signedIn = await googleApi.recheckSession();
      if (!_currentGoogleAttempt(attempt)) return;
      if (signedIn) {
        widget.onSignedIn();
      } else {
        _resendTimer?.cancel();
        setState(() {
          securityOutcomeUnknown = false;
          _receipt = null;
          _requestedEmail = null;
          _resendRemaining = 0;
          _code.clear();
          error = null;
          status = 'No active session was found. Sign in again.';
        });
      }
    } catch (_) {
      if (_currentGoogleAttempt(attempt)) {
        setState(() {
          error = 'Your session could not be checked. Try Check session again.';
        });
      }
    } finally {
      if (_currentGoogleAttempt(attempt)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminPublicAccountPage(
    title: _receipt != null ? 'Check your email' : 'Welcome to Collect',
    subtitle: _googlePending
        ? 'Complete sign-in in the Google window.'
        : _receipt != null
        ? 'Enter the 6-digit code for $_requestedEmail.'
        : 'Enter your team email to sign in to your admin workspace.',
    child: AutofillGroup(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_googlePending)
              const SizedBox.shrink()
            else if (_receipt == null)
              _EmailField(
                controller: _email,
                enabled: !busy && !securityOutcomeUnknown,
                onSubmitted: (_) => _sendCode(),
              )
            else
              TextFormField(
                key: const Key('admin-account-email-code'),
                controller: _code,
                enabled: !busy && !securityOutcomeUnknown,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(labelText: '6-digit code'),
                onFieldSubmitted: (_) => _verifyCode(),
                validator: (value) =>
                    RegExp(r'^[0-9]{6}$').hasMatch(value ?? '')
                    ? null
                    : 'Enter the 6-digit email code.',
              ),
            _Feedback(error: error, status: status),
            const SizedBox(height: 24),
            if (securityOutcomeUnknown)
              FilledButton(
                key: const Key('admin-account-check-session'),
                onPressed: busy ? null : _checkGoogleSession,
                child: Text(busy ? 'Checking session…' : 'Check session'),
              )
            else if (!_googlePending)
              _SubmitButton(
                label: _receipt != null
                    ? 'Verify and sign in'
                    : 'Send sign-in code',
                busy: busy,
                onPressed: _receipt != null ? _verifyCode : _sendCode,
              ),
            if (_receipt == null && (_googlePending || _googleAvailable)) ...[
              const SizedBox(height: 12),
              CollectGoogleSignInButton(
                key: const Key('admin-account-google-sign-in'),
                busy: _googlePending,
                onPressed: busy || securityOutcomeUnknown
                    ? null
                    : _signInWithGoogle,
              ),
              if (_googlePending)
                TextButton(
                  key: const Key('admin-account-cancel-google'),
                  onPressed: _cancelGoogleSignIn,
                  child: const Text('Cancel Google sign-in'),
                ),
            ],
            if (_receipt != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('admin-account-resend-code'),
                onPressed:
                    busy || securityOutcomeUnknown || _resendRemaining > 0
                    ? null
                    : () {
                        _code.clear();
                        _sendCode();
                      },
                child: Text(
                  _resendRemaining > 0
                      ? 'Resend code in ${_resendRemaining}s'
                      : 'Resend code',
                ),
              ),
              TextButton(
                onPressed: busy || securityOutcomeUnknown ? null : _changeEmail,
                child: const Text('Use a different email'),
              ),
            ] else if (!_googlePending) ...[
              const SizedBox(height: 16),
              const Text(
                'New to the team? Ask your super admin for an invitation, then sign in with your email.',
              ),
            ],
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
  Widget build(BuildContext context) => AdminPublicAccountPage(
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
  Widget build(BuildContext context) => AdminPublicAccountPage(
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
  const AdminAccountSecurityPage({
    this.onSignIn,
    this.onPasswordRecovery,
    super.key,
  });
  final VoidCallback? onSignIn;
  final VoidCallback? onPasswordRecovery;

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
                  if (widget.onPasswordRecovery != null)
                    TextButton(
                      onPressed: busy || securityOutcomeUnknown
                          ? null
                          : widget.onPasswordRecovery,
                      child: const Text('Set or reset password by email'),
                    ),
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
  const AdminAccountTeamPage({this.onVerify, super.key});
  final VoidCallback? onVerify;

  @override
  ConsumerState<AdminAccountTeamPage> createState() => _TeamState();
}

class _TeamState extends _RequestState<AdminAccountTeamPage> {
  AdminAccountTeam? _team;
  bool _teamVerified = false;
  AdminInvitationCoordinator? _invitations;
  Object? _invitationFence;
  AdminInvitationAccountApi? _invitationApi;
  AdminInvitationAccountApi? get _managedInvitations {
    final api = ref.read(adminAccountApiProvider);
    return api is AdminInvitationAccountApi &&
            (api as AdminInvitationAccountApi).invitationRecoveryAvailable
        ? api as AdminInvitationAccountApi
        : null;
  }

  void _pairInvitations() {
    final api = _managedInvitations;
    if (api == null || _team?.canManage != true) {
      _invitations = null;
      return;
    }
    if (_invitations != null &&
        identical(_invitationApi, api) &&
        _invitationFence == api.invitationAuthorityFence) {
      return;
    }
    _invitationFence = api.invitationAuthorityFence;
    _invitationApi = api;
    _invitations = AdminInvitationCoordinator(
      api: api,
      store: ref.read(adminPendingAttemptStoreProvider),
      canManageTeam: () =>
          mounted &&
          _teamVerified &&
          _team?.canManage == true &&
          identical(_managedInvitations, api),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _teamVerified = false;
    final api = ref.read(adminAccountApiProvider),
        managed = _managedInvitations;
    final fence = managed?.invitationAuthorityFence;
    await request(() async {
      final team = await api.loadTeam();
      if (!mounted) return;
      if (managed != null && fence != managed.invitationAuthorityFence) {
        throw const AdminAccountException(
          'Reopen team access with your current sign-in.',
        );
      }
      setState(() {
        _team = team;
        _teamVerified = true;
      });
      _pairInvitations();
    });
  }

  Future<void> _invite() async {
    final recovery = _invitations;
    if (_managedInvitations != null &&
        (recovery == null || !recovery.authorized || recovery.hasPending)) {
      return;
    }
    String? invitationError;
    final result = await showDialog<_InviteResult>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      barrierDismissible: false,
      builder: (_) => _InviteDialog(
        coordinator: recovery,
        onFailure: (message) => invitationError = message,
      ),
    );
    if (!mounted) return;
    await _refreshAfterAction(
      actionError: result == null ? invitationError : null,
      actionStatus:
          result?.receipt?.statusMessage ??
          (result?.legacyAccepted == true
              ? 'Invitation accepted for sending.'
              : null),
    );
  }

  Future<void> _checkInvitation(AdminInvitationPending attempt) async {
    final recovery = _invitations;
    if (recovery == null) return;
    AdminInvitationLookup? result;
    await request(() async {
      result = await recovery.lookup(attempt);
    });
    if (!mounted) return;
    final message =
        result?.receipt?.statusMessage ??
        (result != null ? attempt.message : null);
    await _refreshAfterAction(actionError: error, actionStatus: message);
  }

  Future<void> _retryInvitation(AdminInvitationPending attempt) async {
    if (!await _confirmInvitationRetry(context, attempt) || !mounted) return;
    final recovery = _invitations;
    if (recovery == null) return;
    AdminInvitationReceipt? result;
    await request(() async {
      result = await recovery.submit(attempt, confirmedSameIntentRetry: true);
    });
    if (mounted) {
      await _refreshAfterAction(
        actionError: error,
        actionStatus: result?.statusMessage,
      );
    }
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
    final recovery = _invitations;
    AdminInvitationReceipt? receipt;
    if (_managedInvitations != null) {
      if (recovery == null || !recovery.canResend(member)) return;
      await request(() async {
        final attempt = recovery.prepareResend(member);
        receipt = await recovery.submit(attempt);
      });
    } else {
      await request(
        () => ref.read(adminAccountApiProvider).resendInvitation(member.id),
        success:
            'A new invitation for ${member.email} was accepted for sending.',
      );
    }
    if (mounted) {
      await _refreshAfterAction(
        actionError: error,
        actionStatus: receipt?.statusMessage ?? status,
      );
    }
  }

  Future<void> _repairNotice(AdminAccountMember member) async {
    final recovery = _invitations;
    if (recovery == null || !recovery.canRepairNotice(member)) return;
    final source = member.invitation?.requestId ?? member.invitationRequestId;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Send an access notice?'),
        content: Text(
          '${member.email} already has a registered account. Send an access notice with the ordinary Admin sign-in instructions. This does not confirm inbox delivery or sign-in.\n\nOriginal server reference: $source',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep history'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send access notice'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !recovery.canRepairNotice(member)) {
      return;
    }
    AdminInvitationReceipt? receipt;
    await request(() async {
      final attempt = recovery.prepareNoticeRepair(member);
      receipt = await recovery.submit(attempt);
    });
    if (mounted) {
      await _refreshAfterAction(
        actionError: error,
        actionStatus: receipt?.statusMessage,
      );
    }
  }

  Future<void> _revoke(AdminAccountMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
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
    final team = _team, recovery = _invitations;
    final managed = _managedInvitations != null;
    if (recovery != null) ref.watch(adminPendingAttemptStoreProvider);
    return AdminPage(
      title: 'Team access',
      subtitle: 'Admins and staff who can use the Collect workspace.',
      trailing: team?.canManage == true
          ? FilledButton.icon(
              onPressed:
                  busy ||
                      managed &&
                          (recovery == null ||
                              !recovery.authorized ||
                              recovery.hasPending ||
                              !recovery.store.storageAvailable)
                  ? null
                  : _invite,
              icon: const Icon(Icons.person_add_outlined),
              label: Text(
                recovery?.usesV2 == true ? 'Add teammate' : 'Invite teammate',
              ),
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
          if (widget.onVerify != null)
            TextButton.icon(
              onPressed: busy ? null : widget.onVerify,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Verify email to manage team access'),
            ),
          if (managed &&
              team?.canManage == true &&
              recovery?.authorized != true)
            const Text(
              'Verify your current owner sign-in to manage invitations.',
            ),
          if (recovery != null && !recovery.store.storageAvailable)
            _Feedback(error: recovery.store.storageMessage),
          if (recovery != null)
            for (final attempt in recovery.pending)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _AccountCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recovery.usesV2
                            ? 'Original email request'
                            : 'Original invitation',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (attempt.intent.body['email'] is String)
                        Text(attempt.intent.body['email'] as String),
                      Semantics(liveRegion: true, child: Text(attempt.message)),
                      const SizedBox(height: 8),
                      SelectableText(
                        'Original request: ${attempt.intent.requestKey}',
                      ),
                      if (attempt.intent.operation ==
                          AdminInvitationOperation.noticeRepair)
                        SelectableText(
                          'Registered-account source: ${attempt.intent.priorRequestId}',
                        ),
                      if (attempt.receipt != null)
                        SelectableText(
                          'Server reference: ${attempt.receipt!.requestId}',
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed:
                                busy || attempt.busy || !recovery.authorized
                                ? null
                                : () => _checkInvitation(attempt),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Check original request'),
                          ),
                          if (attempt.canRetry)
                            FilledButton(
                              onPressed: busy || !recovery.authorized
                                  ? null
                                  : () => _retryInvitation(attempt),
                              child: const Text('Retry same request'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

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
              Text(
                'Role capability definitions',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'These definitions set the role maximum. Actual account grants and current verification determine available actions.',
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
                            member.invitation?.statusMessage ??
                            switch (member.emailStatus) {
                              'accepted' =>
                                'Invitation email accepted for sending.',
                              'rejected' => 'Invitation request rejected.',
                              'already_registered' =>
                                'Account already registered. Check linked Admin access.',
                              'failed' when !managed =>
                                'Invitation email was not accepted for sending.',
                              _ =>
                                member.status == AdminAccountStatus.invited
                                    ? 'Invitation email sending is not confirmed.'
                                    : '—',
                            },
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
                    'invitation_email': recovery?.usesV2 == true
                        ? 'Email request'
                        : 'Invitation email',
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
                    resendAllowed:
                        !managed || recovery?.canResend(member) == true,
                    resendLabel: recovery?.usesV2 == true
                        ? 'Resend email'
                        : 'Resend invitation',
                    onResend: () => _resend(member),
                    repairAllowed: recovery?.canRepairNotice(member) == true,
                    onRepair: () => _repairNotice(member),
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
  'notifications.read': 'View notification events',
  'assisted_sms.read': 'View assisted SMS jobs',
  'assisted_sms.manage': 'Review and record assisted SMS operations',
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
      tableLabel: 'Role capability definitions',
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
                    ? 'Included in role'
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

class _InviteResult {
  const _InviteResult({this.receipt, this.legacyAccepted = false});
  final AdminInvitationReceipt? receipt;
  final bool legacyAccepted;
}

Future<bool> _confirmInvitationRetry(
  BuildContext context,
  AdminInvitationPending attempt,
) async =>
    await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          attempt.intent.contractVersion == 2
              ? 'Retry the original email request?'
              : 'Retry the original invitation?',
        ),
        content: Text(
          'Use the same original request and unchanged details. '
          '${attempt.intent.body['email'] ?? attempt.intent.staffId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep pending'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retry same request'),
          ),
        ],
      ),
    ) ==
    true;

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog({required this.onFailure, this.coordinator});
  final ValueChanged<String> onFailure;
  final AdminInvitationCoordinator? coordinator;
  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends _RequestState<_InviteDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  var _role = AdminAccountRole.staff;
  AdminInvitationPending? _attempt;
  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit({bool retry = false}) async {
    if (busy || _attempt == null && !_form.currentState!.validate()) return;
    final coordinator = widget.coordinator;
    AdminInvitationReceipt? receipt;
    final accepted = await request(() async {
      if (coordinator == null) {
        await ref
            .read(adminAccountApiProvider)
            .invite(
              _email.text.trim().toLowerCase(),
              _role,
              displayName: _name.text.trim(),
            );
      } else {
        _attempt ??= coordinator.prepareInvite(
          _email.text,
          _role,
          displayName: _name.text,
        );
        receipt = await coordinator.submit(
          _attempt!,
          confirmedSameIntentRetry: retry,
        );
      }
    });
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(
        context,
        _InviteResult(receipt: receipt, legacyAccepted: coordinator == null),
      );
    } else if (error != null) {
      widget.onFailure(error!);
    }
  }

  Future<void> _check() async {
    final coordinator = widget.coordinator, attempt = _attempt;
    if (busy || coordinator == null || attempt == null) return;
    AdminInvitationLookup? result;
    final checked = await request(() async {
      result = await coordinator.lookup(attempt);
    });
    if (!mounted || !checked) return;
    if (attempt.completed) {
      Navigator.pop(context, _InviteResult(receipt: result?.receipt));
    } else {
      setState(() => status = attempt.message);
    }
  }

  Future<void> _retry() async {
    final attempt = _attempt;
    if (attempt == null ||
        !attempt.canRetry ||
        !await _confirmInvitationRetry(context, attempt) ||
        !mounted) {
      return;
    }
    await _submit(retry: true);
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || _attempt != null;
    final coordinator = widget.coordinator, attempt = _attempt;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          coordinator?.usesV2 == true ? 'Add a teammate' : 'Invite a teammate',
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  coordinator?.usesV2 == true
                      ? 'Approve a teammate for Collect Admin. Collect selects an invitation or an access notice for an existing confirmed account. Email sending and sign-in are confirmed separately.'
                      : 'Invite a teammate to Collect Admin. They sign in with an email code. Sending and account access are confirmed separately.',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('admin-account-name'),
                  controller: _name,
                  enabled: !locked,
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
                _EmailField(controller: _email, enabled: !locked),
                const SizedBox(height: 18),
                DropdownButtonFormField<AdminAccountRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Workspace role',
                  ),
                  isExpanded: true,
                  items: [
                    for (final role in [
                      AdminAccountRole.staff,
                      AdminAccountRole.admin,
                    ])
                      DropdownMenuItem(value: role, child: Text(role.label)),
                  ],
                  onChanged: locked
                      ? null
                      : (role) => setState(() => _role = role!),
                ),
                const SizedBox(height: 12),
                Text(
                  _role == AdminAccountRole.staff
                      ? 'Staff can read operational records, create private groups and propose reconciliation allocations. They cannot publish groups or approve allocations.'
                      : 'Admins can manage workspace operations. Only the owner manages team access.',
                ),
                _Feedback(error: error, status: status),
                if (attempt != null) ...[
                  SelectableText(
                    'Original request: ${attempt.intent.requestKey}',
                  ),
                  if (attempt.intent.operation ==
                      AdminInvitationOperation.noticeRepair)
                    SelectableText(
                      'Registered-account source: ${attempt.intent.priorRequestId}',
                    ),
                  if (attempt.receipt != null)
                    SelectableText(
                      'Server reference: ${attempt.receipt!.requestId}',
                    ),
                  if (!attempt.completed)
                    TextButton.icon(
                      onPressed: busy || coordinator?.authorized != true
                          ? null
                          : _check,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Check original request'),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(attempt == null ? 'Cancel' : 'Close'),
          ),
          if (attempt == null)
            _SubmitButton(
              label: coordinator?.usesV2 == true
                  ? 'Add teammate'
                  : 'Send invitation',
              busy: busy,
              onPressed: _submit,
            ),
          if (attempt?.canRetry == true)
            _SubmitButton(
              label: 'Retry same request',
              busy: busy,
              onPressed: _retry,
            ),
        ],
      ),
    );
  }
}

class _TeamActions extends StatelessWidget {
  const _TeamActions({
    required this.member,
    required this.canManage,
    required this.busy,
    required this.onResend,
    required this.onRevoke,
    this.resendAllowed = true,
    this.repairAllowed = false,
    this.onRepair,
    this.resendLabel = 'Resend invitation',
  });
  final AdminAccountMember member;
  final bool canManage;
  final bool busy;
  final bool resendAllowed;
  final bool repairAllowed;
  final String resendLabel;
  final VoidCallback? onRepair;
  final VoidCallback onResend;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    if (!canManage || member.status == AdminAccountStatus.revoked) {
      return const Text('—');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (repairAllowed)
          TextButton(
            onPressed: busy ? null : onRepair,
            child: const Text('Send access notice'),
          ),
        if (member.status == AdminAccountStatus.invited)
          TextButton(
            onPressed: busy || !resendAllowed ? null : onResend,
            child: Text(resendLabel),
          ),
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
      try {
        normalizeAdminEmail(value ?? '');
        return null;
      } on FormatException {
        return 'Enter a valid email address.';
      }
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
