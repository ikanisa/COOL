part of 'collect_repository.dart';

String _normalizeMomoPayCode(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 5 && digits.length <= 6) return digits;
  throw const FormatException('Use a 5 or 6 digit MoMo code.');
}

String _slug(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'group' : slug;
}

Map<String, dynamic> _singleRpcRow(dynamic response) {
  if (response is List && response.isNotEmpty) {
    return Map<String, dynamic>.from(response.first as Map);
  }
  if (response is Map) {
    return Map<String, dynamic>.from(response);
  }
  throw StateError('Expected one RPC result row');
}
