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
  final ownedGroupReceivers = <String>{
    for (final collection in collections)
      if (collection.creatorUserId == profile.id &&
          !collection.isArchived &&
          collection.receiverMomoNumber?.trim().isNotEmpty == true)
        collection.receiverMomoNumber!.trim(),
  };
  final candidates = <String>{
    if (profile.momoNumber?.trim().isNotEmpty == true)
      profile.momoNumber!.trim(),
    if (profile.momoPayCode?.trim().isNotEmpty == true)
      profile.momoPayCode!.trim(),
    ...ownedGroupReceivers,
  };
  final bodyDigits = smsBody.replaceAll(RegExp(r'\D'), '');
  final explicitMatches = candidates
      .where((candidate) {
        final digits = candidate.replaceAll(RegExp(r'\D'), '');
        return digits.length >= MomoReceiverNormalizer.minPayCodeLength &&
            bodyDigits.contains(digits);
      })
      .toList(growable: false);
  if (explicitMatches.length == 1) return explicitMatches.single;
  // A receiver account that owns exactly one active group has one safe route,
  // even when the provider SMS omits the merchant code from its body. Profile
  // phone data must not make that otherwise unambiguous group route ambiguous.
  if (ownedGroupReceivers.length == 1) return ownedGroupReceivers.single;
  if (candidates.length == 1) return candidates.single;
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
