import '../security/phone_normalizer.dart';

/// The same Rwanda mobile prefixes accepted by Collect's profile validation.
/// This identifies a provider only after the entire number is valid.
class RwandaMomoNumber {
  const RwandaMomoNumber._(this.localNumber, this.provider);

  final String localNumber;
  final String provider;

  factory RwandaMomoNumber.parse(String input) {
    const invalid = FormatException('Enter a valid Rwanda MoMo number.');
    if (!RegExp(r'^[+0-9\s()-]+$').hasMatch(input.trim())) throw invalid;
    late final String international;
    try {
      international = PhoneNormalizer.normalizeRwanda(input);
    } on FormatException {
      throw invalid;
    }
    if (!RegExp(r'^\+2507[2389][0-9]{7}$').hasMatch(international)) {
      throw invalid;
    }
    final local = '0${international.substring(4)}';
    return RwandaMomoNumber._(
      local,
      RegExp(r'^07[23]').hasMatch(local) ? 'airtel_money' : 'mtn_momo',
    );
  }
}
