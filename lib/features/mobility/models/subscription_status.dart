class SubscriptionStatus {
  const SubscriptionStatus({
    required this.driverId,
    required this.status,
    required this.tripsUsed,
    required this.tripsRemaining,
    this.planId,
    this.planName,
    this.amountRwf,
    this.expiresAt,
    this.createdAt,
  });

  final String driverId;
  final String status;
  final int tripsUsed;
  final int tripsRemaining;
  final String? planId;
  final String? planName;
  final int? amountRwf;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isSubscribed =>
      status.trim().toLowerCase() == 'active' &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    final tripsUsed = _asInt(json['trips_used']);
    final expiresAt = _parseDateTime(json['expires_at']);
    final status = json['status']?.toString() ?? 'free';
    final normalizedStatus = status.trim().toLowerCase();
    return SubscriptionStatus(
      driverId:
          json['driver_id']?.toString() ?? json['user_id']?.toString() ?? '',
      status: status,
      tripsUsed: tripsUsed,
      tripsRemaining: _asInt(
        json['trips_remaining'] ??
            (normalizedStatus == 'active' &&
                    (expiresAt == null || expiresAt.isAfter(DateTime.now()))
                ? -1
                : 0),
      ),
      planId: json['plan_id']?.toString() ?? json['plan']?.toString(),
      planName:
          json['plan_name']?.toString() ?? json['vehicle_type']?.toString(),
      amountRwf: _nullableInt(
        json['amount_rwf'] ?? json['amount'] ?? json['amount_paid'],
      ),
      expiresAt: expiresAt,
      createdAt: _parseDateTime(
        json['created_at'] ?? json['started_at'] ?? json['starts_at'],
      ),
    );
  }

  factory SubscriptionStatus.freeTier({
    required String driverId,
    required int tripsUsed,
  }) {
    return SubscriptionStatus(
      driverId: driverId,
      status: 'free',
      tripsUsed: tripsUsed,
      tripsRemaining: 0,
    );
  }

  SubscriptionStatus copyWith({
    String? driverId,
    String? status,
    int? tripsUsed,
    int? tripsRemaining,
    String? planId,
    String? planName,
    int? amountRwf,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) {
    return SubscriptionStatus(
      driverId: driverId ?? this.driverId,
      status: status ?? this.status,
      tripsUsed: tripsUsed ?? this.tripsUsed,
      tripsRemaining: tripsRemaining ?? this.tripsRemaining,
      planId: planId ?? this.planId,
      planName: planName ?? this.planName,
      amountRwf: amountRwf ?? this.amountRwf,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

int? _nullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  return _asInt(value);
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
