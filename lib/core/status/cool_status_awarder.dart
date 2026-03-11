import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../status/models/cool_event.dart';
import '../status/providers/cool_status_provider.dart';

/// Convenience mixin for widgets/screens that need to award COOL Status points
/// after an action succeeds.
///
/// Usage in a ConsumerState:
/// ```dart
/// class _MyScreenState extends ConsumerState<MyScreen>
///     with CoolStatusAwarder {
///
///   void _onContributeSuccess(String groupId) {
///     awardCoolPoints(
///       ref,
///       eventType: CoolEventType.groupContribution,
///       sourceId: groupId,
///     );
///   }
/// }
/// ```
mixin CoolStatusAwarder {
  /// Fire-and-forget point award. Safe to call from any widget.
  void awardCoolPoints(
    WidgetRef ref, {
    required CoolEventType eventType,
    String? sourceId,
    int? points,
    Map<String, dynamic> metadata = const {},
  }) {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null || userId.isEmpty) return;

    // Fire-and-forget — don't block the UI
    ref
        .read(coolStatusProvider.notifier)
        .awardPoints(
          userId: userId,
          eventType: eventType,
          sourceId: sourceId,
          points: points,
          metadata: metadata,
        );
  }
}

/// Stand-alone function for widget callbacks that do not use the mixin.
void awardCoolPointsFromRef(
  WidgetRef ref, {
  required CoolEventType eventType,
  String? sourceId,
  int? points,
  Map<String, dynamic> metadata = const {},
}) {
  final userId = ref.read(authProvider).user?.id;
  if (userId == null || userId.isEmpty) return;

  ref
      .read(coolStatusProvider.notifier)
      .awardPoints(
        userId: userId,
        eventType: eventType,
        sourceId: sourceId,
        points: points,
        metadata: metadata,
      );
}
