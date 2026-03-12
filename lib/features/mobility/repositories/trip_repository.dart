import 'dart:async';
import 'dart:math';

import 'package:cool_app/core/sync/network_status.dart';
import 'package:cool_app/core/utils/json_helpers.dart' as jh;
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripRepository {
  TripRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _boxName = 'mobility_trip_posts';
  static const _tableName = 'mobility_trips';
  static final Random _random = Random.secure();

  Future<TripPostResult> createTrip(TripPostRequest request) async {
    final now = DateTime.now();
    final clientRequestId =
        request.clientRequestId ?? _nextClientRequestId(now);
    final requestWithId = request.copyWith(clientRequestId: clientRequestId);
    final cachedPayload = <String, dynamic>{
      ...requestWithId.toJson(),
      'created_at_local': now.toIso8601String(),
      'last_sync_attempt_at': null,
      'last_sync_error': null,
      'sync_attempts': 0,
    };

    await _cacheTrip(
      id: clientRequestId,
      payload: cachedPayload,
      storedOffline: true,
    );

    try {
      final insertedTrip = await _insertTrip(requestWithId);
      final remoteId = insertedTrip['id']?.toString() ?? clientRequestId;
      await _deleteCachedTrip(clientRequestId);
      return TripPostResult(id: remoteId, storedOffline: false);
    } catch (error) {
      if (isNetworkError(error)) {
        return TripPostResult(id: clientRequestId, storedOffline: true);
      }

      await _deleteCachedTrip(clientRequestId);
      rethrow;
    }
  }

  Future<TripSyncSummary> syncPendingTrips({required String userId}) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    final keys = box.keys.toList(growable: false);
    var pendingCount = 0;
    var syncedCount = 0;
    var failedCount = 0;
    var discardedCount = 0;

    for (final key in keys) {
      final rawEntry = box.get(key);
      if (rawEntry is! Map) {
        await box.delete(key);
        discardedCount++;
        continue;
      }

      final entry = Map<String, dynamic>.from(rawEntry);
      if (entry['stored_offline'] != true) {
        await box.delete(key);
        continue;
      }

      final entryUserId = entry['user_id']?.toString();
      if (entryUserId == null || entryUserId.isEmpty) {
        await box.delete(key);
        discardedCount++;
        continue;
      }

      if (entryUserId != userId) {
        continue;
      }

      pendingCount++;

      TripPostRequest request;
      try {
        request = TripPostRequest.fromOfflineCache(entry);
      } on FormatException {
        await box.delete(key);
        discardedCount++;
        continue;
      }

      if (_isStale(request.departureAt)) {
        await box.delete(key);
        discardedCount++;
        continue;
      }

      try {
        await _insertTrip(request);
        await box.delete(key);
        syncedCount++;
      } catch (error) {
        failedCount++;
        await _markSyncFailure(box, key, entry, error);
      }
    }

    return TripSyncSummary(
      pendingCount: pendingCount,
      syncedCount: syncedCount,
      failedCount: failedCount,
      discardedCount: discardedCount,
    );
  }

  Future<Map<String, dynamic>> _insertTrip(TripPostRequest request) async {
    final payloads = <Map<String, dynamic>>[
      request.toJson(),
      request.toJson(includeContactFields: false),
      request.toLegacyJson(),
      request.toLegacyJson(includeContactFields: false),
      _withoutClientRequestId(request.toJson()),
      _withoutClientRequestId(request.toJson(includeContactFields: false)),
      _withoutClientRequestId(request.toLegacyJson()),
      _withoutClientRequestId(
        request.toLegacyJson(includeContactFields: false),
      ),
    ];

    PostgrestException? lastSchemaError;

    for (final payload in payloads) {
      try {
        final insertedTrip = await _client
            .from(_tableName)
            .insert(payload)
            .select('id')
            .single();
        return Map<String, dynamic>.from(insertedTrip);
      } on PostgrestException catch (error) {
        if (_isDuplicateClientRequestError(error)) {
          final existingTrip = await _findExistingTripByClientRequestId(
            request,
          );
          if (existingTrip != null) {
            return existingTrip;
          }
        }
        lastSchemaError = error;
      }
    }

    if (lastSchemaError != null) {
      throw lastSchemaError;
    }

    throw StateError('Unable to create trip.');
  }

  Future<String> _cacheTrip({
    required String id,
    required Map<String, dynamic> payload,
    required bool storedOffline,
  }) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.put(id, <String, dynamic>{
      'id': id,
      'stored_offline': storedOffline,
      ...payload,
    });
    return id;
  }

  Future<void> _deleteCachedTrip(String id) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.delete(id);
  }

  Future<void> _markSyncFailure(
    Box<dynamic> box,
    dynamic key,
    Map<String, dynamic> entry,
    Object error,
  ) async {
    final attempts = jh.asInt(entry['sync_attempts']) ?? 0;
    await box.put(key, <String, dynamic>{
      ...entry,
      'last_sync_attempt_at': DateTime.now().toIso8601String(),
      'last_sync_error': error.toString(),
      'sync_attempts': attempts + 1,
    });
  }

  Future<Map<String, dynamic>?> _findExistingTripByClientRequestId(
    TripPostRequest request,
  ) async {
    final userId = request.userId;
    final clientRequestId = request.clientRequestId;
    if (userId == null ||
        userId.isEmpty ||
        clientRequestId == null ||
        clientRequestId.isEmpty) {
      return null;
    }

    try {
      final existing = await _client
          .from(_tableName)
          .select('id')
          .eq('user_id', userId)
          .eq('client_request_id', clientRequestId)
          .maybeSingle();
      if (existing == null) {
        return null;
      }
      return Map<String, dynamic>.from(existing);
    } on PostgrestException {
      return null;
    }
  }

  bool _isDuplicateClientRequestError(PostgrestException error) {
    final normalized = [
      error.code,
      error.message,
      error.details,
      error.hint,
    ].whereType<String>().join(' ').toLowerCase();
    return error.code == '23505' && normalized.contains('client_request');
  }

  bool _isStale(DateTime departureAt) {
    return departureAt.isBefore(DateTime.now());
  }

  Map<String, dynamic> _withoutClientRequestId(Map<String, dynamic> payload) {
    final sanitized = Map<String, dynamic>.from(payload);
    sanitized.remove('client_request_id');
    return sanitized;
  }



  static String _nextClientRequestId(DateTime now) {
    final randomSuffix = _random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return 'trip_${now.microsecondsSinceEpoch}_$randomSuffix';
  }
}

class TripSyncSummary {
  const TripSyncSummary({
    required this.pendingCount,
    required this.syncedCount,
    required this.failedCount,
    required this.discardedCount,
  });

  final int pendingCount;
  final int syncedCount;
  final int failedCount;
  final int discardedCount;
}
