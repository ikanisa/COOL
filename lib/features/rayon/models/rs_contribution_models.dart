import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../core/config/country_catalog.dart';
import '../../../../core/theme/rs_colors.dart';

// ═══════════════════════════════════════════════════════════
// Contribution Group Types & Privacy
// ═══════════════════════════════════════════════════════════

/// The type of contribution group (per blueprint §6.6).
enum ContributionGroupType { club, community, savings, fanCircle }

extension ContributionGroupTypeX on ContributionGroupType {
  static ContributionGroupType fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'club' => ContributionGroupType.club,
      'community' => ContributionGroupType.community,
      'savings' => ContributionGroupType.savings,
      'fan_circle' || 'fanCircle' => ContributionGroupType.fanCircle,
      _ => ContributionGroupType.community,
    };
  }

  String get value => switch (this) {
    ContributionGroupType.club => 'club',
    ContributionGroupType.community => 'community',
    ContributionGroupType.savings => 'savings',
    ContributionGroupType.fanCircle => 'fan_circle',
  };

  String get label => switch (this) {
    ContributionGroupType.club => 'Club Project',
    ContributionGroupType.community => 'Community Circle',
    ContributionGroupType.savings => 'Public Savings',
    ContributionGroupType.fanCircle => 'Fan Circle',
  };

  IconData get icon => switch (this) {
    ContributionGroupType.club => Icons.stadium_rounded,
    ContributionGroupType.community => Icons.people_alt_rounded,
    ContributionGroupType.savings => Icons.savings_rounded,
    ContributionGroupType.fanCircle => Icons.auto_awesome_rounded,
  };

  Color get color => switch (this) {
    ContributionGroupType.club => RsColors.rsRed,
    ContributionGroupType.community => RsColors.rsNavyLight,
    ContributionGroupType.savings => RsColors.rsGold,
    ContributionGroupType.fanCircle => const Color(0xFFAB47BC),
  };
}

/// Group privacy level.
enum GroupPrivacy { public, friends, private_ }

extension GroupPrivacyX on GroupPrivacy {
  static GroupPrivacy fromValue(String? value) {
    return switch ((value ?? '').toLowerCase()) {
      'public' => GroupPrivacy.public,
      'friends' => GroupPrivacy.friends,
      'private' => GroupPrivacy.private_,
      _ => GroupPrivacy.public,
    };
  }

  String get value => switch (this) {
    GroupPrivacy.public => 'public',
    GroupPrivacy.friends => 'friends',
    GroupPrivacy.private_ => 'private',
  };

  String get label => switch (this) {
    GroupPrivacy.public => 'Public',
    GroupPrivacy.friends => 'Friends Only',
    GroupPrivacy.private_ => 'Private',
  };

  IconData get icon => switch (this) {
    GroupPrivacy.public => Icons.public_rounded,
    GroupPrivacy.friends => Icons.group_rounded,
    GroupPrivacy.private_ => Icons.lock_rounded,
  };
}

// ═══════════════════════════════════════════════════════════
// Contribution Group Model
// ═══════════════════════════════════════════════════════════

class RsContributionGroup extends Equatable {
  const RsContributionGroup({
    required this.id,
    required this.creatorId,
    required this.name,
    this.description,
    this.groupType = ContributionGroupType.community,
    this.privacy = GroupPrivacy.public,
    this.targetAmount = 0,
    this.currentTotal = 0,
    this.momoNumber,
    this.receivingMomoCode,
    this.momoRouteType,
    this.deadline,
    this.isRecurring = false,
    this.isClosed = false,
    this.inviteCode,
    this.memberCount = 0,
    required this.createdAt,
  });

  final String id;
  final String creatorId;
  final String name;
  final String? description;
  final ContributionGroupType groupType;
  final GroupPrivacy privacy;
  final int targetAmount;
  final int currentTotal;
  final String? momoNumber;
  final String? receivingMomoCode;
  final MomoRecipientType? momoRouteType;
  final DateTime? deadline;
  final bool isRecurring;
  final bool isClosed;
  final String? inviteCode;
  final int memberCount;
  final DateTime createdAt;

  /// Progress fraction: 0.0 – 1.0
  double get progress =>
      targetAmount > 0 ? (currentTotal / targetAmount).clamp(0.0, 1.0) : 0.0;

  /// Remaining amount
  int get remaining => (targetAmount - currentTotal).clamp(0, targetAmount);

  /// Whether the deadline has passed
  bool get isExpired => deadline != null && deadline!.isBefore(DateTime.now());

  MomoRecipientType? get effectiveMomoRouteType {
    if (momoRouteType != null) {
      return momoRouteType;
    }
    final number = momoNumber?.trim() ?? '';
    final code = receivingMomoCode?.trim() ?? '';
    if (number.isNotEmpty) {
      return MomoRecipientType.phoneNumber;
    }
    if (code.isNotEmpty) {
      return MomoRecipientType.code;
    }
    return null;
  }

  String get paymentRecipientValue {
    return switch (effectiveMomoRouteType) {
      MomoRecipientType.phoneNumber =>
        momoNumber?.trim().isNotEmpty == true
            ? momoNumber!.trim()
            : receivingMomoCode?.trim() ?? '',
      MomoRecipientType.code =>
        receivingMomoCode?.trim().isNotEmpty == true
            ? receivingMomoCode!.trim()
            : momoNumber?.trim() ?? '',
      null =>
        receivingMomoCode?.trim().isNotEmpty == true
            ? receivingMomoCode!.trim()
            : momoNumber?.trim() ?? '',
    };
  }

  factory RsContributionGroup.fromJson(Map<String, dynamic> json) {
    return RsContributionGroup(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      groupType: ContributionGroupTypeX.fromValue(
        json['group_type'] as String?,
      ),
      privacy: GroupPrivacyX.fromValue(json['privacy'] as String?),
      targetAmount: ((json['target_amount'] as num?) ?? 0).toInt(),
      currentTotal: ((json['current_total'] as num?) ?? 0).toInt(),
      momoNumber: json['momo_number'] as String?,
      receivingMomoCode:
          json['receiving_momo_code'] as String? ??
          json['momo_code'] as String?,
      momoRouteType: _parseMomoRecipientType(
        json['momo_route_type']?.toString(),
      ),
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'] as String)
          : null,
      isRecurring: json['is_recurring'] as bool? ?? false,
      isClosed: json['is_closed'] as bool? ?? false,
      inviteCode: json['invite_code'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'name': name,
    'description': description,
    'group_type': groupType.value,
    'privacy': privacy.value,
    'target_amount': targetAmount,
    'momo_number': momoNumber,
    'receiving_momo_code': receivingMomoCode,
    'momo_route_type': _serializeMomoRecipientType(effectiveMomoRouteType),
    'momo_code': paymentRecipientValue.isEmpty ? null : paymentRecipientValue,
    'deadline': deadline?.toIso8601String(),
    'is_recurring': isRecurring,
  };

  @override
  List<Object?> get props => [id, creatorId, name, currentTotal, isClosed];
}

MomoRecipientType? _parseMomoRecipientType(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'phone_number' || 'phone' => MomoRecipientType.phoneNumber,
    'code' => MomoRecipientType.code,
    _ => null,
  };
}

String? _serializeMomoRecipientType(MomoRecipientType? value) {
  return switch (value) {
    MomoRecipientType.phoneNumber => 'phone_number',
    MomoRecipientType.code => 'code',
    null => null,
  };
}

// ═══════════════════════════════════════════════════════════
// Group Message Model
// ═══════════════════════════════════════════════════════════

class RsGroupMessage extends Equatable {
  const RsGroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.alias,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String groupId;
  final String senderId;
  final String? alias;
  final String content;
  final DateTime createdAt;

  factory RsGroupMessage.fromJson(Map<String, dynamic> json) {
    return RsGroupMessage(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      senderId: json['sender_id'] as String,
      alias: json['alias'] as String?,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'group_id': groupId,
    'content': content,
  };

  @override
  List<Object?> get props => [id, groupId, senderId, content];
}
