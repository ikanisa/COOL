import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloudflare/cloudflare_module.dart';
import '../../shared/providers/collect_app_state.dart'
    show ProfileReadiness, profileReadinessProvider;
import '../../shared/providers/pending_shared_group_intent_provider.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/repositories/pending_shared_group_intent_store.dart';
import '../router.dart';

final collectIncomingAppLinksProvider = Provider<Stream<Uri>>(
  (ref) => const Stream<Uri>.empty(),
);

class PendingGroupIntentHost extends ConsumerStatefulWidget {
  const PendingGroupIntentHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PendingGroupIntentHost> createState() =>
      _PendingGroupIntentHostState();
}

class _PendingGroupIntentHostState
    extends ConsumerState<PendingGroupIntentHost> {
  StreamSubscription<Uri>? _appLinkSubscription;
  var _recoveryScheduled = false;
  String? _navigationTarget;

  @override
  void initState() {
    super.initState();
    _appLinkSubscription = ref
        .read(collectIncomingAppLinksProvider)
        .listen(
          (uri) => unawaited(_acceptIncomingAppLink(uri)),
          onError: (_) {
            // Platform-channel availability must not make normal app startup
            // fail. A received link still fails closed if it cannot persist.
          },
        );
    _scheduleRecovery();
  }

  @override
  void dispose() {
    unawaited(_appLinkSubscription?.cancel());
    super.dispose();
  }

  Future<void> _acceptIncomingAppLink(Uri uri) async {
    final target = collectAppLinkTargetFromUri(uri);
    if (target == null) return;
    switch (target.kind) {
      case CollectAppLinkKind.group:
        final slug = target.value!;
        try {
          await ref
              .read(pendingSharedGroupSlugProvider.notifier)
              .retainIncomingRecord(
                slug,
                ownerUserId: ref.read(collectAuthenticatedUserIdProvider),
              );
          if (!mounted) return;
          _scheduleNavigation('/c/${Uri.encodeComponent(slug)}');
        } catch (_) {
          // Never navigate from a link that was not durably retained.
        }
        return;
      case CollectAppLinkKind.app:
      case CollectAppLinkKind.invite:
        _scheduleNavigation(
          ref.read(collectRepositoryProvider).currentProfile == null
              ? '/auth'
              : '/home',
        );
        return;
    }
  }

  void _scheduleRecovery() {
    if (_recoveryScheduled) return;
    _recoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoveryScheduled = false;
      unawaited(_recover());
    });
  }

  Future<void> _recover() async {
    try {
      final pendingIntent = ref.read(pendingSharedGroupSlugProvider.notifier);
      final ownerId = ref.read(collectAuthenticatedUserIdProvider);
      if (ownerId == null) return;
      final intent = await pendingIntent.currentRecordForOwner(ownerId);
      if (!mounted || intent == null) return;
      final readiness = ref.read(profileReadinessProvider);
      if (!readiness.readyForGroupCreation) return;

      final router = ref.read(appRouterProvider);
      final intentPath = '/c/${Uri.encodeComponent(intent.slug)}';
      if (router.routeInformationProvider.value.uri.path == intentPath) return;
      _scheduleNavigation(intentPath);
    } catch (_) {
      // Local persistence can fail while binding or clearing a pending link.
      // A link must never navigate from a record that could not be verified.
    }
  }

  void _scheduleNavigation(String target) {
    final router = ref.read(appRouterProvider);
    if (router.routeInformationProvider.value.uri.path == target) return;
    if (_navigationTarget == target) return;
    _navigationTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigationTarget = null;
      final currentRouter = ref.read(appRouterProvider);
      if (currentRouter.routeInformationProvider.value.uri.path == target) {
        return;
      }
      currentRouter.go(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingSharedGroupSlugProvider, (_, _) {
      _scheduleRecovery();
    });
    ref.listen<ProfileReadiness>(profileReadinessProvider, (_, _) {
      _scheduleRecovery();
    });
    return widget.child;
  }
}
