part of 'collect_repository.dart';

String _normalizeMomoPayCode(String value) {
  return MomoReceiverNormalizer.normalizePayCode(value);
}

String? _profileSmsReceiverHash(CollectProfile profile) {
  final momoNumber = profile.momoNumber?.trim();
  if (momoNumber != null && momoNumber.isNotEmpty) {
    return HashUtils.momoReceiverHash(momoNumber, isMomoPayCode: false);
  }
  final momoPayCode = profile.momoPayCode?.trim();
  if (momoPayCode != null && momoPayCode.isNotEmpty) {
    return HashUtils.momoReceiverHash(momoPayCode, isMomoPayCode: true);
  }
  return null;
}

String? _resolveSmsReceiver(
  CollectProfile profile,
  Iterable<CollectCollection> collections,
  String smsBody,
) {
  final authorizedGroupReceivers = <String>{
    for (final collection in collections)
      if (!collection.isArchived &&
          collection.receiverMomoNumber?.trim().isNotEmpty == true)
        collection.receiverMomoNumber!.trim(),
  };
  final explicitMatches = authorizedGroupReceivers
      .where((candidate) {
        final digits = candidate.replaceAll(RegExp(r'\D'), '');
        if (digits.length < MomoReceiverNormalizer.minPayCodeLength) {
          return false;
        }
        final separatedDigits = digits
            .split('')
            .map(RegExp.escape)
            .join(r'[\s-]*');
        final labeledReceiver = RegExp(
          '(?:receiver|receiving|merchant|pay(?:ment)?[ -]?code|account|to)'
          '[^0-9]{0,40}(?<![0-9])$separatedDigits(?![0-9])',
          caseSensitive: false,
        );
        return labeledReceiver.hasMatch(smsBody);
      })
      .toList(growable: false);
  if (explicitMatches.length == 1) return explicitMatches.single;
  // An account authorized for exactly one active receiver has one safe route,
  // even when the provider SMS omits the merchant code from its body. Profile
  // profile phone data must not make that route ambiguous.
  if (authorizedGroupReceivers.length == 1) {
    return authorizedGroupReceivers.single;
  }
  // Let the backend parser extract the receiver when more than one receiver is
  // configured. Guessing here could allocate a payment to the wrong group.
  return null;
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
