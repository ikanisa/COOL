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
      'consent_version': consentVersion,
      'embedding': embedding,
      if (liveness != null) 'liveness': liveness,
    };
  }
}
