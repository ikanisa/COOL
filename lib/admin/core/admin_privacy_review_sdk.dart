import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_auth_guard.dart';
import 'admin_privacy_review_models.dart';

bool privacyReviewDenied(Object e) =>
    e is AdminSessionChanged ||
    e is AuthException ||
    e is PostgrestException &&
        const {
          '42501',
          '28000',
          'PGRST301',
          'PGRST302',
          'PGRST303',
        }.contains(e.code);

abstract interface class AdminPrivacyReviewApi {
  Future<AdminPrivacyReviewPage> list({
    int limit = 25,
    AdminPrivacyReviewCursor? before,
  });
  Future<AdminPrivacyReviewDetail> detail(String requestId);
  Future<Object> write(
    AdminPrivacyReviewIntent intent,
    AdminPrivacyReviewDetail detail,
  );
  Future<AdminPrivacyReviewOperation> resolve(AdminPrivacyReviewIntent intent);
}

class AdminPrivacyReviewSdk implements AdminPrivacyReviewApi {
  const AdminPrivacyReviewSdk({
    required this.rpc,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final String actorId, sessionId;
  // The concrete host binds the actual platform_owner role and BOTH read
  // permissions. Server fresh-session/roster checks remain authoritative.
  final bool Function() isCurrent;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  Future<Object?> _call(String name, Map<String, dynamic> params) async {
    _current();
    try {
      final value = await rpc(
        name,
        Map.unmodifiable(params),
      ).timeout(const Duration(seconds: 15));
      _current();
      return value;
    } catch (_) {
      _current();
      rethrow;
    }
  }

  T _fresh<T extends AdminPrivacyReviewEvidence>(T evidence) {
    _current();
    if (!evidence.fresh(now())) privacyReviewInvalid();
    return evidence;
  }

  void _bound(AdminPrivacyReviewIntent i) {
    _current();
    if (i.actorId != actorId || i.sessionId != sessionId) {
      privacyReviewInvalid();
    }
    AdminPrivacyReviewIntent.parse(i.row);
  }

  @override
  Future<AdminPrivacyReviewPage> list({
    int limit = 25,
    AdminPrivacyReviewCursor? before,
  }) async {
    if (limit < 1 || limit > 100) privacyReviewInvalid();
    return _fresh(
      AdminPrivacyReviewPage.parse(
        await _call('admin_list_account_deletion_reviews_v1', {
          'p_limit': limit,
          'p_before_accepted_at': before?.acceptedAt.toIso8601String(),
          'p_before_request_id': before?.requestId,
        }),
        limit: limit,
        before: before,
      ),
    );
  }

  @override
  Future<AdminPrivacyReviewDetail> detail(String requestId) async => _fresh(
    AdminPrivacyReviewDetail.parse(
      await _call('admin_get_account_deletion_review_v1', {
        'p_request_id': privacyReviewUuid(requestId),
      }),
      requestId,
    ),
  );
  @override
  Future<Object> write(
    AdminPrivacyReviewIntent intent,
    AdminPrivacyReviewDetail detail,
  ) async {
    _bound(intent);
    if (!intent.applicable(detail, now())) privacyReviewInvalid();
    final raw = await _call(intent.rpcName, intent.parameters);
    final Object receipt = intent.kind == AdminPrivacyReviewOperationKind.claim
        ? AdminPrivacyReviewClaim.parse(raw)
        : AdminPrivacyReviewOutcome.parse(raw);
    intent.checkReceipt(receipt);
    _current();
    return receipt;
  }

  @override
  Future<AdminPrivacyReviewOperation> resolve(
    AdminPrivacyReviewIntent intent,
  ) async {
    _bound(intent);
    return _fresh(
      AdminPrivacyReviewOperation.parse(
        await _call('admin_get_account_deletion_review_operation_v1', {
          'p_operation_kind': intent.kind.name,
          'p_operation_id': intent.operationId,
        }),
        intent,
      ),
    );
  }
}
