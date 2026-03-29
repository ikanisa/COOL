class MomoStatementBundle {
  const MomoStatementBundle({
    this.walletEntries = const <MomoWalletEntry>[],
    this.savingsEntries = const <SavingsStatementEntry>[],
    this.walletTotalCount = 0,
    this.savingsTotalCount = 0,
  });

  final List<MomoWalletEntry> walletEntries;
  final List<SavingsStatementEntry> savingsEntries;
  final int walletTotalCount;
  final int savingsTotalCount;

  bool get isEmpty => walletEntries.isEmpty && savingsEntries.isEmpty;
  bool get hasMoreWallet => walletEntries.length < walletTotalCount;
  bool get hasMoreSavings => savingsEntries.length < savingsTotalCount;

  MomoStatementBundle copyWith({
    List<MomoWalletEntry>? walletEntries,
    List<SavingsStatementEntry>? savingsEntries,
    int? walletTotalCount,
    int? savingsTotalCount,
  }) {
    return MomoStatementBundle(
      walletEntries: walletEntries ?? this.walletEntries,
      savingsEntries: savingsEntries ?? this.savingsEntries,
      walletTotalCount: walletTotalCount ?? this.walletTotalCount,
      savingsTotalCount: savingsTotalCount ?? this.savingsTotalCount,
    );
  }
}

class MomoStatementPage<T> {
  const MomoStatementPage({this.entries = const [], this.totalCount = 0});

  final List<T> entries;
  final int totalCount;

  bool hasMore({required int offset}) => offset + entries.length < totalCount;
}

class SavingsStatementEntry {
  const SavingsStatementEntry({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.reference,
  });

  final String id;
  final String groupId;
  final String groupName;
  final int amount;
  final String status;
  final DateTime createdAt;
  final String? reference;

  bool get isConfirmed => status == 'confirmed' || status == 'completed';

  factory SavingsStatementEntry.fromJson(Map<String, dynamic> json) {
    return SavingsStatementEntry(
      id: json['id']?.toString() ?? '',
      groupId: json['group_id']?.toString() ?? '',
      groupName: json['group_name']?.toString() ?? 'Contribution circle',
      amount: _asInt(json['amount']),
      status: json['status']?.toString() ?? 'pending',
      createdAt:
          _parseDateTime(json['created_at']) ??
          _parseDateTime(json['tx_datetime']) ??
          DateTime.now(),
      reference:
          _nonEmpty(json['reference']) ?? _nonEmpty(json['external_reference']),
    );
  }
}

class GroupContribution {
  const GroupContribution({
    required this.userId,
    required this.amount,
    required this.status,
    this.id = '',
    this.groupId = '',
    this.contributorName,
    this.createdAt,
    this.reference,
  });

  final String id;
  final String groupId;
  final String userId;
  final String? contributorName;
  final int amount;
  final String status;
  final DateTime? createdAt;
  final String? reference;
}

class PayeePaymentLedgerEntry {
  const PayeePaymentLedgerEntry({
    required this.ledgerId,
    required this.payerUserId,
    required this.payerName,
    required this.amount,
    required this.currency,
    required this.occurredAt,
    required this.txCategory,
    required this.cashflowBucket,
    required this.label,
    required this.targetTable,
    this.payerPhone,
    this.reference,
    this.counterpartyName,
    this.targetRecordId,
  });

  final String ledgerId;
  final String payerUserId;
  final String payerName;
  final String? payerPhone;
  final int amount;
  final String currency;
  final DateTime occurredAt;
  final String? reference;
  final String txCategory;
  final String cashflowBucket;
  final String label;
  final String? counterpartyName;
  final String targetTable;
  final String? targetRecordId;

  factory PayeePaymentLedgerEntry.fromJson(Map<String, dynamic> json) {
    return PayeePaymentLedgerEntry(
      ledgerId: json['ledger_id']?.toString() ?? '',
      payerUserId: json['payer_user_id']?.toString() ?? '',
      payerName: json['payer_name']?.toString() ?? 'Member',
      payerPhone: _nonEmpty(json['payer_phone']),
      amount: _asInt(json['amount']),
      currency: json['currency']?.toString() ?? 'RWF',
      occurredAt:
          _parseDateTime(json['tx_datetime']) ??
          _parseDateTime(json['created_at']) ??
          DateTime.now(),
      reference: _nonEmpty(json['external_reference']),
      txCategory: json['tx_category']?.toString() ?? 'uncategorized',
      cashflowBucket: json['cashflow_bucket']?.toString() ?? 'unknown',
      label:
          json['statement_label']?.toString() ??
          _titleize(json['tx_category']?.toString() ?? 'payment'),
      counterpartyName: _nonEmpty(json['counterparty_name']),
      targetTable: json['target_table']?.toString() ?? '',
      targetRecordId: _nonEmpty(json['target_record_id']),
    );
  }
}

class MomoStatementQuery {
  const MomoStatementQuery({
    this.startDate,
    this.endDate,
    this.limit = 1000,
    this.offset = 0,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final int limit;
  final int offset;

  DateTime? get startAtUtc {
    final value = startDate;
    if (value == null) {
      return null;
    }
    return DateTime(value.year, value.month, value.day).toUtc();
  }

  DateTime? get endBeforeUtc {
    final value = endDate;
    if (value == null) {
      return null;
    }
    return DateTime(value.year, value.month, value.day + 1).toUtc();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MomoStatementQuery &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.limit == limit &&
        other.offset == offset;
  }

  @override
  int get hashCode => Object.hash(startDate, endDate, limit, offset);
}

class GroupPaymentLedgerQuery {
  const GroupPaymentLedgerQuery({
    required this.groupId,
    this.statementQuery = const MomoStatementQuery(),
    this.payerUserId,
  });

  final String groupId;
  final MomoStatementQuery statementQuery;
  final String? payerUserId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is GroupPaymentLedgerQuery &&
        other.groupId == groupId &&
        other.statementQuery == statementQuery &&
        other.payerUserId == payerUserId;
  }

  @override
  int get hashCode => Object.hash(groupId, statementQuery, payerUserId);
}

class PartnerPaymentLedgerQuery {
  const PartnerPaymentLedgerQuery({
    required this.partnerId,
    this.statementQuery = const MomoStatementQuery(),
    this.payerUserId,
  });

  final String partnerId;
  final MomoStatementQuery statementQuery;
  final String? payerUserId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PartnerPaymentLedgerQuery &&
        other.partnerId == partnerId &&
        other.statementQuery == statementQuery &&
        other.payerUserId == payerUserId;
  }

  @override
  int get hashCode => Object.hash(partnerId, statementQuery, payerUserId);
}

class MomoWalletEntry {
  const MomoWalletEntry({
    required this.id,
    required this.entryType,
    required this.ledgerStatus,
    required this.amount,
    required this.currency,
    required this.occurredAt,
    required this.txCategory,
    required this.cashflowBucket,
    required this.label,
    this.counterpartyName,
    this.reference,
    this.description,
    this.momoTxId,
    this.payerName,
    this.payerPhone,
  });

  final String id;
  final String entryType;
  final String ledgerStatus;
  final int amount;
  final String currency;
  final DateTime occurredAt;
  final String txCategory;
  final String cashflowBucket;
  final String label;
  final String? counterpartyName;
  final String? reference;
  final String? description;
  final String? momoTxId;
  final String? payerName;
  final String? payerPhone;

  bool get isCredit => entryType == 'credit';
  bool get isDebit => entryType == 'debit';

  factory MomoWalletEntry.fromJson(Map<String, dynamic> json) {
    // Check if we have the joined momo_sms_parsed data
    final parsedSms =
        json['momo_sms_parsed'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return MomoWalletEntry(
      id: json['id']?.toString() ?? '',
      entryType: json['entry_type']?.toString() ?? 'debit',
      ledgerStatus: json['ledger_status']?.toString() ?? 'draft',
      amount: _asInt(json['amount']),
      currency: json['currency']?.toString() ?? 'RWF',
      occurredAt:
          _parseDateTime(json['tx_datetime']) ??
          _parseDateTime(json['created_at']) ??
          DateTime.now(),
      txCategory: json['tx_category']?.toString() ?? 'uncategorized',
      cashflowBucket: json['cashflow_bucket']?.toString() ?? 'unknown',
      label:
          json['statement_label']?.toString() ??
          json['description']?.toString() ??
          _titleize(
            json['tx_category']?.toString() ?? json['entry_type']?.toString(),
          ),
      counterpartyName: _nonEmpty(json['counterparty_name']),
      reference: _nonEmpty(json['external_reference']),
      description: _nonEmpty(json['description']),
      momoTxId: _nonEmpty(parsedSms['momo_tx_id']),
      payerName: _nonEmpty(parsedSms['payer_name']),
      payerPhone:
          _nonEmpty(parsedSms['payer_number_full']) ??
          _nonEmpty(parsedSms['payer_number_last3']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

String? _nonEmpty(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _titleize(String? raw) {
  final normalized = raw?.trim() ?? '';
  if (normalized.isEmpty) {
    return 'Wallet transaction';
  }

  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
