import '../../../core/config/country_catalog.dart';

class BiopayEnrollmentDraft {
  const BiopayEnrollmentDraft({
    required this.displayName,
    required this.routeType,
    required this.recipientValue,
    required this.countryCode,
    required this.consentVersion,
  });

  final String displayName;
  final MomoRecipientType routeType;
  final String recipientValue;
  final String countryCode;
  final String consentVersion;

  Map<String, Object?> toPayload(
    List<double> embedding, {
    Map<String, Object?>? liveness,
  }) {
    return <String, Object?>{
      'display_name': displayName,
      'route_type': switch (routeType) {
        MomoRecipientType.phoneNumber => 'phone_number',
        MomoRecipientType.code => 'code',
      },
      'recipient_value': recipientValue.trim(),
      'country_code': countryCode.trim().isEmpty ? 'RW' : countryCode.trim(),
      'consent_version': consentVersion,
      'embedding': embedding,
      ...?(liveness == null ? null : <String, Object?>{'liveness': liveness}),
    };
  }
}
