import 'package:equatable/equatable.dart';

/// All action types that can earn COOL Status points.
///
/// Each type maps to a specific real user action — never pure login
/// or passive usage. Points are configurable per type.
enum CoolEventType {
  groupContribution, // savings group deposit confirmed
  groupCycleComplete, // full group cycle finished
  matchAttendance, // ticket used at match (scanned)
  initiativeSupport, // initiative contribution confirmed
  tripCompleted, // reliable trip completion
  tripPosted, // trip posted (driver or passenger)
  inviteQualified, // invitee completed qualifying action
  shopPurchase, // shop order confirmed
  clubJoined, // fan club membership created
  streakMaintained, // weekly streak check passed
  missionCompleted, // cooperative mission goal met
}

extension CoolEventTypeX on CoolEventType {
  String get value => name;

  static CoolEventType fromValue(String? value) {
    final normalized = (value ?? '').trim();
    for (final type in CoolEventType.values) {
      if (type.name == normalized) return type;
    }
    return CoolEventType.groupContribution;
  }

  /// Default points for this event type.
  /// All qualifying activities earn a flat 10 points.
  /// Can be overridden per-event via [CoolEvent.pointsAwarded].
  int get defaultPoints => 10;

  String get displayLabel => switch (this) {
    CoolEventType.groupContribution => 'Group Contribution',
    CoolEventType.groupCycleComplete => 'Group Cycle Complete',
    CoolEventType.matchAttendance => 'Match Attendance',
    CoolEventType.initiativeSupport => 'Initiative Support',
    CoolEventType.tripCompleted => 'Trip Completed',
    CoolEventType.tripPosted => 'Trip Posted',
    CoolEventType.inviteQualified => 'Invite Qualified',
    CoolEventType.shopPurchase => 'Shop Purchase',
    CoolEventType.clubJoined => 'Club Joined',
    CoolEventType.streakMaintained => 'Streak Maintained',
    CoolEventType.missionCompleted => 'Mission Completed',
  };

  String get emoji => switch (this) {
    CoolEventType.groupContribution => '💰',
    CoolEventType.groupCycleComplete => '🎯',
    CoolEventType.matchAttendance => '⚽',
    CoolEventType.initiativeSupport => '🤝',
    CoolEventType.tripCompleted => '🚗',
    CoolEventType.tripPosted => '📍',
    CoolEventType.inviteQualified => '🎉',
    CoolEventType.shopPurchase => '🛍️',
    CoolEventType.clubJoined => '🏟️',
    CoolEventType.streakMaintained => '🔥',
    CoolEventType.missionCompleted => '🏆',
  };
}

/// A single point-awarding event in the COOL Status system.
class CoolEvent extends Equatable {
  const CoolEvent({
    this.id,
    required this.userId,
    required this.eventType,
    this.sourceId,
    required this.pointsAwarded,
    this.metadata = const {},
    this.referrerId,
    this.dedupeKey,
    this.campaignId,
    this.seasonId,
    this.createdAt,
  });

  final String? id;
  final String userId;
  final CoolEventType eventType;
  final String? sourceId;
  final int pointsAwarded;
  final Map<String, dynamic> metadata;
  final String? referrerId;
  final String? dedupeKey;
  final String? campaignId;
  final String? seasonId;
  final DateTime? createdAt;

  factory CoolEvent.fromJson(Map<String, dynamic> json) {
    return CoolEvent(
      id: json['id']?.toString(),
      userId: (json['user_id'] ?? '').toString(),
      eventType: CoolEventTypeX.fromValue(json['event_type']?.toString()),
      sourceId: json['source_id']?.toString(),
      pointsAwarded: _asInt(json['points_awarded']),
      metadata: json['metadata'] is Map
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const {},
      referrerId: json['referrer_id']?.toString(),
      dedupeKey: json['dedupe_key']?.toString(),
      campaignId: json['campaign_id']?.toString(),
      seasonId: json['season_id']?.toString(),
      createdAt: _asDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toInsertJson() {
    final data = <String, dynamic>{
      'user_id': userId,
      'event_type': eventType.value,
      'points_awarded': pointsAwarded,
      'metadata': metadata,
    };
    if (sourceId != null) data['source_id'] = sourceId;
    if (referrerId != null) data['referrer_id'] = referrerId;
    if (dedupeKey != null) data['dedupe_key'] = dedupeKey;
    if (campaignId != null) data['campaign_id'] = campaignId;
    if (seasonId != null) data['season_id'] = seasonId;
    return data;
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    eventType,
    sourceId,
    pointsAwarded,
    metadata,
    referrerId,
    dedupeKey,
    campaignId,
    seasonId,
    createdAt,
  ];
}

// ─── Parsing helpers ──────────────────────────────────────────────

int _asInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
