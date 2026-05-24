import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'phone_normalizer.dart';

class HashUtils {
  const HashUtils._();

  static String sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String phoneHash(String value) {
    return sha256Hex(PhoneNormalizer.normalizeRwanda(value));
  }
}
