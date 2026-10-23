part of 'cloudflare_admin_repository.dart';

String _notePermission(String type) => switch (type) {
  'groups' => 'collections.read',
  'users' => 'users.read',
  _ => throw const FormatException('Choose a group or profile.'),
};

class CloudflareOperatorNotePage {
  const CloudflareOperatorNotePage(this.rows, this.total, this.offset);
  final List<Map<String, dynamic>> rows;
  final int total, offset;
}

extension CloudflareOperatorNotesRepository on CloudflareAdminRepository {
  Future<CloudflareOperatorNotePage> operatorNotes(
    String type,
    String id, {
    int offset = 0,
  }) async {
    final permission = _notePermission(type);
    if (!_coreId(id) || offset < 0 || offset > 10000) {
      throw const FormatException('Choose a valid note page.');
    }
    final result = await _read(
      'operations/$type/$id/notes?limit=25&offset=$offset',
      permission,
    );
    _canonicalKeys(result, const {
      'contract_version',
      'entity_type',
      'entity_id',
      'rows',
      'total',
      'limit',
      'offset',
    });
    if (result['contract_version'] != 1 ||
        result['entity_type'] !=
            (type == 'groups' ? 'collection' : 'profile') ||
        result['entity_id'] != id ||
        result['limit'] != 25 ||
        result['offset'] != offset ||
        !_coreInteger(result['total']) ||
        result['rows'] is! List) {
      _invalidCore();
    }
    final total = result['total'] as int,
        rows = <Map<String, dynamic>>[],
        seen = <String>{};
    for (final value in result['rows'] as List) {
      if (value is! Map) _invalidCore();
      final row = Map<String, dynamic>.from(value);
      _canonicalKeys(row, const {
        'id',
        'body',
        'created_by',
        'author_name',
        'created_at',
      });
      if (!_coreId(row['id']) ||
          !_coreId(row['created_by']) ||
          !seen.add(row['id'] as String) ||
          row['body'] is! String ||
          (row['body'] as String).trim().isEmpty ||
          (row['body'] as String).length > 2000 ||
          row['author_name'] is! String ||
          (row['author_name'] as String).isEmpty ||
          (row['author_name'] as String).length > 120 ||
          !_coreTimestamp(row['created_at'])) {
        _invalidCore();
      }
      rows.add(Map.unmodifiable(row));
    }
    if (rows.length != (total - offset).clamp(0, 25)) _invalidCore();
    return CloudflareOperatorNotePage(List.unmodifiable(rows), total, offset);
  }

  Future<CloudflareOperationReceipt> recordOperatorNote(
    String type,
    String id, {
    required String key,
    required String body,
  }) async {
    final permission = _notePermission(type),
        before = _requirePermission(permission);
    if (!before.usesCanonicalEvidence ||
        !_coreId(id) ||
        !RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key) ||
        body.trim().isEmpty ||
        body.length > 2000 ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(body)) {
      throw const FormatException('Enter a note of up to 2000 characters.');
    }
    final result = await session.request(
      'operations/$type/$id/notes',
      authenticated: true,
      method: 'POST',
      idempotencyKey: key,
      body: {'body': body.trim()},
    );
    final after = _requirePermission(permission);
    if (before.authorityKey != after.authorityKey) {
      throw const AdminAccountException(
        'Your session changed. Check the original request.',
      );
    }
    final receipt = CloudflareOperationReceipt.parse(result);
    if (receipt.resourceType != 'operator_notes' ||
        receipt.version != 1 ||
        receipt.requestId !=
            canonicalAdminRequestId(before.principalId ?? '', key)) {
      _invalidCore();
    }
    return receipt;
  }
}
