import 'package:flutter/foundation.dart' show immutable;

import '../../core/data/exact_json_values.dart';

import 'collect_collection_catalog.dart';
import 'collect_member_profile.dart';
import 'collect_model_json_helpers.dart';

part 'collect_summary_json.dart';

const _unspecifiedReceiverRouteLabel = Object();

@immutable
class CollectCollection {
  const CollectCollection({
    required this.id,
    required this.slug,
    required this.creatorUserId,
    required this.title,
    required this.description,
    this.collectionType = CollectionType.ikimina,
    this.categorySubtype,
    this.purposeLabel,
    this.receiverMomoNumber,
    String? receiverDisplayLabel,
    Object? receiverRouteLabel = _unspecifiedReceiverRouteLabel,
    this.receiverNetwork = 'unknown',
    this._primaryPaymentRail,
    this.settlementCurrency = 'RWF',
    this.imageUrl,
    this.accentColorHex,
    this.isPublic = false,
    this.isPlatformSponsored = false,
    this.isCurrentUserMember = false,
    this.isRecurring = true,
    this.recurringCadence = 'monthly',
    String? visibilityStatus,
    this.suggestedAmountRwf,
    this.moderationStatus = 'not_requested',
    required this.createdAt,
  }) : receiverDisplayLabel = receiverDisplayLabel ?? 'Primary MoMo receiver',
       receiverRouteLabel =
           identical(receiverRouteLabel, _unspecifiedReceiverRouteLabel)
           ? receiverDisplayLabel
           : receiverRouteLabel as String?,
       visibilityStatus =
           visibilityStatus ?? (isPublic ? 'public_approved' : 'private');

  final String id;
  final String slug;
  final String creatorUserId;
  final String title;
  final String description;
  final CollectionType collectionType;
  final String? categorySubtype;
  final String? purposeLabel;
  final String? receiverMomoNumber;
  final String receiverDisplayLabel;
  // Null means the source omitted the field; an empty string represents an
  // explicitly observed null or empty server label. The visible fallback is
  // never used as evidence that the underlying route label matched.
  final String? receiverRouteLabel;
  final String receiverNetwork;
  final String? _primaryPaymentRail;
  final String settlementCurrency;
  final String? imageUrl;
  final String? accentColorHex;
  final bool isPublic;
  final bool isPlatformSponsored;
  final bool isCurrentUserMember;
  final bool isRecurring;
  final String recurringCadence;
  final String visibilityStatus;
  final int? suggestedAmountRwf;
  final String moderationStatus;
  final DateTime createdAt;

  bool get isArchived => moderationStatus.trim().toLowerCase() == 'archived';

  String get primaryPaymentRail =>
      _primaryPaymentRail ??
      (receiverMomoNumber?.trim().isNotEmpty == true &&
              const {'mtn_momo', 'airtel_money'}.contains(receiverNetwork)
          ? 'rwanda_momo'
          : 'unavailable');

  bool get supportsRwandaMomo => primaryPaymentRail == 'rwanda_momo';

  String contributionRailFor(CollectProfile? profile) =>
      supportsRwandaMomo && (profile == null || profile.isRwanda)
      ? 'rwanda_momo'
      : 'unavailable';

  factory CollectCollection.fromJson(Map<String, dynamic> json) {
    final receivers = json['collection_receivers'];
    Map<String, dynamic>? receiver;
    if (receivers is List && receivers.isNotEmpty) {
      receiver = Map<String, dynamic>.from(receivers.first as Map);
    }
    final rawReceiverLabel =
        (receiver?['label'] as String?) ??
        (json['receiver_display_label'] as String?);
    final receiverLabelObserved =
        rawReceiverLabel != null ||
        (receiver?.containsKey('label') ?? false) ||
        json.containsKey('receiver_display_label');
    final receiverMomoNumber =
        (receiver?['momo_number'] as String?) ??
        (json['receiver_momo_number'] as String?);
    final receiverNetwork =
        (receiver?['network'] as String?) ??
        (json['receiver_network'] as String?) ??
        'unknown';
    final primaryPaymentRail =
        (json['payment_rail'] as String?) ??
        ((receiverMomoNumber?.trim().isNotEmpty == true &&
                const {'mtn_momo', 'airtel_money'}.contains(receiverNetwork))
            ? 'rwanda_momo'
            : 'unavailable');
    return CollectCollection(
      id: exactJsonIdentifier(json['id'], field: 'collection.id'),
      slug: exactJsonIdentifier(json['slug'], field: 'collection.slug'),
      creatorUserId: json['creator_user_id'] == null
          ? ''
          : exactJsonIdentifier(
              json['creator_user_id'],
              field: 'collection.creator_user_id',
            ),
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      collectionType: CollectionType.fromJson(
        json['collection_type'] ?? json['category'],
      ),
      categorySubtype: json['category_subtype'] as String?,
      purposeLabel: json['purpose_label'] as String?,
      receiverMomoNumber: receiverMomoNumber,
      receiverDisplayLabel: rawReceiverLabel,
      receiverRouteLabel: receiverLabelObserved ? rawReceiverLabel ?? '' : null,
      receiverNetwork: receiverNetwork,
      primaryPaymentRail: primaryPaymentRail,
      settlementCurrency:
          (json['settlement_currency'] as String?) ??
          (json['currency'] as String?) ??
          (primaryPaymentRail == 'rwanda_momo' ? 'RWF' : 'XXX'),
      imageUrl:
          (json['image_url'] as String?) ??
          (json['cover_image_url'] as String?) ??
          (json['photo_url'] as String?),
      accentColorHex:
          (json['accent_color_hex'] as String?) ??
          (json['card_color_hex'] as String?) ??
          (json['color_hex'] as String?),
      isPublic: _collectionIsPublic(json),
      isPlatformSponsored: (json['is_platform_sponsored'] as bool?) ?? false,
      isCurrentUserMember: (json['is_member'] as bool?) ?? false,
      isRecurring: (json['is_recurring'] as bool?) ?? true,
      recurringCadence:
          (json['recurring_cadence'] as String?) ??
          (json['contribution_frequency'] as String?) ??
          (json['frequency'] as String?) ??
          'monthly',
      visibilityStatus:
          (json['visibility_status'] as String?) ??
          ((json['is_public'] as bool?) == true
              ? 'public_approved'
              : 'private'),
      suggestedAmountRwf: json['suggested_amount_rwf'] == null
          ? null
          : exactJsonInteger(
              json['suggested_amount_rwf'],
              field: 'collection.suggested_amount_rwf',
              minimum: 1,
            ),
      moderationStatus:
          (json['moderation_status'] as String?) ?? 'not_requested',
      createdAt: modelJsonTimestamp(json['created_at']),
    );
  }

  CollectCollection copyWith({
    String? creatorUserId,
    String? title,
    String? description,
    CollectionType? collectionType,
    String? categorySubtype,
    String? purposeLabel,
    String? receiverMomoNumber,
    String? receiverDisplayLabel,
    Object? receiverRouteLabel = _unspecifiedReceiverRouteLabel,
    String? receiverNetwork,
    String? primaryPaymentRail,
    String? settlementCurrency,
    String? imageUrl,
    bool clearImageUrl = false,
    String? accentColorHex,
    bool? isPublic,
    bool? isPlatformSponsored,
    bool? isCurrentUserMember,
    bool? isRecurring,
    String? recurringCadence,
    String? visibilityStatus,
    int? suggestedAmountRwf,
    String? moderationStatus,
  }) {
    return CollectCollection(
      id: id,
      slug: slug,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      title: title ?? this.title,
      description: description ?? this.description,
      collectionType: collectionType ?? this.collectionType,
      categorySubtype: categorySubtype ?? this.categorySubtype,
      purposeLabel: purposeLabel ?? this.purposeLabel,
      receiverMomoNumber: receiverMomoNumber ?? this.receiverMomoNumber,
      receiverDisplayLabel: receiverDisplayLabel ?? this.receiverDisplayLabel,
      receiverRouteLabel:
          !identical(receiverRouteLabel, _unspecifiedReceiverRouteLabel)
          ? receiverRouteLabel
          : receiverDisplayLabel == null ||
                receiverDisplayLabel == this.receiverDisplayLabel
          ? this.receiverRouteLabel
          : null,
      receiverNetwork: receiverNetwork ?? this.receiverNetwork,
      primaryPaymentRail: primaryPaymentRail ?? this.primaryPaymentRail,
      settlementCurrency: settlementCurrency ?? this.settlementCurrency,
      imageUrl: clearImageUrl ? null : imageUrl ?? this.imageUrl,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      isPublic: isPublic ?? this.isPublic,
      isPlatformSponsored: isPlatformSponsored ?? this.isPlatformSponsored,
      isCurrentUserMember: isCurrentUserMember ?? this.isCurrentUserMember,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringCadence: recurringCadence ?? this.recurringCadence,
      visibilityStatus: visibilityStatus ?? this.visibilityStatus,
      suggestedAmountRwf: suggestedAmountRwf ?? this.suggestedAmountRwf,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      createdAt: createdAt,
    );
  }
}

@immutable
class CollectionSummary {
  const CollectionSummary({
    required this.amountRaisedRwf,
    required this.supporterCount,
    this.currentUserBalanceRwf = 0,
    this.currency = 'RWF',
  }) : _totals = null,
       _ownBalances = null;

  CollectionSummary.multiCurrency({
    required Map<String, int> totals,
    required Map<String, int> ownBalances,
    required this.supporterCount,
    String emptyCurrency = 'RWF',
  }) : _totals = Map.unmodifiable(totals.isEmpty ? {emptyCurrency: 0} : totals),
       _ownBalances = Map.unmodifiable({
         for (final currency in totals.isEmpty ? [emptyCurrency] : totals.keys)
           currency: ownBalances[currency] ?? 0,
       }),
       amountRaisedRwf = totals['RWF'] ?? 0,
       currentUserBalanceRwf = ownBalances['RWF'] ?? 0,
       currency = totals.length == 1 ? totals.keys.single : emptyCurrency;

  final int amountRaisedRwf;
  final int? supporterCount;
  final int currentUserBalanceRwf;
  final String currency;
  final Map<String, int>? _totals;
  final Map<String, int>? _ownBalances;

  Map<String, int> get totalsByCurrency =>
      _totals ?? {currency: amountRaisedRwf};
  Map<String, int> get ownBalancesByCurrency =>
      _ownBalances ?? {currency: currentUserBalanceRwf};
  String get supporterCountLabel => supporterCount?.toString() ?? '—';
  String get supporterCountSemantics => supporterCount == null
      ? 'Contributor count unavailable'
      : '$supporterCount ${supporterCount == 1 ? 'contributor' : 'contributors'}';

  int get amountRaisedMinor => _singleCurrencyAmount(totalsByCurrency);
  int get currentUserBalanceMinor =>
      _singleCurrencyAmount(ownBalancesByCurrency);

  int _singleCurrencyAmount(Map<String, int> amounts) {
    if (amounts.length > 1) {
      throw StateError('Choose a settlement currency before reading an amount');
    }
    return amounts.values.firstOrNull ?? 0;
  }

  factory CollectionSummary.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('balances')) {
      final balances = json['balances'];
      final count = json['supporter_count'];
      if (balances is! List) {
        throw const FormatException('Invalid group balances');
      }
      final totals = <String, int>{};
      final own = <String, int>{};
      for (final row in balances) {
        if (row is! Map ||
            row['currency'] != 'RWF' ||
            totals.containsKey(row['currency'])) {
          throw const FormatException('Invalid settlement balance');
        }
        final currency = row['currency'] as String;
        totals[currency] = _summaryInteger(
          row['amount_raised_minor'],
          'amount_raised_minor',
        );
        own[currency] = _summaryInteger(
          row['current_user_balance_minor'],
          'current_user_balance_minor',
        );
      }
      return CollectionSummary.multiCurrency(
        totals: totals,
        ownBalances: own,
        supporterCount: _summaryContributorCount(count),
        emptyCurrency: _summaryCurrency(json['currency']),
      );
    }
    return CollectionSummary(
      amountRaisedRwf: _summaryAliasedInteger(
        json,
        'amount_raised_minor',
        'amount_raised_rwf',
      ),
      supporterCount: _summaryContributorCount(json['supporter_count']),
      currentUserBalanceRwf: _summaryAliasedInteger(
        json,
        'current_user_balance_minor',
        'current_user_balance_rwf',
      ),
      currency: _summaryCurrency(json['currency']),
    );
  }
}

@immutable
class CollectMember {
  const CollectMember({
    required this.publicId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.amountScope = 'hidden',
    this.contributionTotals = const {},
  });

  final String publicId;
  final String role;
  final String status;
  final DateTime joinedAt;
  final String amountScope;
  final Map<String, int> contributionTotals;

  String? get contributionCaption => switch (amountScope) {
    'own' => 'Your contributions',
    'shared' => 'Shared contributions',
    _ => null,
  };

  factory CollectMember.fromJson(Map<String, dynamic> json) {
    final publicId = json['public_id'];
    final role = json['role'];
    final status = json['status'];
    final joinedAt = json['joined_at'];
    final scope = json['amount_scope'];
    final amounts = json['contributions'];
    if (publicId is! String ||
        !RegExp(r'^[0-9]{6}$').hasMatch(publicId) ||
        !const {
          'owner',
          'admin',
          'receiver',
          'member',
          'contributor',
          'viewer',
        }.contains(role) ||
        !const {'active', 'invited', 'removed', 'left'}.contains(status) ||
        !const {'own', 'shared', 'hidden'}.contains(scope) ||
        amounts is! List) {
      throw const FormatException('Invalid member roster');
    }
    final totals = <String, int>{};
    for (final row in amounts) {
      if (row is! Map ||
          row['currency'] != 'RWF' ||
          totals.containsKey(row['currency'])) {
        throw const FormatException('Invalid member contributions');
      }
      totals[row['currency'] as String] = exactJsonInteger(
        row['amount_minor'],
        field: 'member.amount_minor',
        minimum: 1,
      );
    }
    if ((scope == 'hidden' && totals.isNotEmpty) ||
        (scope == 'shared' && totals.isEmpty)) {
      throw const FormatException('Invalid member contribution visibility');
    }
    return CollectMember(
      publicId: publicId,
      role: role as String,
      status: status as String,
      joinedAt: exactJsonTimestamp(joinedAt, field: 'member.joined_at'),
      amountScope: scope as String,
      contributionTotals: Map.unmodifiable(totals),
    );
  }

  String get safeLabel => 'Collect ID $publicId';
}

@immutable
class OwnerGroupHealth {
  const OwnerGroupHealth({
    required this.collectionId,
    required this.smsAccessEnabled,
    required this.receiverConfigured,
    required this.pendingPaymentIntents,
    required this.needsReviewEvents,
    required this.lastSyncedAt,
  });

  final String collectionId;
  final bool smsAccessEnabled;
  final bool receiverConfigured;
  final int pendingPaymentIntents;
  final int needsReviewEvents;
  final DateTime? lastSyncedAt;

  factory OwnerGroupHealth.fromJson(Map<String, dynamic> json) {
    return OwnerGroupHealth(
      collectionId: exactJsonIdentifier(
        json['collection_id'],
        field: 'health.collection_id',
      ),
      smsAccessEnabled: (json['sms_access_enabled'] as bool?) ?? false,
      receiverConfigured: (json['receiver_configured'] as bool?) ?? false,
      pendingPaymentIntents: exactJsonInteger(
        json['pending_payment_intents'],
        field: 'health.pending_payment_intents',
        minimum: 0,
      ),
      needsReviewEvents: exactJsonInteger(
        json['needs_review_events'],
        field: 'health.needs_review_events',
        minimum: 0,
      ),
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : modelJsonTimestamp(json['last_synced_at']),
    );
  }

  bool get ready => smsAccessEnabled && receiverConfigured;
}

bool _collectionIsPublic(Map<String, dynamic> json) {
  final explicit =
      json['is_public'] ??
      json['public'] ??
      json['is_publicly_visible'] ??
      json['listed_publicly'];
  if (explicit is bool) return explicit;
  if (json['is_platform_sponsored'] == true) return true;
  final visibility = (json['public_status'] ?? json['visibility'])
      ?.toString()
      .toLowerCase();
  return visibility == 'public' || visibility == 'public_approved';
}
