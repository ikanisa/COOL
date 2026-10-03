import 'dart:convert';
import 'dart:io';

// Dated isolated SQL observation with explicitly synthetic current read times.
// This adapter proves routing/state presentation, not current SQL installation.
Map<String, dynamic> adminExceptionListFixture(
  DateTime checked, {
  bool empty = false,
  int limit = 20,
}) {
  final raw = Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/admin_exception_reads_v2/observed-${empty ? 'empty' : 'populated'}.json',
          ).readAsStringSync(),
        )
        as Map,
  );
  String wire(DateTime value) {
    final iso = value.toUtc().toIso8601String();
    return RegExp(r'\.\d{3}Z$').hasMatch(iso)
        ? '${iso.substring(0, iso.length - 1)}000Z'
        : iso;
  }

  raw['limit'] = limit;
  raw['checked_at'] = wire(checked);
  raw['sample_valid_until'] = wire(checked.add(const Duration(seconds: 60)));
  return raw;
}
