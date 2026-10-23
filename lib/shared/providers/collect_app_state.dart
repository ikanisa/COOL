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
  PendingSharedGroupIntent? _intent;

  Future<String?> current() async {
    await _operation;
    return state;
  }

  Future<PendingSharedGroupIntent?> currentRecord() async {
    await _operation;
    return _intent;
  }

  Future<PendingSharedGroupIntent> retainRecord(
    String rawSlug, {
    String? ownerUserId,
  }) {
    return _enqueue(() async {
      final intent = await _store.save(rawSlug, ownerUserId: ownerUserId);
      _intent = intent;
      if (mounted) state = intent.slug;
      return intent;
    });
  }

  /// Repeated delivery of the same App Link keeps the invitation currently
  /// visible on screen. A new slug or account creates a new record.
  Future<PendingSharedGroupIntent> retainIncomingRecord(
    String rawSlug, {
    String? ownerUserId,
  }) {
    return _enqueue(() async {
      final slug = normalizePendingSharedGroupSlug(rawSlug);
      if (slug == null) throw const FormatException('Group link is invalid');
      final owner = ownerUserId == null
          ? null
          : normalizePendingSharedGroupOwnerUserId(ownerUserId);
      final existing = _intent;
      if (existing != null &&
          existing.slug == slug &&
          (existing.ownerUserId == owner ||
              (existing.ownerUserId == null && owner != null))) {
        final persisted = await _store.read();
        if (persisted?.intentId == existing.intentId &&
            persisted?.ownerUserId == existing.ownerUserId) {
          if (owner != null && persisted!.ownerUserId == null) {
            final bound = persisted.bindTo(owner);
            await _store.write(bound);
            _intent = bound;
            return bound;
          }
          return persisted!;
        }
      }
      final intent = await _store.save(slug, ownerUserId: owner);
      _intent = intent;
      if (mounted) state = intent.slug;
      return intent;
    });
  }

  Future<String> retain(String rawSlug, {String? ownerUserId}) async =>
      (await retainRecord(rawSlug, ownerUserId: ownerUserId)).slug;

  Future<PendingSharedGroupIntent?> currentRecordForOwner(String userId) {
    return _enqueue(() async {
      final intent = _intent;
      if (intent == null) return null;
      final persisted = await _store.read();
      if (persisted == null ||
          persisted.intentId != intent.intentId ||
          persisted.ownerUserId != intent.ownerUserId) {
        _intent = persisted;
        if (mounted) state = persisted?.slug;
        return null;
      }
      final normalizedUserId = normalizePendingSharedGroupOwnerUserId(userId);
      if (intent.ownerUserId != null &&
          intent.ownerUserId != normalizedUserId) {
        await _store.clear();
        _intent = null;
        if (mounted) state = null;
        return null;
      }
      if (intent.ownerUserId == null) {
        final bound = intent.bindTo(normalizedUserId);
        await _store.write(bound);
        _intent = bound;
        return bound;
      }
      return intent;
    });
  }

  Future<bool> clearIfMatchesRecord(PendingSharedGroupIntent expected) {
    return _enqueue(() async {
      final intent = _intent;
      if (intent == null ||
          intent.slug != expected.slug ||
          intent.intentId != expected.intentId ||
          intent.ownerUserId != expected.ownerUserId) {
        return false;
      }
      final persisted = await _store.read();
      if (persisted?.intentId != expected.intentId ||
          persisted?.ownerUserId != expected.ownerUserId) {
        return false;
      }
      await _store.clear();
      _intent = null;
      if (mounted) state = null;
      return true;
    });
  }

  Future<bool> clearIfMatches(String rawSlug) {
    return _enqueue(() async {
      final slug = normalizePendingSharedGroupSlug(rawSlug);
      if (slug == null || state != slug) return false;
      await _store.clear();
      _intent = null;
      if (mounted) state = null;
      return true;
    });
  }

  Future<void> clear() {
    return _enqueue(() async {
      await _store.clear();
      _intent = null;
      if (mounted) state = null;
    });
  }

  Future<void> _restore() async {
    try {
      final restored = await _store.read();
      if (mounted && state == null) {
        _intent = restored;
        state = restored?.slug;
      }
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
      final repository = ref.watch(collectRepositoryProvider.notifier);
      ref.watch(
        collectRepositoryProvider.select(
          (state) => (
            repository.sessionGeneration,
            state.currentProfile?.id,
            state.lastSuccessfulSyncAt,
            state.collections,
          ),
        ),
      );
      return repository.ownerHealthFor(collectionId);
    });

final groupMembersProvider = FutureProvider.family<List<CollectMember>, String>(
  (ref, collectionId) {
    // A roster belongs to the exact client session and membership snapshot.
    final repository = ref.watch(collectRepositoryProvider.notifier);
    ref.watch(
      collectRepositoryProvider.select(
        (state) => (
          repository.sessionGeneration,
          state.currentProfile?.id,
          state.lastSuccessfulSyncAt,
          state.collections,
        ),
      ),
    );
    return repository.membersForCollection(collectionId);
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
