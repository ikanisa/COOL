import 'package:equatable/equatable.dart';
import 'rs_models.dart';

const Object _unset = Object();

class RsInitiative extends Equatable {
  const RsInitiative({
    required this.id,
    required this.partnerId,
    required this.title,
    required this.description,
    required this.category,
    required this.targetAmount,
    required this.raisedAmount,
    required this.supporterCount,
    required this.isActive,
    required this.endsAt,
  });

  final String id;
  final String partnerId;
  final String title;
  final String description;
  final InitiativeCategory category;
  final int targetAmount;
  final int raisedAmount;
  final int supporterCount;
  final bool isActive;
  final DateTime? endsAt;

  double get progressPercent {
    if (targetAmount <= 0) {
      return 0;
    }

    return ((raisedAmount / targetAmount) * 100).clamp(0, 100).toDouble();
  }

  String get progressDisplay {
    final percent = progressPercent;
    final whole = percent.truncateToDouble() == percent;
    return '${percent.toStringAsFixed(whole ? 0 : 1)}% funded';
  }

  double get progress => progressPercent / 100;

  factory RsInitiative.fromJson(RsJsonMap json) {
    return RsInitiative(
      id: json['id']?.toString() ?? '',
      partnerId: (json['partner_id'] ?? json['partnerId'])?.toString() ?? '',
      title: (json['title'] ?? 'Club Initiative').toString(),
      description: json['description']?.toString() ?? '',
      category: InitiativeCategoryX.fromValue(
        (json['category'] ?? json['initiative_category'])?.toString(),
      ),
      targetAmount:
          int.tryParse(
            (json['target_amount'] ?? json['targetAmount'] ?? '0')
                .toString()
                .replaceAll(',', ''),
          ) ??
          0,
      raisedAmount:
          int.tryParse(
            (json['raised_amount'] ?? json['raisedAmount'] ?? '0')
                .toString()
                .replaceAll(',', ''),
          ) ??
          0,
      supporterCount:
          int.tryParse(
            (json['supporter_count'] ?? json['supporterCount'] ?? '0')
                .toString()
                .replaceAll(',', ''),
          ) ??
          0,
      isActive: (json['is_active'] ?? json['isActive'] ?? true) as bool,
      endsAt: json['ends_at'] != null
          ? DateTime.tryParse(json['ends_at'].toString())
          : null,
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'partner_id': partnerId,
      'title': title,
      'description': description,
      'category': category.value,
      'target_amount': targetAmount,
      'raised_amount': raisedAmount,
      'supporter_count': supporterCount,
      'is_active': isActive,
      'ends_at': endsAt?.toIso8601String(),
    };
  }

  RsInitiative copyWith({
    String? id,
    String? partnerId,
    String? title,
    String? description,
    InitiativeCategory? category,
    int? targetAmount,
    int? raisedAmount,
    int? supporterCount,
    bool? isActive,
    Object? endsAt = _unset,
  }) {
    return RsInitiative(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      targetAmount: targetAmount ?? this.targetAmount,
      raisedAmount: raisedAmount ?? this.raisedAmount,
      supporterCount: supporterCount ?? this.supporterCount,
      isActive: isActive ?? this.isActive,
      endsAt: identical(endsAt, _unset) ? this.endsAt : endsAt as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    partnerId,
    title,
    description,
    category,
    targetAmount,
    raisedAmount,
    supporterCount,
    isActive,
    endsAt,
  ];
}

class RsInitiativeContribution extends Equatable {
  const RsInitiativeContribution({
    required this.id,
    required this.initiativeId,
    required this.userId,
    required this.amount,
    required this.momoReference,
    required this.status,
    required this.createdAt,
    this.supporterName,
  });

  final String id;
  final String initiativeId;
  final String userId;
  final int amount;
  final String momoReference;
  final String status;
  final DateTime createdAt;
  final String? supporterName;

  factory RsInitiativeContribution.fromJson(RsJsonMap json) {
    return RsInitiativeContribution(
      id: json['id']?.toString() ?? '',
      initiativeId:
          (json['initiative_id'] ?? json['initiativeId'])?.toString() ?? '',
      userId: (json['user_id'] ?? json['userId'])?.toString() ?? '',
      amount:
          int.tryParse(
            (json['amount'] ?? '0').toString().replaceAll(',', ''),
          ) ??
          0,
      momoReference: (json['momo_reference'] ?? json['momoReference'] ?? '')
          .toString(),
      status: (json['status'] ?? 'pending').toString(),
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      supporterName:
          (json['supporter_name'] ?? json['supporterName'] ?? json['name'])
              ?.toString(),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'initiative_id': initiativeId,
      'user_id': userId,
      'amount': amount,
      'momo_reference': momoReference,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (supporterName != null) 'supporter_name': supporterName,
    };
  }

  RsInitiativeContribution copyWith({
    String? id,
    String? initiativeId,
    String? userId,
    int? amount,
    String? momoReference,
    String? status,
    DateTime? createdAt,
    Object? supporterName = _unset,
  }) {
    return RsInitiativeContribution(
      id: id ?? this.id,
      initiativeId: initiativeId ?? this.initiativeId,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      momoReference: momoReference ?? this.momoReference,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      supporterName: identical(supporterName, _unset)
          ? this.supporterName
          : supporterName as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    initiativeId,
    userId,
    amount,
    momoReference,
    status,
    createdAt,
    supporterName,
  ];
}
