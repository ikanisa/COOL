import 'dart:convert';
import 'dart:io';

// Declared synthetic model-shaped documents, normalized to the explicitly
// controlled test clock. These are DTO inputs, not live server receipts.
Map<String, dynamic> adminGatewayListFixture(
  DateTime checkedAt, {
  bool empty = false,
  int limit = 20,
}) {
  final raw = _fixture('collect-admin-gateway-v1.fixture.json', checkedAt);
  raw['limit'] = limit;
  if (empty) {
    raw['rows'] = [];
    raw['total'] = 0;
    raw['next_cursor'] = null;
  }
  return raw;
}

Map<String, dynamic> adminGatewayRequestFixture(DateTime checkedAt) =>
    _fixture('collect-admin-gateway-owner-request-v1.fixture.json', checkedAt);

Map<String, dynamic> _fixture(String name, DateTime checkedAt) {
  final raw =
      jsonDecode(File('test/fixtures/declared_admin/$name').readAsStringSync())
          as Map<String, dynamic>;
  final difference = checkedAt.toUtc().difference(
    DateTime.parse(raw['checked_at'] as String),
  );
  Object? shift(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key, shift(item)));
    }
    if (value is List) return value.map(shift).toList();
    if (value is String && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(value)) {
      return DateTime.parse(value).add(difference).toUtc().toIso8601String();
    }
    return value;
  }

  return Map<String, dynamic>.from(shift(raw) as Map);
}
