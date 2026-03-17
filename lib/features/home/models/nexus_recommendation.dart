import 'package:flutter/material.dart';

/// Approval status for AI-generated content.
enum AiContentStatus {
  draft,
  pendingReview,
  approved,
  rejected;

  String get label => switch (this) {
    AiContentStatus.draft => 'Draft',
    AiContentStatus.pendingReview => 'Pending Review',
    AiContentStatus.approved => 'Approved',
    AiContentStatus.rejected => 'Rejected',
  };

  String get dbValue => switch (this) {
    AiContentStatus.draft => 'draft',
    AiContentStatus.pendingReview => 'pending_review',
    AiContentStatus.approved => 'approved',
    AiContentStatus.rejected => 'rejected',
  };

  Color get color => switch (this) {
    AiContentStatus.draft => Colors.grey,
    AiContentStatus.pendingReview => Colors.orange,
    AiContentStatus.approved => Colors.green,
    AiContentStatus.rejected => Colors.red,
  };

  static AiContentStatus fromDb(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'draft' => AiContentStatus.draft,
      'pending_review' => AiContentStatus.pendingReview,
      'approved' => AiContentStatus.approved,
      'rejected' => AiContentStatus.rejected,
      _ => AiContentStatus.draft,
    };
  }
}

/// Types of AI-generated content.
enum AiContentType {
  recommendation,
  banner,
  promo,
  tip;

  String get label => switch (this) {
    AiContentType.recommendation => 'FOR YOU',
    AiContentType.banner => 'BANNER',
    AiContentType.promo => 'PROMOTION',
    AiContentType.tip => 'TIP',
  };

  String get dbValue => name;

  static AiContentType fromDb(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return AiContentType.values.firstWhere(
      (t) => t.name.toLowerCase() == normalized,
      orElse: () => AiContentType.recommendation,
    );
  }
}

/// A dynamic AI-generated content card for the Home screen.
class NexusRecommendation {
  const NexusRecommendation({
    required this.id,
    required this.title,
    required this.subtitle,
    this.body = '',
    this.rationale = '',
    required this.contentType,
    required this.status,
    this.iconEmoji = '✨',
    this.ctaAction = '',
    this.ctaLabel = '',
    this.country,
    this.sortOrder = 0,
    this.isActive = true,
    this.createdBy,
    this.reviewedBy,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final String body;
  final String rationale;
  final AiContentType contentType;
  final AiContentStatus status;
  final String iconEmoji;
  final String ctaAction;
  final String ctaLabel;
  final String? country;
  final int sortOrder;
  final bool isActive;
  final String? createdBy;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory NexusRecommendation.fromJson(Map<String, dynamic> json) {
    return NexusRecommendation(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      rationale: json['rationale']?.toString() ?? '',
      contentType: AiContentType.fromDb(json['content_type']),
      status: AiContentStatus.fromDb(json['status']),
      iconEmoji: json['icon_emoji']?.toString() ?? '✨',
      ctaAction: json['cta_action']?.toString() ?? '',
      ctaLabel: json['cta_label']?.toString() ?? '',
      country: json['country']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by']?.toString(),
      reviewedBy: json['reviewed_by']?.toString(),
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.tryParse(json['reviewed_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  /// Convert to JSON for upsert operations.
  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'content_type': contentType.dbValue,
      'title': title,
      'subtitle': subtitle,
      'body': body,
      'rationale': rationale,
      'icon_emoji': iconEmoji,
      'cta_action': ctaAction,
      'cta_label': ctaLabel,
      'country': country,
      'sort_order': sortOrder,
      'status': status.dbValue,
      'is_active': isActive,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NexusRecommendation && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
