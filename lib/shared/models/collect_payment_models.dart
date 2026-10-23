part of 'collect_models.dart';

@immutable
class PaymentIntentDraft {
  const PaymentIntentDraft({
    required this.collectionId,
    required this.amountRwf,
  });

  final String collectionId;
  final int amountRwf;

  int get amountMinor => amountRwf;
}

@immutable
class PaymentIntentModel {
  const PaymentIntentModel({
    required this.id,
    required this.collectionId,
    int? expectedAmountMinor,
    int? expectedAmountRwf,
    this.rail = 'rwanda_momo',
    this.receiverMomoNumber = '',
    this.receiverMomoNumberHash = '',
    this.receiverMomoLabel = '',
    this.momoNetwork = 'mtn_momo',
    this.senderPhoneHash = '',
    this.currency = 'RWF',
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.confirmationStatus = 'awaiting_confirmation',
    this.paymentId,
    this.contributionEntryId,
    this.creditedAmountRwf,
    this.postedAt,
    this.providerTransactionAt,
    this.providerTransactionReference,
    this.balanceAfterContributionRwf,
    this.groupBalanceAfterContributionRwf,
  }) : expectedAmountMinor = expectedAmountMinor ?? expectedAmountRwf ?? 0;

  final String id;
  final String collectionId;
  final int expectedAmountMinor;
  final String rail;
  final String receiverMomoNumber;
  final String receiverMomoNumberHash;
  final String receiverMomoLabel;
  final String momoNetwork;
  final String senderPhoneHash;
  final String currency;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String confirmationStatus;
  final String? paymentId, contributionEntryId, providerTransactionReference;
  final int? creditedAmountRwf;
  final DateTime? postedAt, providerTransactionAt;
  final int? balanceAfterContributionRwf, groupBalanceAfterContributionRwf;

  bool get hasCommittedContribution =>
      const {'credited', 'reversed'}.contains(confirmationStatus) &&
      paymentId != null &&
      contributionEntryId != null &&
      creditedAmountRwf != null &&
      creditedAmountRwf! > 0 &&
      postedAt != null;

  int get expectedAmountRwf => expectedAmountMinor;
  bool get isRwandaMomo => rail == 'rwanda_momo' && currency == 'RWF';
  String get receiverLabel => receiverMomoLabel;
  String get network => momoNetwork;
  bool get isAwaitingTransfer =>
      isRwandaMomo &&
      status == 'pending' &&
      DateTime.now().toUtc().isBefore(expiresAt.toUtc());

  factory PaymentIntentModel.fromJson(Map<String, dynamic> json) {
    final rail = json['rail'] ?? 'rwanda_momo';
    final currency = json['currency'] ?? 'RWF';
    if (rail != 'rwanda_momo' || currency != 'RWF') {
      throw const FormatException('Only Rwanda MoMo intents are supported');
    }
    if (json['destination'] != null ||
        json['destination_snapshot'] != null ||
        json['transfer_reference'] != null) {
      throw const FormatException('Unsupported payment intent route metadata');
    }
    final createdAt = _paymentTimestamp(json['created_at'], 'created_at');
    final expiresAt = _paymentTimestamp(json['expires_at'], 'expires_at');
    // Expired historical intents are valid data; inverted lifetimes are not.
    if (!expiresAt.isAfter(createdAt)) {
      throw const FormatException('Invalid payment intent lifetime');
    }
    final confirmationStatus =
        json['confirmation_status'] ?? 'awaiting_confirmation';
    if (!const {
      'awaiting_confirmation',
      'payment_received',
      'credited',
      'needs_review',
      'reversed',
    }.contains(confirmationStatus)) {
      throw const FormatException('Invalid payment confirmation state');
    }
    String? optionalId(String key) =>
        json[key] == null ? null : _paymentIdentifier(json[key], key);
    final paymentId = optionalId('payment_id');
    final contributionEntryId = optionalId('contribution_entry_id');
    final creditedAmount = json['credited_amount_rwf'] == null
        ? null
        : exactJsonInteger(
            json['credited_amount_rwf'],
            field: 'intent.credited_amount_rwf',
            minimum: 1,
          );
    final postedAt = json['posted_at'] == null
        ? null
        : _paymentTimestamp(json['posted_at'], 'posted_at');
    if ((const {'credited', 'reversed'}.contains(confirmationStatus) &&
            (paymentId == null ||
                contributionEntryId == null ||
                creditedAmount == null ||
                postedAt == null)) ||
        (confirmationStatus == 'payment_received' && paymentId == null) ||
        (confirmationStatus == 'awaiting_confirmation' &&
            (paymentId != null ||
                contributionEntryId != null ||
                creditedAmount != null ||
                postedAt != null))) {
      throw const FormatException('Incomplete payment confirmation evidence');
    }
    return PaymentIntentModel(
      id: _paymentIdentifier(json['id'], 'id'),
      collectionId: _paymentIdentifier(json['collection_id'], 'collection_id'),
      expectedAmountMinor: _paymentAmount(
        json,
        'amount_minor',
        'expected_amount_rwf',
      ),
      rail: 'rwanda_momo',
      receiverMomoNumber: _paymentOptionalText(
        json['receiver_momo_number'],
        'receiver_momo_number',
      ).trim(),
      receiverMomoNumberHash: _paymentOptionalText(
        json['receiver_momo_number_hash'],
        'receiver_momo_number_hash',
      ).trim(),
      receiverMomoLabel: _paymentOptionalText(
        json['receiver_label'],
        'receiver_label',
      ).trim(),
      momoNetwork: _paymentOptionalText(
        json['network'],
        'network',
        fallback: 'mtn_momo',
      ).trim(),
      senderPhoneHash: _paymentOptionalText(
        json['sender_phone_hash'],
        'sender_phone_hash',
      ).trim(),
      currency: 'RWF',
      // Never manufacture an actionable pending state from an absent status.
      status: _paymentIdentifier(json['status'], 'status'),
      createdAt: createdAt,
      expiresAt: expiresAt,
      confirmationStatus: confirmationStatus as String,
      paymentId: paymentId,
      contributionEntryId: contributionEntryId,
      creditedAmountRwf: creditedAmount,
      postedAt: postedAt,
      providerTransactionAt: json['provider_transaction_at'] == null
          ? null
          : _paymentTimestamp(
              json['provider_transaction_at'],
              'provider_transaction_at',
            ),
      providerTransactionReference: optionalId(
        'provider_transaction_reference',
      ),
      balanceAfterContributionRwf:
          json['balance_after_contribution_rwf'] == null
          ? null
          : exactJsonInteger(
              json['balance_after_contribution_rwf'],
              field: 'intent.balance_after_contribution_rwf',
              minimum: 0,
            ),
      groupBalanceAfterContributionRwf:
          json['group_balance_after_contribution_rwf'] == null
          ? null
          : exactJsonInteger(
              json['group_balance_after_contribution_rwf'],
              field: 'intent.group_balance_after_contribution_rwf',
              minimum: 0,
            ),
    );
  }
}

enum ContributionEntryKind { contribution, reversal, correction }

@immutable
class Contribution {
  const Contribution({
    required this.id,
    required this.collectionId,
    required this.amountRwf,
    this.currency = 'RWF',
    required this.supporterLabel,
    required this.createdAt,
    this.transactionId,
    this.isCurrentUserContribution = false,
    this.historyContractVersion = 1,
    this.entryKind = ContributionEntryKind.contribution,
    this.paymentId,
    this.groupTitle,
    this.reversesEntryId,
    this.evidenceId,
    this.paymentStatus,
  });

  final String id;
  final String collectionId;
  final int amountRwf;
  final String currency;
  final String supporterLabel;
  final DateTime createdAt;
  final String? transactionId;
  final bool isCurrentUserContribution;
  final int historyContractVersion;
  final ContributionEntryKind entryKind;
  final String? paymentId;
  final String? groupTitle;
  final String? reversesEntryId;
  final String? evidenceId;
  final String? paymentStatus;

  bool get isHistoryEvent => historyContractVersion == 2;
  bool get isCompensation => entryKind != ContributionEntryKind.contribution;

  int get amountMinor => amountRwf;

  factory Contribution.fromJson(Map<String, dynamic> json) {
    final version = json['contract_version'];
    if (version is int && version == 2) {
      return Contribution.historyEventFromJson(json);
    }
    if (version != null && (version is! int || version != 1)) {
      throw const FormatException('Unsupported contribution contract');
    }
    if ((json['currency'] ?? 'RWF') != 'RWF' ||
        (json['rail'] ?? 'rwanda_momo') != 'rwanda_momo') {
      throw const FormatException('Only RWF MoMo contributions are supported');
    }
    final ownership = json['is_current_user_contribution'];
    if (ownership != null && ownership is! bool) {
      throw const FormatException('Invalid payment field: ownership');
    }
    return Contribution(
      // payment_id and id can belong to different schemas; retain precedence.
      id: _paymentIdentifier(json['payment_id'] ?? json['id'], 'payment_id'),
      collectionId: _paymentIdentifier(json['collection_id'], 'collection_id'),
      amountRwf: _paymentAmount(json, 'amount_minor', 'amount_rwf'),
      currency: 'RWF',
      supporterLabel: _paymentOptionalText(
        json['supporter_label'],
        'supporter_label',
        fallback: json['contributor_public_id'] == null
            ? 'Collect member'
            : 'Collect ID ${json['contributor_public_id']}',
      ),
      // Posting and creation are different events. Preserve posting precedence;
      // do not require their values to agree or replace a missing date with now.
      createdAt: _paymentTimestamp(
        json['posted_at'] ?? json['created_at'],
        'posted_at',
      ),
      transactionId: json['transaction_id'] == null
          ? null
          : _paymentOptionalText(json['transaction_id'], 'transaction_id'),
      isCurrentUserContribution: ownership == true,
    );
  }

  /// Versioned signed ledger event. A payment can have several distinct entries.
  factory Contribution.historyEventFromJson(Map<String, dynamic> json) {
    const requiredFields = {
      'entry_id',
      'payment_id',
      'collection_id',
      'group_title',
      'amount_minor',
      'currency',
      'rail',
      'posted_at',
      'supporter_label',
      'is_current_user_contribution',
      'entry_kind',
      'reverses_entry_id',
      'evidence_id',
      'payment_status',
      'provider_confirmation',
      'settlement_status',
    };
    if (!json.keys.toSet().containsAll(requiredFields) ||
        json.keys.any(
          (key) => !requiredFields.contains(key) && key != 'contract_version',
        ) ||
        (json.containsKey('contract_version') &&
            (json['contract_version'] is! int ||
                json['contract_version'] != 2))) {
      throw const FormatException(
        'Incomplete or unsupported signed history event',
      );
    }
    final kind = switch (json['entry_kind']) {
      'contribution' => ContributionEntryKind.contribution,
      'reversal' => ContributionEntryKind.reversal,
      'correction' => ContributionEntryKind.correction,
      _ => throw const FormatException('Invalid history entry kind'),
    };
    final amount = exactJsonInteger(
      json['amount_minor'],
      field: 'history.amount',
    );
    final reversal = json['reverses_entry_id'];
    final label = json['supporter_label'];
    final title = json['group_title'];
    final status = json['payment_status'];
    if ((json['contract_version'] != null && json['contract_version'] != 2) ||
        json['currency'] != 'RWF' ||
        json['rail'] != 'rwanda_momo' ||
        json['provider_confirmation'] != false ||
        json['settlement_status'] != 'not_asserted' ||
        json['is_current_user_contribution'] is! bool ||
        label is! String ||
        !(label == 'Member' || RegExp(r'^[0-9]{6}$').hasMatch(label)) ||
        title is! String ||
        title.trim().isEmpty ||
        title.length > 160 ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(title) ||
        status is! String ||
        !const {
          'recorded',
          'reconciled',
          'confirmed',
          'corrected',
          'reversed',
          'ambiguous',
        }.contains(status) ||
        amount == 0 ||
        (kind == ContributionEntryKind.contribution
            ? amount < 0 || reversal != null
            : amount > 0 || reversal == null)) {
      throw const FormatException('Invalid signed history event');
    }
    final entryId = _historyUuid(json['entry_id'], 'entry_id');
    if (reversal != null &&
        _historyUuid(reversal, 'reverses_entry_id') == entryId) {
      throw const FormatException('Invalid history lineage');
    }
    return Contribution(
      id: entryId,
      collectionId: _historyUuid(json['collection_id'], 'collection_id'),
      amountRwf: amount,
      supporterLabel: label,
      createdAt: _paymentTimestamp(json['posted_at'], 'posted_at'),
      isCurrentUserContribution: json['is_current_user_contribution'] as bool,
      historyContractVersion: 2,
      entryKind: kind,
      paymentId: _historyUuid(json['payment_id'], 'payment_id'),
      groupTitle: title,
      reversesEntryId: reversal as String?,
      evidenceId: _historyUuid(json['evidence_id'], 'evidence_id'),
      paymentStatus: status,
    );
  }

  /// Exact v2 cache representation; deliberately carries no provider reference.
  Map<String, dynamic> toHistoryEventJson() => {
    'contract_version': historyContractVersion,
    'entry_id': id,
    'payment_id': paymentId,
    'collection_id': collectionId,
    'group_title': groupTitle,
    'amount_minor': amountMinor,
    'currency': currency,
    'rail': 'rwanda_momo',
    'posted_at': createdAt.toUtc().toIso8601String(),
    'supporter_label': supporterLabel,
    'is_current_user_contribution': isCurrentUserContribution,
    'entry_kind': entryKind.name,
    'reverses_entry_id': reversesEntryId,
    'evidence_id': evidenceId,
    'payment_status': paymentStatus,
    'provider_confirmation': false,
    'settlement_status': 'not_asserted',
  };
}

@immutable
class ParsedPaymentEvent {
  const ParsedPaymentEvent({
    required this.id,
    required this.amountRwf,
    required this.transactionId,
    required this.senderLabel,
    required this.allocationStatus,
    required this.confidence,
    required this.createdAt,
    this.collectionId,
  });

  final String id;
  final int amountRwf;
  final String? transactionId;
  final String senderLabel;
  final String allocationStatus;
  final double confidence;
  final DateTime createdAt;
  final String? collectionId;

  factory ParsedPaymentEvent.fromJson(Map<String, dynamic> json) {
    if (json['currency'] != 'RWF') {
      throw const FormatException('Only RWF MoMo events are supported');
    }
    return ParsedPaymentEvent(
      id: _paymentIdentifier(json['id'], 'id'),
      // An incomplete receipt belongs in the controlled review queue; do not
      // display an unknown amount as a confirmed zero-RWF event.
      amountRwf: _paymentAmount(json, 'amount_rwf', 'amount_minor'),
      transactionId: json['transaction_id'] == null
          ? null
          : _paymentIdentifier(json['transaction_id'], 'transaction_id'),
      senderLabel: 'MoMo receipt',
      allocationStatus: _paymentIdentifier(
        json['allocation_status'],
        'allocation_status',
      ),
      confidence: _paymentConfidence(json['confidence']),
      createdAt: _paymentTimestamp(json['created_at'], 'created_at'),
      collectionId: json['collection_id'] == null
          ? null
          : _paymentIdentifier(json['collection_id'], 'collection_id'),
    );
  }
}
