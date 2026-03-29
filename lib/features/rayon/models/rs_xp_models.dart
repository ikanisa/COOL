import 'package:equatable/equatable.dart';

/// Defines the XP reward table for all fan actions.
///
/// Each [XpEventType] maps to a specific user action that awards XP.
/// The XP values and frequency limits match the blueprint specification.
enum XpEventType {
  dailyOpen,
  matchAttendance,
  contribution,
  createGroup,
  inviteFriends,
  shopPurchase,
  completeProfile,
  weekStreak,
  monthStreak,
}

extension XpEventTypeX on XpEventType {
  /// XP points awarded for this event.
  int get xpReward => switch (this) {
    XpEventType.dailyOpen => 10,
    XpEventType.matchAttendance => 500,
    XpEventType.contribution => 50,
    XpEventType.createGroup => 200,
    XpEventType.inviteFriends => 150,
    XpEventType.shopPurchase => 100,
    XpEventType.completeProfile => 300,
    XpEventType.weekStreak => 250,
    XpEventType.monthStreak => 1000,
  };

  /// Display label for the XP event.
  String get label => switch (this) {
    XpEventType.dailyOpen => 'Daily Check-In',
    XpEventType.matchAttendance => 'Match Attendance',
    XpEventType.contribution => 'Make Contribution',
    XpEventType.createGroup => 'Create Circle',
    XpEventType.inviteFriends => 'Invite 3 Friends',
    XpEventType.shopPurchase => 'Shop Purchase',
    XpEventType.completeProfile => 'Complete Profile',
    XpEventType.weekStreak => '7-Day Streak',
    XpEventType.monthStreak => '30-Day Streak',
  };

  /// Emoji icon for the XP event.
  String get emoji => switch (this) {
    XpEventType.dailyOpen => '📅',
    XpEventType.matchAttendance => '🏟️',
    XpEventType.contribution => '💰',
    XpEventType.createGroup => '👥',
    XpEventType.inviteFriends => '📣',
    XpEventType.shopPurchase => '🛍️',
    XpEventType.completeProfile => '✅',
    XpEventType.weekStreak => '🔥',
    XpEventType.monthStreak => '💎',
  };

  /// Frequency description.
  String get frequency => switch (this) {
    XpEventType.dailyOpen => 'Once per day',
    XpEventType.matchAttendance => 'Per match',
    XpEventType.contribution => 'Per transaction',
    XpEventType.createGroup => 'Per creation',
    XpEventType.inviteFriends => 'Per 3 invites',
    XpEventType.shopPurchase => 'Per purchase',
    XpEventType.completeProfile => 'One-time',
    XpEventType.weekStreak => 'Per week',
    XpEventType.monthStreak => 'Per month',
  };

  /// Whether this is a streak-based event.
  bool get isStreak => this == XpEventType.weekStreak ||
      this == XpEventType.monthStreak;

  /// The event key used in database storage.
  String get eventKey => switch (this) {
    XpEventType.dailyOpen => 'daily_open',
    XpEventType.matchAttendance => 'match_attendance',
    XpEventType.contribution => 'contribution',
    XpEventType.createGroup => 'create_group',
    XpEventType.inviteFriends => 'invite_friends',
    XpEventType.shopPurchase => 'shop_purchase',
    XpEventType.completeProfile => 'complete_profile',
    XpEventType.weekStreak => 'week_streak',
    XpEventType.monthStreak => 'month_streak',
  };

  /// Parse an event key back to an [XpEventType].
  static XpEventType? fromKey(String key) {
    for (final type in XpEventType.values) {
      if (type.eventKey == key) return type;
    }
    return null;
  }
}

/// A single XP event log entry.
class XpEvent extends Equatable {
  const XpEvent({
    required this.id,
    required this.userId,
    required this.eventType,
    required this.xpAwarded,
    required this.eventAt,
    this.metadata,
  });

  final String id;
  final String userId;
  final XpEventType eventType;
  final int xpAwarded;
  final DateTime eventAt;
  final Map<String, Object?>? metadata;

  factory XpEvent.fromJson(Map<String, dynamic> json) {
    return XpEvent(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      eventType: XpEventTypeX.fromKey(
            (json['event_type'] ?? '').toString(),
          ) ??
          XpEventType.dailyOpen,
      xpAwarded: (json['xp_awarded'] as num?)?.toInt() ?? 0,
      eventAt: DateTime.tryParse(json['event_at']?.toString() ?? '') ??
          DateTime.now(),
      metadata: json['metadata'] is Map
          ? Map<String, Object?>.from(json['metadata'] as Map)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, userId, eventType, xpAwarded, eventAt];
}
