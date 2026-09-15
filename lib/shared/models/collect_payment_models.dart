part of 'collect_models.dart';

@immutable
class PaymentIntentDraft {
  const PaymentIntentDraft({
    required this.collectionId,
    required this.amountRwf,
  });

  final String collectionId;
  final int amountRwf;

  /// Compatibility name retained for APIs that expose a generic minor amount.
  /// Rwanda values are whole RWF; diaspora values are currency minor units.
  int get amountMinor => amountRwf;
}

@immutable
class BankTransferDestination {
  const BankTransferDestination({
    required this.id,
    required this.beneficiaryName,
    required this.iban,
    required this.ibanMasked,
    required this.bic,
    required this.bankName,
    this.currency = 'EUR',
    this.transferScheme = 'sepa_credit_transfer',
    this.supportsInstant = true,
    this.status = 'draft',
    this.isPlaceholder = false,
    this.enabled = false,
  });

  static const placeholder = BankTransferDestination(
    id: 'placeholder',
    beneficiaryName: 'PLACEHOLDER — DO NOT TRANSFER',
    iban: 'XX00PLACEHOLDER0000000000',
    ibanMasked: 'XX00••••0000',
    bic: 'PLACEHOL',
    bankName: 'PLACEHOLDER BANK',
    isPlaceholder: true,
  );

  final String id;
  final String beneficiaryName;
  final String iban;
  final String ibanMasked;
  final String bic;
  final String bankName;
  final String currency;
  final String transferScheme;
  final bool supportsInstant;
  final String status;
  final bool isPlaceholder;
  final bool enabled;

  factory BankTransferDestination.fromJson(Map<String, dynamic> json) {
    return BankTransferDestination(
      id: (json['id'] as String?) ?? 'unavailable',
      beneficiaryName:
          (json['beneficiary_name'] as String?) ?? 'Beneficiary unavailable',
      iban: (json['iban'] as String?) ?? '',
      ibanMasked: (json['iban_masked'] as String?) ?? '',
      bic: (json['bic'] as String?) ?? '',
      bankName: (json['bank_name'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'EUR',
      transferScheme:
          (json['transfer_scheme'] as String?) ?? 'sepa_credit_transfer',
      supportsInstant: json['supports_instant'] != false,
      status: (json['status'] as String?) ?? 'draft',
      isPlaceholder: json['is_placeholder'] == true,
      enabled: json['enabled'] == true,
    );
  }
}

@immutable
class PaymentIntentModel {
  const PaymentIntentModel({
    required this.id,
    required this.collectionId,
    int? expectedAmountMinor,
    int? expectedAmountRwf,
    this.rail = 'diaspora_bank',
    this.receiverMomoNumber = '',
    this.receiverMomoNumberHash = '',
    this.receiverMomoLabel = '',
    this.momoNetwork = 'mtn_momo',
    this.senderPhoneHash = '',
    this.transferReference = '',
    this.destination = BankTransferDestination.placeholder,
    this.currency = 'EUR',
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
  final String transferReference;
  final BankTransferDestination destination;
  final String currency;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;

  int get expectedAmountRwf => expectedAmountMinor;
  bool get isRwandaMomo => rail == 'rwanda_momo';
  String get receiverLabel =>
      isRwandaMomo ? receiverMomoLabel : destination.beneficiaryName;
  String get network => isRwandaMomo ? momoNetwork : 'sepa';

  bool get isAwaitingTransfer =>
      (isRwandaMomo
              ? const {'pending'}
              : const {
                  'awaiting_transfer',
                  'handoff_opened',
                  'awaiting_bank_evidence',
                  'received_unreconciled',
                })
          .contains(status) &&
      DateTime.now().toUtc().isBefore(expiresAt.toUtc());

  factory PaymentIntentModel.fromJson(Map<String, dynamic> json) {
    final createdAt = _dateTime(json['created_at']);
    final expiresAt = _dateTime(json['expires_at']);
    final storedStatus = (json['status'] as String?) ?? 'awaiting_transfer';
    final destinationJson = json['destination'] ?? json['destination_snapshot'];
    return PaymentIntentModel(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      expectedAmountMinor:
          (json['amount_minor'] as num?)?.toInt() ??
          (json['expected_amount_rwf'] as num?)?.toInt() ??
          0,
      rail:
          json['rail']?.toString() ??
          (json['receiver_momo_number'] != null
              ? 'rwanda_momo'
              : 'diaspora_bank'),
      receiverMomoNumber:
          (json['receiver_momo_number'] as String?)?.trim() ?? '',
      receiverMomoNumberHash:
          (json['receiver_momo_number_hash'] as String?)?.trim() ?? '',
      receiverMomoLabel: (json['receiver_label'] as String?)?.trim() ?? '',
      momoNetwork: (json['network'] as String?)?.trim() ?? 'mtn_momo',
      senderPhoneHash: (json['sender_phone_hash'] as String?)?.trim() ?? '',
      transferReference: (json['transfer_reference'] as String?) ?? '',
      destination: destinationJson is Map
          ? BankTransferDestination.fromJson(
              Map<String, dynamic>.from(destinationJson),
            )
          : BankTransferDestination.placeholder,
      currency:
          (json['currency'] as String?) ??
          (json['receiver_momo_number'] != null ? 'RWF' : 'EUR'),
      status:
          const {
                'awaiting_transfer',
                'handoff_opened',
                'awaiting_bank_evidence',
              }.contains(storedStatus) &&
              !expiresAt.isAfter(DateTime.now().toUtc())
          ? 'expired'
          : storedStatus,
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
    return Contribution(
      id: (json['payment_id'] as String?) ?? json['id'] as String,
      collectionId: json['collection_id'] as String,
      amountRwf:
          (json['amount_minor'] as num?)?.toInt() ??
          (json['amount_rwf'] as num?)?.toInt() ??
          0,
      currency:
          (json['currency'] as String?) ??
          (json.containsKey('amount_minor') ? 'EUR' : 'RWF'),
      supporterLabel:
          (json['supporter_label'] as String?) ??
          (json['contributor_public_id'] == null
              ? 'Collect member'
              : 'Collect ID ${json['contributor_public_id']}'),
      createdAt: _dateTime(json['posted_at'] ?? json['created_at']),
      transactionId: json['transaction_id'] as String?,
      isCurrentUserContribution: json['is_current_user_contribution'] == true,
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
    return ParsedPaymentEvent(
      id: json['id'] as String,
      amountRwf: (json['amount_rwf'] as num?)?.toInt() ?? 0,
      transactionId: json['transaction_id'] as String?,
      senderLabel: 'Bank SMS',
      allocationStatus: (json['allocation_status'] as String?) ?? 'unallocated',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: _dateTime(json['created_at']),
      collectionId: json['collection_id'] as String?,
    );
  }
}
