import 'dart:convert';
import 'admin_full_payment_compensation_models.dart';
import 'admin_full_payment_compensation_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_full_payment_compensation_checkpoint_web.dart'
    as platform;

abstract interface class AdminFullPaymentCompensationStore {
  Future<AdminFullPaymentCompensationIntent?> pending(
    String actor,
    String session,
  );
  Future<AdminFullPaymentCompensationIntent?> lastCompleted(
    String actor,
    String session,
    String paymentId,
  );
  Future<void> savePending(AdminFullPaymentCompensationIntent original);
  Future<void> complete(
    AdminFullPaymentCompensationIntent original,
    AdminFullPaymentCompensationResult result,
  );
}

AdminFullPaymentCompensationStore? browserFullPaymentCompensationStore() =>
    platform.createStore();

class AdminFullPaymentCompensationJournalStore
    implements AdminFullPaymentCompensationStore {
  const AdminFullPaymentCompensationJournalStore({
    required this.readRaw,
    required this.writeRaw,
    required this.exclusive,
  });
  final String? Function(String) readRaw;
  final void Function(String, String) writeRaw;
  final Future<void> Function(String, void Function()) exclusive;
  static const capacity = 64, maximumBytes = 2097152;
  String _key(String actor, String session) {
    compensationUuid(session);
    return 'collect.full-compensation.v1.${compensationUuid(actor)}';
  }

  Map<String, dynamic> _read(String actor, String session) {
    final raw = readRaw(_key(actor, session));
    if (raw == null) {
      return {
        'version': 1,
        'actor_id': actor,
        'pending': null,
        'completed': <Object?>[],
      };
    }
    if (utf8.encode(raw).length > maximumBytes) compensationInvalid();
    final row = compensationObject(jsonDecode(raw), {
      'version',
      'actor_id',
      'pending',
      'completed',
    });
    if (row['version'] is! int ||
        row['version'] != 1 ||
        row['actor_id'] != actor ||
        row['completed'] is! List ||
        (row['completed'] as List).length > capacity) {
      compensationInvalid();
    }
    final ids = <String>{};
    void bound(AdminFullPaymentCompensationIntent i) {
      if (i.actorId != actor || !ids.add(i.requestId)) compensationInvalid();
    }

    for (final item in row['completed'] as List) {
      final done = compensationObject(item, {'intent', 'result'}),
          original = AdminFullPaymentCompensationIntent.parse(done['intent']);
      bound(original);
      AdminFullPaymentCompensationResult.parse(done['result'], original);
    }
    if (row['pending'] != null) {
      bound(AdminFullPaymentCompensationIntent.parse(row['pending']));
    }
    return row;
  }

  void _write(String actor, String session, Map<String, dynamic> row) {
    final raw = jsonEncode(row);
    if (utf8.encode(raw).length > maximumBytes) compensationInvalid();
    writeRaw(_key(actor, session), raw);
    if (readRaw(_key(actor, session)) != raw) compensationInvalid();
    _read(actor, session);
  }

  @override
  Future<AdminFullPaymentCompensationIntent?> pending(
    String actor,
    String session,
  ) async {
    final raw = _read(actor, session)['pending'];
    return raw == null ? null : AdminFullPaymentCompensationIntent.parse(raw);
  }

  @override
  Future<AdminFullPaymentCompensationIntent?> lastCompleted(
    String actor,
    String session,
    String paymentId,
  ) async {
    compensationUuid(paymentId);
    final values = _read(actor, session)['completed'] as List;
    for (final item in values.reversed) {
      final original = AdminFullPaymentCompensationIntent.parse(
        (item as Map)['intent'],
      );
      if (original.inspection.paymentId == paymentId) return original;
    }
    return null;
  }

  @override
  Future<void> savePending(
    AdminFullPaymentCompensationIntent original,
  ) => exclusive(_key(original.actorId, original.sessionId), () {
    final row = _read(original.actorId, original.sessionId);
    if ((row['completed'] as List).length >= capacity ||
        (row['completed'] as List).any(
          (e) =>
              ((e as Map)['intent'] as Map)['request_id'] == original.requestId,
        )) {
      compensationInvalid();
    }
    if (row['pending'] != null &&
        AdminFullPaymentCompensationIntent.parse(row['pending']).fingerprint !=
            original.fingerprint) {
      compensationInvalid();
    }
    row['pending'] = original.row;
    _write(original.actorId, original.sessionId, row);
  });
  @override
  Future<void> complete(
    AdminFullPaymentCompensationIntent original,
    AdminFullPaymentCompensationResult result,
  ) => exclusive(_key(original.actorId, original.sessionId), () {
    AdminFullPaymentCompensationResult.parse(result.row, original);
    final row = _read(original.actorId, original.sessionId),
        completed = List<Object?>.from(row['completed'] as List);
    for (final item in completed) {
      final done = compensationObject(item, {'intent', 'result'}),
          saved = AdminFullPaymentCompensationIntent.parse(done['intent']);
      if (saved.requestId == original.requestId) {
        if (saved.fingerprint != original.fingerprint ||
            compensationFingerprint(done['result']) !=
                compensationFingerprint(result.row)) {
          compensationInvalid();
        }
        return;
      }
    }
    if (row['pending'] == null ||
        AdminFullPaymentCompensationIntent.parse(row['pending']).fingerprint !=
            original.fingerprint ||
        completed.length >= capacity) {
      compensationInvalid();
    }
    completed.add({'intent': original.row, 'result': result.row});
    row['completed'] = completed;
    row['pending'] = null;
    _write(original.actorId, original.sessionId, row);
  });
}
