part of 'collect_repository.dart';

String _normalizeMomoPayCode(String value) {
  return MomoReceiverNormalizer.normalizePayCode(value);
}

String _slug(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'group' : slug;
}
