class PublicUserIdentity {
  PublicUserIdentity._();

  static final RegExp _pattern = RegExp(r'^\d{6}$');

  static bool isValid(String? value) {
    return _pattern.hasMatch(value?.trim() ?? '');
  }

  static String normalize(String? value) {
    final trimmed = value?.trim() ?? '';
    return isValid(trimmed) ? trimmed : '';
  }

  static String resolve({
    String? publicUserId,
    String? userId,
    String? phone,
    String fallback = '000000',
  }) {
    final normalized = normalize(publicUserId);
    if (normalized.isNotEmpty) {
      return normalized;
    }

    final seed = '${userId?.trim() ?? ''}|${phone?.trim() ?? ''}';
    if (seed.replaceAll('|', '').isEmpty) {
      return fallback;
    }

    var hash = 0;
    for (final codeUnit in seed.codeUnits) {
      hash = ((hash * 131) + codeUnit) % 900000;
    }

    return (hash + 100000).toString().padLeft(6, '0');
  }
}
