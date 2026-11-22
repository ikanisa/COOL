import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Server-confirmed storage acknowledgement, not financial settlement.
class DurableSmsReceipt {
  const DurableSmsReceipt._({
    required this.rawSmsId,
    required this.envelopeId,
    required this.ownerUserId,
    required this.bodySha256,
  });
  final String rawSmsId;
  final String envelopeId;
  final String ownerUserId;
  final String bodySha256;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  factory DurableSmsReceipt.decode(
    Object? payload, {
    required String expectedOwner,
    required String expectedEnvelope,
    required String rawBody,
  }) {
    Object? value = payload;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        throw const FormatException('Receipt acknowledgement unavailable.');
      }
    }
    if (value is! Map || value['ok'] != true || value['receipt'] is! Map) {
      throw const FormatException('Receipt acknowledgement unavailable.');
    }
    final receipt = value['receipt'] as Map;
    final id = receipt['raw_sms_id'];
    final digest = sha256.convert(utf8.encode(rawBody)).toString();
    if (!_uuid.hasMatch(expectedOwner) ||
        !_uuid.hasMatch(expectedEnvelope) ||
        receipt['contract_version'] != 2 ||
        receipt['stored'] != true ||
        id is! String ||
        !_uuid.hasMatch(id) ||
        receipt['owner_user_id'] != expectedOwner ||
        receipt['client_envelope_id'] != expectedEnvelope ||
        receipt['body_sha256'] != digest) {
      throw const FormatException(
        'Receipt acknowledgement does not match this account and message.',
      );
    }
    return DurableSmsReceipt._(
      rawSmsId: id,
      envelopeId: expectedEnvelope,
      ownerUserId: expectedOwner,
      bodySha256: digest,
    );
  }
}
