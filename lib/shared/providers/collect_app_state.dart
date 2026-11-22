import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/collect_models.dart';
import '../repositories/collect_repository.dart';

export 'pending_shared_group_intent_provider.dart';

final notificationPermissionStatusProvider =
    StateProvider<CollectDevicePermissionStatus>(
      (ref) => CollectDevicePermissionStatus.notRequested,
    );

final cameraPermissionStatusProvider =
    StateProvider<CollectDevicePermissionStatus>(
      (ref) => CollectDevicePermissionStatus.notRequested,
    );

final profileReadinessProvider = Provider<ProfileReadiness>((ref) {
  final profile = ref.watch(
    collectRepositoryProvider.select((state) => state.currentProfile),
  );
  return ProfileReadiness(
    hasProfile: profile != null,
    collectId: profile?.publicId,
  );
});

/// Diagnostic connectivity state for explicit recovery flows and device UAT.
/// This state must not be rendered as a global overlay over customer screens.
final connectivityStatusProvider = Provider<ConnectivityStatus>((ref) {
  final usingStaleCache = ref.watch(
    collectRepositoryProvider.select((state) => state.usingStaleCache),
  );
  if (usingStaleCache) return ConnectivityStatus.offlineStale;
  final error = ref.watch(
    collectRepositoryProvider.select((state) => state.lastError),
  );
  if (error == null || error.trim().isEmpty) return ConnectivityStatus.online;
  final lower = error.toLowerCase();
  if (lower.contains('socket') ||
      lower.contains('network') ||
      lower.contains('offline') ||
      lower.contains('connection')) {
    return ConnectivityStatus.offline;
  }
  return ConnectivityStatus.degraded;
});

final realtimeSyncStatusProvider = Provider<RealtimeSyncStatus>((ref) {
  final isLoading = ref.watch(
    collectRepositoryProvider.select((state) => state.isLoading),
  );
  final error = ref.watch(
    collectRepositoryProvider.select((state) => state.lastError),
  );
  if (isLoading) return RealtimeSyncStatus.syncing;
  if (error != null && error.trim().isNotEmpty) {
    return RealtimeSyncStatus.needsAttention;
  }
  return RealtimeSyncStatus.current;
});

final momoReceiptCaptureAvailableProvider = Provider<bool>((ref) {
  // SMS capture is an optional Android device capability. Collection does not
  // depend on a country, payment profile, recipient registry or paired role.
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
});

final smsPermissionStatusProvider = Provider<SmsPermissionStatus>((ref) {
  // A cached consent flag from another device cannot grant this device a
  // capability its OS does not support.
  if (!ref.watch(momoReceiptCaptureAvailableProvider)) {
    return SmsPermissionStatus.unavailable;
  }
  final enabled = ref.watch(
    collectRepositoryProvider.select((state) => state.smsAccessEnabled),
  );
  final denied = ref.watch(
    collectRepositoryProvider.select((state) => state.smsAccessDenied),
  );
  if (enabled) return SmsPermissionStatus.granted;
  if (denied) return SmsPermissionStatus.denied;
  return SmsPermissionStatus.notRequested;
});

final paymentUiStatusProvider =
    Provider.family<PaymentUiStatus, PaymentStatusKey>((ref, key) {
      final payments = ref.watch(memberPaymentRepositoryProvider);
      ref.watch(
        memberPaymentStateProvider.select((state) => state.paymentIntents),
      );
      try {
        final intent = payments.maybeIntentById(key.intentId);
        if (intent == null || intent.collectionId != key.collectionId) {
          return PaymentUiStatus.needsReview;
        }
        return switch ((intent.confirmationStatus, intent.status)) {
          ('credited', _) when intent.hasCommittedContribution =>
            PaymentUiStatus.confirmed,
          ('reversed', _) when intent.hasCommittedContribution =>
            PaymentUiStatus.reversed,
          ('payment_received', _) when intent.paymentId != null =>
            PaymentUiStatus.paymentLinked,
          ('awaiting_confirmation', 'pending') when intent.isRwandaMomo =>
            intent.isAwaitingTransfer
                ? PaymentUiStatus.pending
                : PaymentUiStatus.expired,
          ('awaiting_confirmation', 'expired') => PaymentUiStatus.expired,
          _ => PaymentUiStatus.needsReview,
        };
      } catch (_) {
        return PaymentUiStatus.needsReview;
      }
    });

final _memberGroupReadScopeProvider = Provider((ref) {
  // Protected reads belong to this session and membership snapshot.
  final session = ref.watch(memberGroupSessionProvider);
  final snapshot = ref.watch(
    memberGroupDirectoryStateProvider.select(
      (state) => (state.lastSuccessfulSyncAt, state.collections),
    ),
  );
  return (session: session, snapshot: snapshot);
});

final ownerGroupHealthProvider =
    FutureProvider.family<OwnerGroupHealth, String>((ref, collectionId) {
      ref.watch(_memberGroupReadScopeProvider);
      return ref
          .watch(memberGroupManagementRepositoryProvider)
          .ownerHealthFor(collectionId);
    });

final groupMembersProvider = FutureProvider.family<List<CollectMember>, String>(
  (ref, collectionId) {
    final scope = ref.watch(_memberGroupReadScopeProvider);
    return scope.session.repository.membersForCollection(collectionId);
  },
);

class ProfileReadiness {
  const ProfileReadiness({required this.hasProfile, required this.collectId});

  final bool hasProfile;
  final String? collectId;

  bool get readyForContribution => hasProfile;
  bool get readyForGroupCreation => hasProfile;
}

class PaymentStatusKey {
  const PaymentStatusKey({required this.collectionId, required this.intentId});

  final String collectionId;
  final String intentId;
}

final offlineSnapshotStatusProvider = Provider<OfflineSnapshotStatus>((ref) {
  final state = ref.watch(collectRepositoryProvider);
  return OfflineSnapshotStatus(
    usingStaleCache: state.usingStaleCache,
    hasReadableData: state.hasOfflineReadableData,
    lastSuccessfulSyncAt: state.lastSuccessfulSyncAt,
  );
});

enum ConnectivityStatus { online, degraded, offline, offlineStale }

enum RealtimeSyncStatus { current, syncing, needsAttention }

enum SmsPermissionStatus { unavailable, notRequested, granted, denied }

enum PaymentUiStatus {
  pending,
  confirmed,
  expired,
  needsReview,
  paymentLinked,
  reversed,
}

enum CollectDevicePermissionStatus { notRequested, granted, denied }

class OfflineSnapshotStatus {
  const OfflineSnapshotStatus({
    required this.usingStaleCache,
    required this.hasReadableData,
    required this.lastSuccessfulSyncAt,
  });

  final bool usingStaleCache;
  final bool hasReadableData;
  final DateTime? lastSuccessfulSyncAt;

  String get label {
    if (!usingStaleCache) return 'Live data';
    final syncedAt = lastSuccessfulSyncAt;
    if (syncedAt == null) return 'Offline saved data';
    final local = syncedAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return 'Offline saved data, updated $hour:$minute';
  }
}
