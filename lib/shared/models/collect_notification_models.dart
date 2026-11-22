import 'package:flutter/foundation.dart' show immutable;

import '../../core/data/exact_json_values.dart';

import 'collect_model_json_helpers.dart';

@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.contributionConfirmations = true,
    this.paymentReminders = true,
    this.groupUpdates = true,
    this.securityNotices = true,
    this.emailEnabled = false,
  });

  final bool contributionConfirmations;
  final bool paymentReminders;
  final bool groupUpdates;
  final bool securityNotices;
  final bool emailEnabled;

  static const defaults = NotificationPreferences();

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      contributionConfirmations:
          (json['contribution_confirmations'] as bool?) ?? true,
      paymentReminders: (json['payment_reminders'] as bool?) ?? true,
      groupUpdates: (json['group_updates'] as bool?) ?? true,
      securityNotices: (json['security_notices'] as bool?) ?? true,
      emailEnabled: (json['email_enabled'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contribution_confirmations': contributionConfirmations,
      'payment_reminders': paymentReminders,
      'group_updates': groupUpdates,
      'security_notices': securityNotices,
      'email_enabled': emailEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? contributionConfirmations,
    bool? paymentReminders,
    bool? groupUpdates,
    bool? securityNotices,
    bool? emailEnabled,
  }) {
    return NotificationPreferences(
      contributionConfirmations:
          contributionConfirmations ?? this.contributionConfirmations,
      paymentReminders: paymentReminders ?? this.paymentReminders,
      groupUpdates: groupUpdates ?? this.groupUpdates,
      securityNotices: securityNotices ?? this.securityNotices,
      emailEnabled: emailEnabled ?? this.emailEnabled,
    );
  }
}

@immutable
class NotificationEvent {
  const NotificationEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.collectionId,
    this.deepLink,
    this.sentAt,
    this.readAt,
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String status;
  final DateTime createdAt;
  final String? collectionId;
  final String? deepLink;
  final DateTime? sentAt;
  final DateTime? readAt;

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    return NotificationEvent(
      id: exactJsonIdentifier(json['id'], field: 'notification.id'),
      userId: exactJsonIdentifier(
        json['user_id'],
        field: 'notification.user_id',
      ),
      collectionId: json['collection_id'] == null
          ? null
          : exactJsonIdentifier(
              json['collection_id'],
              field: 'notification.collection_id',
            ),
      type: (json['type'] as String?) ?? 'group_update',
      title: (json['title'] as String?) ?? 'Notification',
      body: (json['body'] as String?) ?? '',
      deepLink: json['deep_link'] as String?,
      status: (json['status'] as String?) ?? 'queued',
      createdAt: modelJsonTimestamp(json['created_at']),
      sentAt: json['sent_at'] == null
          ? null
          : modelJsonTimestamp(json['sent_at']),
      readAt: json['read_at'] == null
          ? null
          : modelJsonTimestamp(json['read_at']),
    );
  }

  bool get unread => status != 'read';

  NotificationEvent copyWith({String? status, DateTime? readAt}) {
    return NotificationEvent(
      id: id,
      userId: userId,
      collectionId: collectionId,
      type: type,
      title: title,
      body: body,
      deepLink: deepLink,
      status: status ?? this.status,
      createdAt: createdAt,
      sentAt: sentAt,
      readAt: readAt ?? this.readAt,
    );
  }
}
