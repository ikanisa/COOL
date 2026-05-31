import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collect_models.dart';
import '../repositories/collect_repository.dart';

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

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

  bool get readyForContribution => hasProfile;
  bool get readyForGroupCreation => hasProfile && hasMomoNumber;
}

class PaymentStatusKey {
  const PaymentStatusKey({required this.collectionId, required this.intentId});

  final String collectionId;
  final String intentId;
}

enum ConnectivityStatus { online, degraded, offline }

enum RealtimeSyncStatus { current, syncing, needsAttention }

enum SmsPermissionStatus { unavailable, notRequested, granted, denied }

enum PaymentUiStatus { pending, confirmed, expired, needsReview }
