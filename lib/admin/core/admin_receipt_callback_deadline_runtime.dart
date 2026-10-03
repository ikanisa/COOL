import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_auth_guard.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_runtime.dart';
import 'admin_receipt_callback_deadline_models.dart';
import 'admin_receipt_successor_execution_sdk.dart';

class CallbackDeadlineDenied implements Exception {
  const CallbackDeadlineDenied();
}

abstract interface class CallbackDeadlineApi {
  Future<CallbackDeadlinePage> list(CallbackDeadlineQuery query);
  Future<CallbackDeadlineDetail> detail(
    String id, {
    int? cutoff,
    int? after,
    int limit = 20,
  });
}

class CallbackDeadlineSdk implements CallbackDeadlineApi {
  const CallbackDeadlineSdk({
    required this.rpc,
    required this.isCurrent,
    required this.now,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final bool Function() isCurrent;
  final DateTime Function() now;
  void _current() {
    if (!isCurrent()) throw const AdminSessionChanged();
  }

  Future<Object?> _read(String name, Map<String, dynamic> params) async {
    _current();
    try {
      final raw = await rpc(
        name,
        Map.unmodifiable(params),
      ).timeout(const Duration(seconds: 15));
      _current();
      return raw;
    } catch (error) {
      _current();
      if (executionAccessDenied(error)) throw const CallbackDeadlineDenied();
      rethrow;
    }
  }

  @override
  Future<CallbackDeadlinePage> list(CallbackDeadlineQuery query) async {
    final page = CallbackDeadlinePage.parse(
      await _read('admin_list_receipt_callback_deadlines_v1', query.parameters),
      query,
    );
    if (!page.fresh(now())) deadlineInvalid();
    return page;
  }

  @override
  Future<CallbackDeadlineDetail> detail(
    String id, {
    int? cutoff,
    int? after,
    int limit = 20,
  }) async {
    cancelDeadlineDetailQuery(id, cutoff, after, limit);
    final value = CallbackDeadlineDetail.parse(
      await _read('admin_get_receipt_callback_deadline_v1', {
        'p_case_id': id,
        'p_cutoff_revision': cutoff,
        'p_after_revision': after,
        'p_limit': limit,
      }),
      id,
      cutoff: cutoff,
      after: after,
      limit: limit,
    );
    if (!value.fresh(now())) deadlineInvalid();
    return value;
  }
}

void cancelDeadlineDetailQuery(String id, int? cutoff, int? after, int limit) {
  // Parser validation is shared, including canonical UUID and complete pairs.
  if ((cutoff == null) != (after == null) ||
      limit < 1 ||
      limit > 25 ||
      cutoff != null && (cutoff < 1 || after! < 1 || after >= cutoff)) {
    deadlineInvalid();
  }
  cancelUuid(id);
}

final adminCallbackDeadlineApiProvider =
    Provider.autoDispose<CallbackDeadlineApi?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          repository = ref.watch(adminRepositoryProvider),
          state = ref.watch(adminIdentityProvider);
      final identity = state.isLoading || state.hasError
          ? null
          : state.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !identity.roles.contains('platform_owner') ||
          !{
            'payments.read',
            'notifications.read',
            'system_health.read',
          }.every(identity.permissions.contains) ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      return CallbackDeadlineSdk(
        rpc: (name, params) =>
            repository.rpcMap(name, params: params, automaticRetry: false),
        isCurrent: () =>
            current &&
            ref.read(adminAuthSessionScopeProvider) == scope &&
            identical(ref.read(adminRepositoryProvider), repository),
        now: ref.watch(adminClockProvider),
      );
    });

class CallbackDeadlineController extends ChangeNotifier {
  CallbackDeadlineController(this.api);
  final CallbackDeadlineApi api;
  CallbackDeadlineQuery? query;
  CallbackDeadlinePage? page;
  final rows = <CallbackDeadlineRow>[];
  CallbackDeadlineDetail? detail;
  final observations = <Object?>[];
  bool busy = false, disposed = false;
  int generation = 0;
  Object? error;
  void _forget() {
    page = null;
    rows.clear();
    detail = null;
    observations.clear();
  }

  bool _owns(int value) => !disposed && generation == value;
  Future<void> load(CallbackDeadlineQuery value) async {
    final token = ++generation;
    query = value;
    _forget();
    busy = true;
    error = null;
    notifyListeners();
    try {
      final next = await api.list(value);
      if (!_owns(token)) return;
      page = next;
      rows.addAll(next.items);
    } catch (failure) {
      if (!_owns(token)) return;
      _forget();
      error = failure;
    } finally {
      if (_owns(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> more() async {
    final cursor = page?.next, owned = query;
    if (cursor == null || owned == null || busy) return;
    final token = generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final next = await api.list(
        CallbackDeadlineQuery(
          family: owned.family,
          active: owned.active,
          limit: owned.limit,
          cursor: cursor,
        ),
      );
      if (!_owns(token)) return;
      final ids = rows.map((r) => r.id).toSet();
      if (next.items.any((r) => ids.contains(r.id))) deadlineInvalid();
      page = next;
      rows.addAll(next.items);
    } catch (failure) {
      if (!_owns(token)) return;
      error = failure;
      if (failure is CallbackDeadlineDenied ||
          failure is AdminSessionChanged ||
          executionAccessDenied(failure)) {
        _forget();
      }
    } finally {
      if (_owns(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> inspect(String id, {bool more = false}) async {
    if (busy || more && detail?.next == null) return;
    final token = generation;
    final current = detail;
    if (!more) {
      detail = null;
      observations.clear();
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final next = await api.detail(
        id,
        cutoff: more ? current?.cutoff : null,
        after: more ? current?.next : null,
      );
      if (!_owns(token)) return;
      if (next.head == null) {
        detail = null;
        observations.clear();
      } else {
        detail = next;
        observations.addAll(next.row['items'] as List);
      }
    } catch (failure) {
      if (!_owns(token)) return;
      error = failure;
      if (!more ||
          failure is CallbackDeadlineDenied ||
          failure is AdminSessionChanged ||
          executionAccessDenied(failure)) {
        detail = null;
        observations.clear();
        if (failure is CallbackDeadlineDenied ||
            failure is AdminSessionChanged ||
            executionAccessDenied(failure)) {
          _forget();
        }
      }
    } finally {
      if (_owns(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    _forget();
    super.dispose();
  }
}
