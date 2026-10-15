import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'admin_auth_guard.dart';
import 'admin_models.dart';
import 'admin_runtime.dart';
import 'admin_privacy_review_checkpoint.dart';
import 'admin_privacy_review_controller.dart';
import 'admin_privacy_review_sdk.dart';
import 'admin_privacy_review_view.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';

bool adminPrivacyReviewIdentityAllows(AdminIdentity identity) =>
    identity.roles.contains('platform_owner') &&
    {'users.read', 'audit.read'}.every(identity.permissions.contains);

class AdminPrivacyReviewAccess {
  const AdminPrivacyReviewAccess({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
  });
  final AdminPrivacyReviewApi api;
  final String actorId, sessionId;
  final bool Function() isCurrent;
}

final adminPrivacyReviewStoreProvider = Provider<AdminPrivacyReviewStore?>(
  (ref) => browserPrivacyReviewStore(),
);
final adminPrivacyReviewAccessProvider =
    Provider.autoDispose<AdminPrivacyReviewAccess?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          repository = ref.watch(adminRepositoryProvider),
          state = ref.watch(adminIdentityProvider);
      final identity = state.isLoading || state.hasError
          ? null
          : state.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !adminPrivacyReviewIdentityAllows(identity) ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      ref.listen(adminRepositoryProvider, (_, _) => current = false);
      bool valid() {
        if (!current) return false;
        final currentIdentity = ref.read(adminIdentityProvider);
        final resolved = currentIdentity.isLoading || currentIdentity.hasError
            ? null
            : currentIdentity.asData?.value;
        if (ref.read(adminAuthSessionScopeProvider) != scope ||
            !identical(ref.read(adminRepositoryProvider), repository) ||
            resolved == null ||
            resolved.userId != identity.userId ||
            !adminPrivacyReviewIdentityAllows(resolved) ||
            resolved.roles.length != identity.roles.length ||
            !resolved.roles.toSet().containsAll(identity.roles) ||
            resolved.permissions.length != identity.permissions.length ||
            !resolved.permissions.toSet().containsAll(identity.permissions)) {
          current = false;
        }
        return current;
      }

      return AdminPrivacyReviewAccess(
        api: AdminPrivacyReviewSdk(
          // AdminRepository.rpcMap owns AdminRequestSession and sends its captured
          // Authorization token. Reads and writes explicitly disable retries.
          rpc: (name, params) =>
              repository.rpcMap(name, params: params, automaticRetry: false),
          actorId: scope.key.userId,
          sessionId: scope.key.sessionId,
          isCurrent: valid,
          now: ref.watch(adminClockProvider),
        ),
        actorId: scope.key.userId,
        sessionId: scope.key.sessionId,
        isCurrent: valid,
      );
    });

class AdminPrivacyReviewPageHost extends ConsumerWidget {
  const AdminPrivacyReviewPageHost({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider),
        access = ref.watch(adminPrivacyReviewAccessProvider);
    if (identity.isLoading) {
      return const AdminPage(
        title: 'Privacy requests',
        child: AdminLoadingState(
          title: 'Checking privacy review access',
          message: 'Checking your current Admin session.',
        ),
      );
    }
    if (access == null) {
      return const AdminPage(
        title: 'Privacy requests',
        child: AdminEmptyState(
          title: 'Privacy review access required',
          message:
              'A current platform owner with users read and audit read permissions is required. Sign in again or request access.',
        ),
      );
    }
    return _ControllerHost(key: ValueKey(access), access: access);
  }
}

class _ControllerHost extends ConsumerStatefulWidget {
  const _ControllerHost({required this.access, super.key});
  final AdminPrivacyReviewAccess access;
  @override
  ConsumerState<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends ConsumerState<_ControllerHost> {
  AdminPrivacyReviewController? _controller;
  AdminPrivacyReviewStore? _store;
  bool _configured = false;
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(adminPrivacyReviewStoreProvider);
    if (!_configured || !identical(_store, store)) {
      _controller?.dispose();
      _store = store;
      _configured = true;
      final a = widget.access;
      _controller = AdminPrivacyReviewController(
        api: a.api,
        actorId: a.actorId,
        sessionId: a.sessionId,
        store: store,
        now: ref.read(adminClockProvider),
        isCurrent: a.isCurrent,
        newOperationId: () => const Uuid().v4(),
      );
    }
    return AdminPrivacyReviewView(
      key: ValueKey(_controller),
      controller: _controller!,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
