import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../repositories/pending_shared_group_intent_store.dart';

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
  PendingSharedGroupIntentController(this._store) : super(null) {
    _operation = _restore();
  }

  final PendingSharedGroupIntentStore _store;
  late Future<void> _operation;
  PendingSharedGroupIntent? _intent;

  Future<PendingSharedGroupIntent?> currentRecord() async {
    await _operation;
    return _intent;
  }

  Future<PendingSharedGroupIntent> retainRecord(
    String rawSlug, {
    String? ownerUserId,
  }) {
    return _enqueue(() => _saveRecord(rawSlug, ownerUserId: ownerUserId));
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
      return _saveRecord(slug, ownerUserId: owner);
    });
  }

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
        await _clearStoredIntent();
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
      await _clearStoredIntent();
      return true;
    });
  }

  Future<PendingSharedGroupIntent> _saveRecord(
    String slug, {
    required String? ownerUserId,
  }) async {
    final intent = await _store.save(slug, ownerUserId: ownerUserId);
    _intent = intent;
    if (mounted) state = intent.slug;
    return intent;
  }

  Future<void> _clearStoredIntent() async {
    await _store.clear();
    _intent = null;
    if (mounted) state = null;
  }

  Future<void> _restore() async {
    try {
      final restored = await _store.read();
      if (mounted) {
        _intent = restored;
        state = restored?.slug;
      }
    } catch (_) {
      // A local preference failure must not crash startup. A newly received
      // intent still fails closed in retainRecord() if it cannot be persisted.
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
