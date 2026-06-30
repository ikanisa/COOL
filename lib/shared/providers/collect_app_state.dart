import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collect_models.dart';
import '../repositories/collect_repository.dart';

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

final legalConsentAcceptedProvider = StateProvider<bool>((ref) => false);

final pendingSharedGroupSlugProvider = StateProvider<String?>((ref) => null);

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
    hasMomoNumber: profile?.momoNumber?.trim().isNotEmpty == true,
    collectId: profile?.publicId,
  );
});

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

final smsPermissionStatusProvider = Provider<SmsPermissionStatus>((ref) {
  final enabled = ref.watch(
    collectRepositoryProvider.select((state) => state.smsAccessEnabled),
  );
  final denied = ref.watch(
    collectRepositoryProvider.select((state) => state.smsAccessDenied),
  );
  if (enabled) return SmsPermissionStatus.granted;
  if (denied) return SmsPermissionStatus.denied;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return SmsPermissionStatus.unavailable;
  }
  return SmsPermissionStatus.notRequested;
});

final paymentUiStatusProvider =
    Provider.family<PaymentUiStatus, PaymentStatusKey>((ref, key) {
      final repo = ref.watch(collectRepositoryProvider.notifier);
      try {
        final intent = repo.intentById(key.intentId);
        if (intent.status == 'pending' &&
            DateTime.now().isAfter(intent.expiresAt)) {
          return PaymentUiStatus.expired;
        }
        return switch (intent.status) {
          'matched' || 'confirmed' || 'paid' => PaymentUiStatus.confirmed,
          'needs_review' || 'review' => PaymentUiStatus.needsReview,
          'expired' || 'failed' => PaymentUiStatus.expired,
          _ => PaymentUiStatus.pending,
        };
      } catch (_) {
        return PaymentUiStatus.needsReview;
      }
    });

final ownerGroupHealthProvider =
    FutureProvider.family<OwnerGroupHealth, String>((ref, collectionId) {
      return ref
          .read(collectRepositoryProvider.notifier)
          .ownerHealthFor(collectionId);
    });

final groupMembersProvider = FutureProvider.family<List<CollectMember>, String>(
  (ref, collectionId) {
    return ref
        .read(collectRepositoryProvider.notifier)
        .membersForCollection(collectionId);
  },
);

final shareConfirmationProvider = StateProvider<String?>((ref) => null);

class ProfileReadiness {
  const ProfileReadiness({
    required this.hasProfile,
    required this.hasMomoNumber,
    required this.collectId,
  });

  final bool hasProfile;
  final bool hasMomoNumber;
  final String? collectId;

  bool get readyForContribution => hasProfile && hasMomoNumber;
  bool get readyForGroupCreation => hasProfile && hasMomoNumber;
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

enum PaymentUiStatus { pending, confirmed, expired, needsReview }

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
