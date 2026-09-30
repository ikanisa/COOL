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
    );
  }
}

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
  });

  final String id;
  final String collectionId;
  final int amountRwf;
  final String currency;
  final String supporterLabel;
  final DateTime createdAt;
  final String? transactionId;
  final bool isCurrentUserContribution;

  int get amountMinor => amountRwf;

  factory Contribution.fromJson(Map<String, dynamic> json) {
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
