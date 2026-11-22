import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloudflare/cloudflare_module.dart';
import '../../core/notifications/collect_notification_service.dart';
import '../../shared/repositories/collect_repository.dart';
import '../router.dart';

class NotificationIntentHost extends ConsumerStatefulWidget {
  const NotificationIntentHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationIntentHost> createState() =>
      NotificationIntentHostState();
}

class NotificationIntentHostState
    extends ConsumerState<NotificationIntentHost> {
  StreamSubscription<CollectNotificationIntent>? _subscription;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(collectNotificationServiceProvider);
    _subscription = notifications.notificationTapPayloads.listen(
      _scheduleNavigation,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _scheduleNavigation(CollectNotificationIntent intent) {
    final client = ref.read(collectBackendClientProvider);
    final owner = client == null
        ? ref.read(collectAuthenticatedUserIdProvider)
        : client.auth.currentUser?.id;
    if (intent.recipientId != null && intent.recipientId != owner) {
      return;
    }
    final eventId = intent.eventId;
    if (eventId != null) {
      unawaited(_markNotificationRead(eventId));
    }
    final target = intent.deepLink;
    final router = ref.read(appRouterProvider);
    if (router.routeInformationProvider.value.uri.toString() == target) return;
    router.go(target);
  }

  Future<void> _markNotificationRead(String eventId) async {
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .markNotificationRead(eventId);
    } catch (_) {
      // Navigation remains available if read-receipt sync is temporarily down.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
