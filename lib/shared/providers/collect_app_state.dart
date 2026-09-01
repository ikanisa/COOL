import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/collect_models.dart';
import '../repositories/pending_shared_group_intent_store.dart';
import '../repositories/collect_repository.dart';

final onboardingCompleteProvider = StateProvider<bool>((ref) => false);

final legalConsentAcceptedProvider = StateProvider<bool>((ref) => false);

final pendingSharedGroupIntentStoreProvider =
    Provider<PendingSharedGroupIntentStore>(
      (ref) => PendingSharedGroupIntentStore(),
    );

final pendingSharedGroupSlugProvider =
    StateNotifierProvider<PendingSharedGroupIntentController, String?>(
      (ref) => PendingSharedGroupIntentController(
        ref.watch(pendingSharedGroupIntentStoreProvider),
      ),
    );

class PendingSharedGroupIntentController extends StateNotifier<String?> {
  PendingSharedGroupIntentController(
    this._store, {
    String? initialSlug,
    bool restorePersistedIntent = true,
  }) : super(normalizePendingSharedGroupSlug(initialSlug ?? '')) {
    _operation = restorePersistedIntent ? _restore() : Future<void>.value();
  }

  final PendingSharedGroupIntentStore _store;
  late Future<void> _operation;

  Future<String?> current() async {
    await _operation;
    return state;
  }

  Future<String> retain(String rawSlug) {
    return _enqueue(() async {
      final slug = await _store.saveSlug(rawSlug);
      if (mounted) state = slug;
      return slug;
    });
  }

  Future<bool> clearIfMatches(String rawSlug) {
    return _enqueue(() async {
      final slug = normalizePendingSharedGroupSlug(rawSlug);
      if (slug == null || state != slug) return false;
      await _store.clear();
      if (mounted) state = null;
      return true;
    });
  }

  Future<void> clear() {
    return _enqueue(() async {
      await _store.clear();
      if (mounted) state = null;
    });
  }

  Future<void> _restore() async {
    try {
      final restored = await _store.readSlug();
      if (mounted && state == null) state = restored;
    } catch (_) {
      // A local preference failure must not crash startup. A newly received
      // intent still fails closed in retain() if it cannot be persisted.
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operation = _operation.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

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
