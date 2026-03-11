import 'package:equatable/equatable.dart';

/// A time-limited engagement campaign (2–4 weeks).
///
/// Season-scoped points reset each season; permanent tier/total never resets.
class CoolSeason extends Equatable {
  const CoolSeason({
    required this.id,
    required this.title,
    required this.theme,
    required this.emoji,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
    this.rewardsDescription,
  });

  final String id;
  final String title;
  final String theme;    // 'savings', 'supporter', 'commuter', 'matchday'
  final String emoji;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;
  final String? rewardsDescription;

  // ─── Computed ───────────────────────────────────────────────────

  bool get isExpired => DateTime.now().isAfter(endsAt);
  bool get isUpcoming => DateTime.now().isBefore(startsAt);
  bool get isLive => isActive && !isExpired && !isUpcoming;

  Duration get timeRemaining {
    final now = DateTime.now();
    return endsAt.isAfter(now) ? endsAt.difference(now) : Duration.zero;
  }

  String get timeRemainingLabel {
    final remaining = timeRemaining;
    if (remaining == Duration.zero) return 'Ended';
    if (remaining.inDays > 0) return '${remaining.inDays}d left';
    if (remaining.inHours > 0) return '${remaining.inHours}h left';
    return '${remaining.inMinutes}m left';
  }

  double get progressThroughSeason {
    final total = endsAt.difference(startsAt).inSeconds;
    if (total <= 0) return 1;
    final elapsed = DateTime.now().difference(startsAt).inSeconds;
    return (elapsed / total).clamp(0, 1).toDouble();
  }

  // ─── Serialization ──────────────────────────────────────────────

  factory CoolSeason.fromJson(Map<String, dynamic> json) {
    return CoolSeason(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Season').toString(),
      theme: (json['theme'] ?? 'supporter').toString(),
      emoji: (json['emoji'] ?? '🏅').toString(),
      startsAt: _asDateTime(json['starts_at']) ?? DateTime.now(),
      endsAt: _asDateTime(json['ends_at']) ?? DateTime.now(),
      isActive: _asBool(json['is_active']),
      rewardsDescription: json['rewards_description']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
    id, title, theme, emoji, startsAt, endsAt, isActive, rewardsDescription,
  ];
}

// ─── Helpers ──────────────────────────────────────────────────────

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final s = value.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}
