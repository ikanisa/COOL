import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'momo_receiver_normalizer.dart';
import 'phone_normalizer.dart';

class HashUtils {
  const HashUtils._();

  static String sha256Hex(String value) {
    return sha256.convert(utf8.encode(value)).toString();
  }

  static String phoneHash(String value) {
    return sha256Hex(PhoneNormalizer.normalizeRwanda(value));
  }

  static String momoReceiverHash(String value, {required bool isMomoPayCode}) {
    if (!isMomoPayCode) return phoneHash(value);
    final code = MomoReceiverNormalizer.normalizePayCode(value);
    // The Edge hash normalizer prefixes non-phone digit identifiers with "+".
    // Keep that canonical form so code receivers match during SMS ingestion.
    return sha256Hex('+$code');
  }
}
