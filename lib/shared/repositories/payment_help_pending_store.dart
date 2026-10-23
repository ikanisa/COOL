import 'dart:convert';

import 'payment_help_storage.dart';

final _uuid = RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$');

/// The original immutable pending command or its verified acknowledgement. This is
/// recovery evidence only; it never changes payment or contribution state.
class PaymentHelpCheckpoint {
  PaymentHelpCheckpoint({
    required this.ownerId,
    required this.collectionId,
    required this.intentId,
    required this.requestId,
    this.reference,
    this.note,
    this.received = false,
  }) {
    if (![ownerId, collectionId, intentId, requestId].every(_uuid.hasMatch) ||
        (received && (reference != null || note != null)) ||
        (reference != null &&
            (reference!.isEmpty ||
                reference != reference!.trim() ||
                reference!.length > 160)) ||
        (note != null &&
            (note!.isEmpty || note != note!.trim() || note!.length > 2000))) {
      throw const FormatException('Invalid saved payment-help request.');
    }
  }

  final String ownerId, collectionId, intentId, requestId;
  final String? reference, note;
  final bool received;

  Map<String, dynamic> get command {
    if (received) throw StateError('Received requests cannot be sent again.');
    return {
      'p_kind': 'payment_review',
      'p_collection_id': collectionId,
      'p_intent_id': intentId,
      'p_request_id': requestId,
      'p_provider_reference': reference,
      'p_note': note,
    };
  }

  PaymentHelpCheckpoint acknowledge() => PaymentHelpCheckpoint(
    ownerId: ownerId,
    collectionId: collectionId,
    intentId: intentId,
    requestId: requestId,
    received: true,
  );

  Map<String, dynamic> _encode() => received
      ? {
          'owner_id': ownerId,
          'status': 'received',
          'receipt': {
            'id': requestId,
            'collection_id': collectionId,
            'intent_id': intentId,
            'financial_effects': 0,
          },
        }
      : {
          'owner_id': ownerId,
          'command': command,
          'status': received ? 'received' : 'pending',
        };

  static PaymentHelpCheckpoint _decode(Object? raw) {
    if (raw is! Map ||
        raw.length != 3 ||
        !const {'pending', 'received'}.contains(raw['status'])) {
      throw const FormatException('Saved payment help could not be verified.');
    }
    if (raw['status'] == 'received') {
      final receipt = raw['receipt'];
      if (raw['owner_id'] is! String ||
          receipt is! Map ||
          receipt.length != 4 ||
          receipt['id'] is! String ||
          receipt['collection_id'] is! String ||
          receipt['intent_id'] is! String ||
          receipt['financial_effects'] is! int ||
          receipt['financial_effects'] != 0) {
        throw const FormatException(
          'Saved payment help could not be verified.',
        );
      }
      return PaymentHelpCheckpoint(
        ownerId: raw['owner_id'] as String,
        collectionId: receipt['collection_id'] as String,
        intentId: receipt['intent_id'] as String,
        requestId: receipt['id'] as String,
        received: true,
      );
    }
    if (raw['command'] is! Map) {
      throw const FormatException('Saved payment help could not be verified.');
    }
    final body = raw['command'] as Map;
    if (body.length != 6 ||
        !body.keys.toSet().containsAll(const {
          'p_kind',
          'p_collection_id',
          'p_intent_id',
          'p_request_id',
          'p_provider_reference',
          'p_note',
        }) ||
        body['p_kind'] != 'payment_review' ||
        raw['owner_id'] is! String ||
        body['p_collection_id'] is! String ||
        body['p_intent_id'] is! String ||
        body['p_request_id'] is! String ||
        (body['p_provider_reference'] != null &&
            body['p_provider_reference'] is! String) ||
        (body['p_note'] != null && body['p_note'] is! String)) {
      throw const FormatException('Saved payment help could not be verified.');
    }
    return PaymentHelpCheckpoint(
      ownerId: raw['owner_id'] as String,
      collectionId: body['p_collection_id'] as String,
      intentId: body['p_intent_id'] as String,
      requestId: body['p_request_id'] as String,
      reference: body['p_provider_reference'] as String?,
      note: body['p_note'] as String?,
    );
  }
}

class PaymentHelpPendingStore {
  PaymentHelpPendingStore({PaymentHelpProtectedStorage? storage})
    : _storage = storage ?? createPaymentHelpStorage();

  static const maximumRecords = 64, maximumBytes = 256 * 1024;
  final PaymentHelpProtectedStorage _storage;
  String? _owner;
  int _epoch = 0;
  final _pendingClearOwners = <String>{};

  /// Fence synchronously, including any queued operation from the old owner.
  /// A repository being destroyed is not logout and does not call this.
  void bindOwner(String? ownerId) {
    if (ownerId != null && !_uuid.hasMatch(ownerId)) {
      throw const FormatException('Invalid payment-help owner.');
    }
    if (_owner == ownerId) return;
    final old = _owner;
    _owner = ownerId;
    ++_epoch;
    if (old != null) {
      _pendingClearOwners.add(old);
      // Retry failed cleanup before the next operation, retaining the affected
      // owner until the native/browser transaction actually commits.
      _storage.exclusive(_clearPending).ignore();
    }
  }

  Future<void> _clearPending() async {
    for (final owner in _pendingClearOwners.toList()) {
      await _storage.clear(owner);
      _pendingClearOwners.remove(owner);
    }
  }

  Future<void> ensureCleanup() => _storage.exclusive(_clearPending);

  void _current(String owner, int epoch) {
    if (_owner != owner || _epoch != epoch) throw StateError('Account changed');
  }

  Future<Map<String, PaymentHelpCheckpoint>> _read(String owner) async {
    final text = await _storage.read(owner);
    if (text == null) return {};
    if (utf8.encode(text).length > maximumBytes) {
      throw const FormatException('Saved payment help exceeds its limit.');
    }
    final value = jsonDecode(text);
    if (value is! Map ||
        value.length != 3 ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['owner_id'] != owner ||
        value['requests'] is! List ||
        (value['requests'] as List).length > maximumRecords) {
      throw const FormatException('Saved payment help could not be verified.');
    }
    final records = <String, PaymentHelpCheckpoint>{};
    for (final raw in value['requests'] as List) {
      final record = PaymentHelpCheckpoint._decode(raw);
      if (record.ownerId != owner || records.containsKey(record.intentId)) {
        throw const FormatException(
          'Saved payment help could not be verified.',
        );
      }
      records[record.intentId] = record;
    }
    return records;
  }

  Future<T> _operate<T>(String owner, Future<T> Function(int) action) {
    final epoch = _epoch;
    _current(owner, epoch);
    return _storage.exclusive(() async {
      await _clearPending();
      _current(owner, epoch);
      return action(epoch);
    });
  }

  Future<PaymentHelpCheckpoint?> read({
    required String ownerId,
    required String collectionId,
    required String intentId,
  }) => _operate(ownerId, (epoch) async {
    final record = (await _read(ownerId))[intentId];
    _current(ownerId, epoch);
    if (record != null && record.collectionId != collectionId) {
      throw const FormatException('Saved payment request group is invalid.');
    }
    return record;
  });

  /// First claim wins, including after an unknown response or another tab.
  Future<PaymentHelpCheckpoint> retain(PaymentHelpCheckpoint candidate) =>
      _operate(candidate.ownerId, (epoch) async {
        final records = await _read(candidate.ownerId);
        _current(candidate.ownerId, epoch);
        final previous = records[candidate.intentId];
        if (previous != null) {
          if (previous.collectionId != candidate.collectionId) {
            throw const FormatException(
              'Saved payment request group is invalid.',
            );
          }
          return previous;
        }
        if (records.length >= maximumRecords) {
          throw StateError(
            'Saved payment help is full. Existing requests remain available.',
          );
        }
        records[candidate.intentId] = candidate;
        await _write(candidate.ownerId, records);
        _current(candidate.ownerId, epoch);
        return candidate;
      });

  Future<PaymentHelpCheckpoint> acknowledge(PaymentHelpCheckpoint expected) =>
      _operate(expected.ownerId, (epoch) async {
        final records = await _read(expected.ownerId);
        _current(expected.ownerId, epoch);
        final previous = records[expected.intentId];
        if (previous?.received == true &&
            previous!.requestId == expected.requestId &&
            previous.collectionId == expected.collectionId) {
          return previous;
        }
        if (previous == null ||
            previous.received ||
            jsonEncode(previous.command) != jsonEncode(expected.command)) {
          throw const FormatException('Saved payment help changed. Reopen it.');
        }
        final received = previous.acknowledge();
        records[expected.intentId] = received;
        await _write(expected.ownerId, records);
        _current(expected.ownerId, epoch);
        return received;
      });

  Future<void> _write(
    String owner,
    Map<String, PaymentHelpCheckpoint> records,
  ) async {
    final text = jsonEncode({
      'version': 1,
      'owner_id': owner,
      'requests': records.values.map((value) => value._encode()).toList(),
    });
    if (utf8.encode(text).length > maximumBytes) {
      throw StateError(
        'Saved payment help is full. Existing requests remain available.',
      );
    }
    await _storage.write(owner, text);
  }
}
