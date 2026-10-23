import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../shared/widgets/collect_components.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_auth_guard.dart';
import 'admin_privacy_review_checkpoint.dart';
import 'admin_privacy_review_controller.dart';
import 'admin_privacy_review_models.dart';
import 'admin_privacy_review_sdk.dart';
import 'admin_privacy_review_view.dart';
import 'cloudflare_admin_retention_inspection.dart';
import 'cloudflare_admin_session.dart';

final cloudflareAdminPrivacyClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);
final cloudflareAdminPrivacyStoreProvider = Provider<AdminPrivacyReviewStore?>(
  (ref) => browserPrivacyReviewStore(),
);

String _privacySignInMessage(CloudflareAdminUser? user) =>
    user?.usesEmailVerification == true
    ? 'Verify your email to reopen privacy review. Verification must be less than five minutes old.'
    : 'Sign in again, then verify your authenticator to reopen privacy review. Both checks must be less than five minutes old.';

bool cloudflareAdminPrivacyIdentityAllows(
  CloudflareAdminUser? user, {
  DateTime? now,
}) {
  if (user == null ||
      !user.permissions.contains('privacy.review') ||
      !user.hasRecentSensitiveVerification(now: now)) {
    return false;
  }
  try {
    privacyReviewUuid(user.principalId);
    privacyReviewUuid(user.sessionId);
    return true;
  } on FormatException {
    return false;
  }
}

/// Uses only the current HttpOnly-cookie transport. The principal and PUBLIC
/// cookie session UUID namespace the local durable journal; the public UUID is
/// not auth_sessions.id. Neither value is sent as RPC authority. The server
/// derives its canonical principal/auth-session binding from the cookie.
class CloudflareAdminPrivacyAccess {
  CloudflareAdminPrivacyAccess({
    required this.session,
    required this.user,
    required this.now,
    this.onDenied,
  }) : _fence = session.authorityFence;

  final CloudflareAdminSession session;
  final CloudflareAdminUser user;
  final DateTime Function() now;
  final VoidCallback? onDenied;
  final ({int epoch, Object? key}) _fence;
  bool _alive = true;
  CloudflareAdminRetentionContext? _context;
  CloudflareAdminRetentionContext? get context => _context;

  bool get _baseCurrent =>
      _alive &&
      session.mounted &&
      session.authorityFence == _fence &&
      session.user?.authorityKey == user.authorityKey &&
      cloudflareAdminPrivacyIdentityAllows(session.user, now: now()) &&
      session.user!.expiresAt.isAfter(now());

  DateTime? get validUntil {
    final contextUntil = context?.validUntil;
    final verifiedAt = session.user?.sensitiveVerificationAt;
    if (contextUntil == null || verifiedAt == null) return null;
    final proofUntil = verifiedAt.add(const Duration(minutes: 5));
    return proofUntil.isBefore(contextUntil) ? proofUntil : contextUntil;
  }

  bool isCurrent() =>
      _baseCurrent &&
      context?.fresh(now()) == true &&
      validUntil?.isAfter(now()) == true;

  void close() => _alive = false;

  void _deny() {
    if (!_alive) return;
    _alive = false;
    onDenied?.call();
  }

  static const _operations = {
    'admin_list_account_deletion_reviews_v1',
    'admin_get_account_deletion_review_v1',
    'admin_claim_account_deletion_review_v1',
    'admin_record_account_deletion_review_v1',
    'admin_get_account_deletion_review_operation_v1',
    'admin_get_account_retention_context_v1',
    'admin_inspect_account_retention_scope_v1',
  };

  Future<Object?> rpc(String name, Map<String, dynamic> parameters) async {
    if (!_operations.contains(name)) {
      throw ArgumentError('Unsupported privacy review operation.');
    }
    final opening = name == 'admin_get_account_retention_context_v1';
    if (!_baseCurrent || (!opening && !isCurrent())) {
      _deny();
      throw const AdminSessionChanged();
    }
    try {
      final result = await session.request(
        'privacy/$name',
        body: parameters,
        authenticated: true,
      );
      if (!_baseCurrent || (!opening && !isCurrent())) {
        _deny();
        throw const AdminSessionChanged();
      }
      return result;
    } catch (error) {
      if (!_baseCurrent ||
          error is CloudflareAdminRequestException &&
              const {401, 403}.contains(error.statusCode)) {
        _deny();
        throw const AdminSessionChanged();
      }
      rethrow;
    }
  }

  Future<void> initialize() async {
    final result = await rpc('admin_get_account_retention_context_v1', {});
    final observed = await CloudflareAdminRetentionContext.receive(result, now);
    if (!_baseCurrent) throw const AdminSessionChanged();
    _context = observed;
  }

  AdminPrivacyReviewSdk get review => AdminPrivacyReviewSdk(
    rpc: rpc,
    actorId: user.principalId!,
    sessionId: user.sessionId,
    isCurrent: isCurrent,
    now: now,
  );

  CloudflareAdminRetentionInspectionApi get inspection =>
      CloudflareAdminRetentionInspectionApi(
        rpc: rpc,
        context: context!,
        actorId: user.principalId!,
        isCurrent: isCurrent,
        now: now,
      );
}

class CloudflareAdminPrivacyReviewPageHost extends ConsumerWidget {
  const CloudflareAdminPrivacyReviewPageHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudflareAdminSessionProvider);
    if (state.isLoading) return const _PrivacyLoading();
    final user = state.hasError ? null : state.asData?.value;
    final now = ref.watch(cloudflareAdminPrivacyClockProvider);
    if (!cloudflareAdminPrivacyIdentityAllows(user, now: now())) {
      return _PrivacyUnavailable(
        needsSignIn: true,
        user: user,
        canVerify:
            user?.permissions.contains('privacy.review') == true &&
            (user?.usesEmailVerification == true || user?.assuranceLevel == 1),
      );
    }
    final session = ref.read(cloudflareAdminSessionProvider.notifier);
    final store = ref.watch(cloudflareAdminPrivacyStoreProvider);
    return _CookieReviewHost(
      key: ValueKey((session.authorityFence, store, now)),
      session: session,
      user: user!,
      store: store,
      now: now,
    );
  }
}

class _CookieReviewHost extends StatefulWidget {
  const _CookieReviewHost({
    required this.session,
    required this.user,
    required this.store,
    required this.now,
    super.key,
  });
  final CloudflareAdminSession session;
  final CloudflareAdminUser user;
  final AdminPrivacyReviewStore? store;
  final DateTime Function() now;

  @override
  State<_CookieReviewHost> createState() => _CookieReviewHostState();
}

class _CookieReviewHostState extends State<_CookieReviewHost> {
  late final CloudflareAdminPrivacyAccess _access;
  AdminPrivacyReviewController? _controller;
  Timer? _expiry;
  bool _loading = true, _denied = false;

  @override
  void initState() {
    super.initState();
    _access = CloudflareAdminPrivacyAccess(
      session: widget.session,
      user: widget.user,
      now: widget.now,
      onDenied: _deny,
    );
    unawaited(_load());
  }

  void _deny() {
    if (!mounted) return;
    _access.close();
    _expiry?.cancel();
    _controller?.dispose();
    _controller = null;
    setState(() {
      _denied = true;
      _loading = false;
    });
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    if (!_access.isCurrent()) {
      _deny();
      return;
    }
    _expiry = Timer(_access.validUntil!.difference(widget.now()), _deny);
  }

  @override
  void didUpdateWidget(covariant _CookieReviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller != null &&
        !_denied &&
        oldWidget.user.sensitiveVerificationAt !=
            widget.user.sensitiveVerificationAt) {
      _scheduleExpiry();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _access.initialize();
      if (!mounted || !_access.isCurrent()) {
        _deny();
        return;
      }
      _controller = AdminPrivacyReviewController(
        api: _access.review,
        actorId: widget.user.principalId!,
        sessionId: widget.user.sessionId,
        store: widget.store,
        now: widget.now,
        isCurrent: _access.isCurrent,
        newOperationId: () => const Uuid().v4(),
        deniedMessage: _privacySignInMessage(widget.user),
      );
      _scheduleExpiry();
    } catch (error) {
      if (error is AdminSessionChanged) _deny();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _PrivacyLoading();
    if (_denied) {
      return _PrivacyUnavailable(
        needsSignIn: true,
        user: widget.user,
        canVerify: widget.user.usesEmailVerification,
      );
    }
    final controller = _controller;
    if (controller == null) {
      return _PrivacyUnavailable(
        needsSignIn: false,
        user: widget.user,
        retry: _load,
      );
    }
    return AdminPrivacyReviewView(
      controller: controller,
      selectedDetailSupplement: (_, detail) =>
          CloudflareAdminRetentionInspectionPanel(
            key: ValueKey((
              detail.item!.requestId,
              detail.item!.revision,
              detail.checkedAt,
            )),
            api: _access.inspection,
            detail: detail,
            onAccessLost: _deny,
          ),
    );
  }

  @override
  void dispose() {
    _access.close();
    _expiry?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}

class _PrivacyLoading extends StatelessWidget {
  const _PrivacyLoading();
  @override
  Widget build(BuildContext context) => const AdminPage(
    title: 'Privacy requests',
    child: AdminLoadingState(
      title: 'Checking privacy review access',
      message: 'Verifying your current privacy review access.',
    ),
  );
}

class _PrivacyUnavailable extends ConsumerWidget {
  const _PrivacyUnavailable({
    required this.needsSignIn,
    this.user,
    this.canVerify = false,
    this.retry,
  });
  final bool needsSignIn, canVerify;
  final CloudflareAdminUser? user;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AdminPage(
    title: 'Privacy requests',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminEmptyState(
          title: needsSignIn
              ? 'Fresh privacy review access required'
              : 'Privacy review temporarily unavailable',
          message: needsSignIn
              ? _privacySignInMessage(user)
              : 'The current review context could not be verified. No review action was sent.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (canVerify)
              CollectButton(
                label: user?.usesEmailVerification == true
                    ? 'Verify email'
                    : 'Verify authenticator',
                icon: Icons.verified_user_outlined,
                onPressed: () {
                  if (user?.usesEmailVerification == true) {
                    context.go(
                      Uri(
                        path: '/admin/security/verify-email',
                        queryParameters: {
                          'returnTo': GoRouterState.of(context).uri.toString(),
                        },
                      ).toString(),
                    );
                  } else {
                    context.go('/admin/security/authenticator');
                  }
                },
              ),
            if (needsSignIn)
              CollectButton(
                label: 'Sign in again',
                icon: Icons.login,
                variant: CollectButtonVariant.secondary,
                onPressed: () {
                  ref.read(cloudflareAdminSessionProvider.notifier).clear();
                  context.go(
                    '/admin/login?returnTo=%2Fadmin%2Fprivacy-requests',
                  );
                },
              ),
            if (retry != null)
              CollectButton(
                label: 'Recheck privacy access',
                icon: Icons.refresh,
                onPressed: retry,
              ),
          ],
        ),
      ],
    ),
  );
}
