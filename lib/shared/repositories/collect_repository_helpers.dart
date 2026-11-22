part of 'collect_repository.dart';

String _slug(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? 'group' : slug;
}

String _defaultLocalMomoFromPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^2507[2389][0-9]{7}$').hasMatch(digits)) {
    return '0${digits.substring(3)}';
  }
  return '';
}

String _defaultMomoProviderFromPhone(String phone) {
  final local = _defaultLocalMomoFromPhone(phone);
  return RegExp(r'^07[23]').hasMatch(local) ? 'airtel_money' : 'mtn_momo';
}

String _normalizeLocalRwandaMomo(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final local = digits.startsWith('250') && digits.length == 12
      ? '0${digits.substring(3)}'
      : digits.length == 9 && digits.startsWith('7')
      ? '0$digits'
      : digits;
  if (!RegExp(r'^07[2389][0-9]{7}$').hasMatch(local)) {
    throw const FormatException('Use a Rwanda MoMo number such as 078XXXXXXX.');
  }
  return local;
}
