class PartnerCreditApplication {
  const PartnerCreditApplication({
    required this.id,
    required this.userId,
    required this.partnerId,
    required this.partnerName,
    required this.partnerSlug,
    required this.partnerEmoji,
    required this.applicationType,
    required this.status,
    required this.readinessState,
    this.requestedProduct,
    this.applicantNote,
    required this.officialName,
    required this.officialPhone,
    required this.kycStatus,
    this.creditScore,
    this.creditScoreBand,
    this.creditScoreVersion,
    this.scoreSummary,
    this.snapshotPayload = const <String, dynamic>{},
    this.submittedAt,
    this.lastHandoffAt,
    this.lastHandoffChannel,
    this.lastDestinationPath,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final String partnerId;
  final String partnerName;
  final String partnerSlug;
  final String partnerEmoji;
  final String applicationType;
  final String status;
  final String readinessState;
  final String? requestedProduct;
  final String? applicantNote;
  final String officialName;
  final String officialPhone;
  final String kycStatus;
  final int? creditScore;
  final String? creditScoreBand;
  final String? creditScoreVersion;
  final String? scoreSummary;
  final Map<String, dynamic> snapshotPayload;
  final DateTime? submittedAt;
  final DateTime? lastHandoffAt;
  final String? lastHandoffChannel;
  final String? lastDestinationPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isDraft => status == 'draft';

  bool get hasBeenRouted => status == 'partner_routed' || lastHandoffAt != null;

  String get applicationTypeLabel {
    return switch (applicationType) {
      'loan' => 'Loan Application',
      'account_opening' => 'Account Opening',
      _ => 'Application',
    };
  }

  String get statusLabel {
    return switch (status) {
      'draft' => 'Draft',
      'partner_routed' => 'Partner routed',
      'in_review' => 'In review',
      'partner_contacted' => 'Partner contacted',
      'closed' => 'Closed',
      'cancelled' => 'Cancelled',
      _ => status.replaceAll('_', ' '),
    };
  }

  factory PartnerCreditApplication.fromJson(Map<String, dynamic> json) {
    final partnerData = json['partners'];
    final partnerMap = partnerData is Map
        ? Map<String, dynamic>.from(partnerData)
        : const <String, dynamic>{};

    return PartnerCreditApplication(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      partnerId: json['partner_id']?.toString() ?? '',
      partnerName: partnerMap['name']?.toString() ?? 'Partner',
      partnerSlug: partnerMap['slug']?.toString() ?? '',
      partnerEmoji: partnerMap['emoji']?.toString() ?? '🏦',
      applicationType: json['application_type']?.toString() ?? 'loan',
      status: json['status']?.toString() ?? 'draft',
      readinessState: json['readiness_state']?.toString() ?? 'building',
      requestedProduct: _asNonEmptyString(json['requested_product']),
      applicantNote: _asNonEmptyString(json['applicant_note']),
      officialName: json['official_name']?.toString() ?? '',
      officialPhone: json['official_phone']?.toString() ?? '',
      kycStatus: json['kyc_status']?.toString() ?? 'unverified',
      creditScore: _asIntOrNull(json['credit_score']),
      creditScoreBand: _asNonEmptyString(json['credit_score_band']),
      creditScoreVersion: _asNonEmptyString(json['credit_score_version']),
      scoreSummary: _asNonEmptyString(json['score_summary']),
      snapshotPayload: _asMap(json['snapshot_payload']),
      submittedAt: _parseDateTime(json['submitted_at']),
      lastHandoffAt: _parseDateTime(json['last_handoff_at']),
      lastHandoffChannel: _asNonEmptyString(json['last_handoff_channel']),
      lastDestinationPath: _asNonEmptyString(json['last_destination_path']),
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

String? _asNonEmptyString(dynamic value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

int? _asIntOrNull(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value == null) {
    return null;
  }
  return int.tryParse(value.toString());
}
