import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_colors.dart';
import '../shared/components/admin_page.dart';
import 'admin_account_api.dart';
import 'admin_account_pages.dart';
import 'cloudflare_admin_email_verification_page.dart';
import 'cloudflare_admin_session.dart';

final _factorIdPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

const _invalidAuthenticator = AdminAccountException(
  'The authenticator response could not be verified. Recheck your session.',
);

class CloudflareAdminMfaFactor {
  const CloudflareAdminMfaFactor({
    required this.id,
    required this.name,
    required this.verified,
  });
  final String id;
  final String name;
  final bool verified;

  factory CloudflareAdminMfaFactor.parse(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        !_factorIdPattern.hasMatch(value['id'] as String) ||
        value['factor_type'] != 'totp' ||
        !const {'verified', 'unverified'}.contains(value['status'])) {
      throw _invalidAuthenticator;
    }
    final name = value['friendly_name'] ?? 'Authenticator';
    if (name is! String ||
        name.isEmpty ||
        name.length > 64 ||
        RegExp(r'[\x00-\x1f]').hasMatch(name)) {
      throw _invalidAuthenticator;
    }
    return CloudflareAdminMfaFactor(
      id: value['id'] as String,
      name: name,
      verified: value['status'] == 'verified',
    );
  }
}

/// One-use enrollment material, retained only by the current setup widget.
/// Ordinary factor lists never carry the key or authenticator URI.
class CloudflareAdminMfaSetup {
  const CloudflareAdminMfaSetup({required this.factor, required this.secret});
  final CloudflareAdminMfaFactor factor;
  final String secret;

  factory CloudflareAdminMfaSetup.parse(
    Map<String, dynamic> value,
    CloudflareAdminUser user,
  ) {
    final factor = CloudflareAdminMfaFactor.parse(value);
    final totp = value['totp'];
    if (factor.verified ||
        totp is! Map ||
        totp['secret'] is! String ||
        !RegExp(r'^[A-Z2-7]{32}$').hasMatch(totp['secret'] as String) ||
        totp['uri'] is! String) {
      throw _invalidAuthenticator;
    }
    final uri = Uri.tryParse(totp['uri'] as String);
    if (uri == null ||
        uri.scheme != 'otpauth' ||
        uri.host != 'totp' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        uri.pathSegments.single != 'Collect:${user.email}') {
      throw _invalidAuthenticator;
    }
    final parameters = uri.queryParametersAll;
    final expected = {
      'secret': totp['secret'] as String,
      'issuer': 'Collect',
      'algorithm': 'SHA1',
      'digits': '6',
      'period': '30',
    };
    if (parameters.length != expected.length ||
        expected.entries.any(
          (entry) =>
              parameters[entry.key]?.length != 1 ||
              parameters[entry.key]!.single != entry.value,
        )) {
      throw _invalidAuthenticator;
    }
    return CloudflareAdminMfaSetup(
      factor: factor,
      secret: totp['secret'] as String,
    );
  }
}

class CloudflareAdminMfaApi {
  CloudflareAdminMfaApi(this.session);
  final CloudflareAdminSession session;

  CloudflareAdminUser _actor() {
    if (session.usesEmailVerification) {
      throw const AdminAccountException(
        'Verify your email to confirm sensitive changes.',
      );
    }
    final user = session.user;
    if (user == null || user.principalId == null) {
      throw const AdminAccountException(
        'Sign in again to use your authenticator.',
      );
    }
    return user;
  }

  Future<List<CloudflareAdminMfaFactor>> factors() async {
    final user = _actor();
    final value = await session.request('auth/user', authenticated: true);
    final factors = value['factors'];
    if (value['id'] != user.principalId ||
        factors is! List ||
        factors.length > 128) {
      throw _invalidAuthenticator;
    }
    final parsed = factors.map(CloudflareAdminMfaFactor.parse).toList();
    if (parsed.map((factor) => factor.id).toSet().length != parsed.length) {
      throw _invalidAuthenticator;
    }
    return List<CloudflareAdminMfaFactor>.unmodifiable(parsed);
  }

  Future<CloudflareAdminMfaSetup> enroll() async {
    final user = _actor();
    if (!user.permissions.contains('auth.mfa.enroll')) {
      throw const AdminAccountException(
        'Ask the owner to enable authenticator setup.',
      );
    }
    final result = await session.request(
      'auth/mfa/enroll',
      authenticated: true,
      body: const {'friendly_name': 'Collect Admin', 'factor_type': 'totp'},
    );
    return CloudflareAdminMfaSetup.parse(result, user);
  }

  Future<void> verify(CloudflareAdminMfaFactor factor, String code) async {
    _actor();
    if (!_factorIdPattern.hasMatch(factor.id) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const AdminAccountException(
        'Enter the six-digit authenticator code.',
      );
    }
    final fence = session.authorityFence;
    final result = await session.request(
      'auth/mfa/challenge',
      authenticated: true,
      body: {'factor_id': factor.id},
    );
    final challengeId = result['challenge_id'];
    final expiresAt = result['expires_at'];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (challengeId is! String ||
        !_factorIdPattern.hasMatch(challengeId) ||
        result['id'] != challengeId ||
        expiresAt is! int ||
        expiresAt <= now ||
        expiresAt > now + 600) {
      throw _invalidAuthenticator;
    }
    if (session.authorityFence != fence) {
      throw const AdminAccountException(
        'Your session changed. Reopen this page.',
      );
    }
    await session.verifyAuthenticator(
      factorId: factor.id,
      challengeId: challengeId,
      code: code,
    );
  }

  Future<void> cancelPending(CloudflareAdminMfaFactor factor) async {
    final user = _actor();
    if (factor.verified ||
        !_factorIdPattern.hasMatch(factor.id) ||
        !user.permissions.contains('auth.mfa.enroll')) {
      throw const AdminAccountException(
        'Only an owned pending setup can be cancelled.',
      );
    }
    final result = await session.request(
      'auth/mfa/cancel-enrollment',
      authenticated: true,
      body: {'factor_id': factor.id},
    );
    if (result['id'] != factor.id ||
        result['factor_type'] != 'totp' ||
        result['status'] != 'revoked') {
      throw const CloudflareAdminRequestException(
        'Cancellation could not be confirmed. Recheck the pending setup.',
        outcomeUnknown: true,
      );
    }
  }
}

/// Keeps the existing password task and selected backend verification route.
class CloudflareAdminSecurityPage extends ConsumerWidget {
  const CloudflareAdminSecurityPage({this.onSignIn, super.key});
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email =
        ref
            .watch(cloudflareAdminSessionProvider)
            .asData
            ?.value
            ?.usesEmailVerification ==
        true;
    return Material(
      color: context.collectColors.canvas,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ListTile(
              leading: Icon(
                email
                    ? Icons.mark_email_read_outlined
                    : Icons.phonelink_lock_outlined,
              ),
              title: Text(email ? 'Verify email' : 'Authenticator'),
              subtitle: Text(
                email
                    ? 'Confirm sensitive changes with an email code.'
                    : 'Set up or verify two-step access.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(
                email
                    ? '/admin/security/verify-email'
                    : '/admin/security/authenticator',
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Open-source licenses'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/admin/licenses'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AdminAccountSecurityPage(
              onSignIn: onSignIn,
              onPasswordRecovery: email
                  ? () => context.go('/admin/forgot-password')
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class CloudflareAdminMfaPage extends ConsumerWidget {
  const CloudflareAdminMfaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cloudflareAdminSessionProvider);
    final session = ref.read(cloudflareAdminSessionProvider.notifier);
    if (session.usesEmailVerification) {
      return const CloudflareAdminEmailVerificationPage();
    }
    return AdminPage(
      title: 'Authenticator',
      leading: IconButton(
        tooltip: 'Back to account security',
        onPressed: () => context.go('/admin/security'),
        icon: const Icon(Icons.arrow_back),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _AuthenticatorTask(
            key: ValueKey(session.authorityFence),
            session: session,
          ),
        ),
      ),
    );
  }
}

class _AuthenticatorTask extends StatefulWidget {
  const _AuthenticatorTask({required this.session, super.key});
  final CloudflareAdminSession session;

  @override
  State<_AuthenticatorTask> createState() => _AuthenticatorTaskState();
}

class _AuthenticatorTaskState extends State<_AuthenticatorTask> {
  final _code = TextEditingController();
  List<CloudflareAdminMfaFactor> _factors = const [];
  CloudflareAdminMfaSetup? _setup;
  String? _selectedId;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _unknown = false;
  int _operation = 0;

  CloudflareAdminMfaApi get _api => CloudflareAdminMfaApi(widget.session);
  CloudflareAdminMfaFactor? get _factor {
    if (_setup != null) return _setup!.factor;
    for (final factor in _factors) {
      if (factor.id == _selectedId) return factor;
    }
    return _factors.isEmpty ? null : _factors.first;
  }

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_load));
  }

  @override
  void dispose() {
    ++_operation;
    _setup = null;
    _code.dispose();
    super.dispose();
  }

  Future<void> _execute<T>(
    Future<T> Function() work,
    void Function(T) apply,
  ) async {
    if (!mounted || _busy) return;
    final operation = ++_operation;
    final fence = widget.session.authorityFence;
    bool current() =>
        mounted &&
        operation == _operation &&
        fence == widget.session.authorityFence;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await work();
      if (!current()) return;
      setState(() {
        apply(value);
        _unknown = false;
      });
    } catch (failure) {
      if (!current()) return;
      setState(() {
        _error = _authenticatorError(failure);
        _unknown =
            failure is CloudflareAdminRequestException &&
            failure.outcomeUnknown;
      });
    } finally {
      if (current()) {
        _code.clear();
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _load() => _execute(_api.factors, (factors) {
    _factors = factors;
    if (_setup != null &&
        !factors.any(
          (factor) => factor.id == _setup!.factor.id && !factor.verified,
        )) {
      _setup = null;
    }
    if (!factors.any((factor) => factor.id == _selectedId)) {
      _selectedId = factors.isEmpty ? null : factors.first.id;
    }
  });

  Future<void> _enroll() => _execute(_api.enroll, (setup) {
    _setup = setup;
    _selectedId = setup.factor.id;
  });

  Future<void> _verify() async {
    final factor = _factor;
    if (factor == null || _unknown || _busy) return;
    final code = _code.text;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the six-digit authenticator code.');
      return;
    }
    _code.clear();
    await _execute(() => _api.verify(factor, code), (_) {});
  }

  Future<void> _cancel() async {
    final factor = _factor;
    if (factor == null || factor.verified || _busy || _unknown) return;
    final fence = widget.session.authorityFence;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel authenticator setup?'),
        content: const Text(
          'This removes the pending setup. You can then connect a new authenticator.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep setup'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel setup'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        widget.session.authorityFence != fence) {
      return;
    }
    await _execute(
      () async {
        await _api.cancelPending(factor);
        return _api.factors();
      },
      (factors) {
        _setup = null;
        _factors = factors;
        _selectedId = null;
      },
    );
  }

  void _signIn() {
    widget.session.clear();
    context.go('/admin/login?returnTo=%2Fadmin%2Fsecurity%2Fauthenticator');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final user = widget.session.user;
    final factor = _factor;
    final canEnroll = user?.permissions.contains('auth.mfa.enroll') == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (user?.assuranceLevel == 2) ...[
          const Text('Two-step verification is complete for this session.'),
          const SizedBox(height: 16),
        ],
        if (!_loading && factor == null && _error == null)
          const Text(
            'Connect an authenticator to verify protected account actions.',
          ),
        if (_setup != null) ...[
          const Text(
            'Add this key to your authenticator as Collect, then enter its six-digit code.',
          ),
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('cloudflare_admin_mfa_setup'),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Setup key',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _setup!.secret,
                  key: const ValueKey('cloudflare_admin_mfa_secret'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ] else if (factor != null && !factor.verified) ...[
          const Text(
            'Setup is pending. Enter a code if you saved the key, or cancel this setup and connect again.',
          ),
          const SizedBox(height: 20),
        ],
        if (_factors.length > 1 && _setup == null) ...[
          DropdownButtonFormField<String>(
            key: ValueKey(_factors.map((factor) => factor.id).join(',')),
            initialValue: factor?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Authenticator'),
            items: [
              for (final factor in _factors)
                DropdownMenuItem(value: factor.id, child: Text(factor.name)),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _selectedId = value),
          ),
          const SizedBox(height: 16),
        ],
        if (factor != null) ...[
          TextField(
            key: const ValueKey('cloudflare_admin_mfa_code'),
            controller: _code,
            decoration: const InputDecoration(labelText: 'Authenticator code'),
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            enabled: !_busy && !_unknown,
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('cloudflare_admin_mfa_verify'),
            onPressed: _busy || _unknown ? null : _verify,
            child: Text(_busy ? 'Verifying…' : 'Verify code'),
          ),
          if (!factor.verified && canEnroll)
            TextButton(
              key: const ValueKey('cloudflare_admin_mfa_cancel'),
              onPressed: _busy || _unknown ? null : _cancel,
              child: const Text('Cancel pending setup'),
            ),
        ] else if (!_loading && canEnroll) ...[
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('cloudflare_admin_mfa_enroll'),
            onPressed: _busy || _unknown ? null : _enroll,
            child: Text(_busy ? 'Connecting…' : 'Connect authenticator'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('cloudflare_admin_mfa_error'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.danger),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Recheck setup'),
          ),
          TextButton(
            onPressed: _busy ? null : _signIn,
            child: const Text('Sign in again'),
          ),
        ],
      ],
    );
  }
}

String _authenticatorError(Object failure) {
  if (failure is CloudflareAdminRequestException) {
    return switch (failure.code) {
      'fresh_auth_required' =>
        'Sign in again before changing authenticator setup.',
      'enrollment_pending' =>
        'A setup is already pending. Recheck it before continuing.',
      'mfa_required' =>
        'Verify your current authenticator before changing setup.',
      'mfa_challenge_unavailable' =>
        'This setup can no longer be verified. Cancel it after signing in again.',
      'mfa_verification_failed' =>
        'The code was not verified. Enter a new authenticator code.',
      _ => failure.message,
    };
  }
  return failure is AdminAccountException
      ? failure.message
      : 'Authenticator access is unavailable. Recheck your session.';
}
