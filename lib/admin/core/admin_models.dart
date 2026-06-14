class AdminIdentity {
  const AdminIdentity({
    required this.userId,
    required this.displayName,
    required this.roles,
    required this.permissions,
    this.phoneMasked,
  });

  final String userId;
  final String displayName;
  final String? phoneMasked;
  final List<String> roles;
  final List<String> permissions;

  factory AdminIdentity.fromJson(Map<String, dynamic> json) {
    return AdminIdentity(
      userId: json['user_id'] as String,
      displayName: (json['display_name'] as String?) ?? 'Collect admin',
      phoneMasked: json['phone_masked'] as String?,
      roles: _stringList(json['roles']),
      permissions: _stringList(json['permissions']),
    );
  }
}

class AdminMetric {
  const AdminMetric({
    required this.label,
    required this.value,
    required this.status,
  });

  final String label;
  final String value;
  final String status;

  factory AdminMetric.fromJson(Map<String, dynamic> json) {
    return AdminMetric(
      label: (json['label'] as String?) ?? 'Metric',
      value: '${json['value'] ?? 0}',
      status: (json['status'] as String?) ?? 'unknown',
    );
  }
}

class AdminTableRowData {
  const AdminTableRowData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.amount,
    this.createdAt,
    this.extra = const {},
  });

  final String id;
  final String title;
  final String subtitle;
  final String status;
  final String amount;
  final DateTime? createdAt;
  final Map<String, dynamic> extra;

  factory AdminTableRowData.fromJson(Map<String, dynamic> json) {
    return AdminTableRowData(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Record',
      subtitle: (json['subtitle'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'unknown',
      amount: (json['amount'] as String?) ?? '',
      createdAt: _dateTimeOrNull(json['created_at']),
      extra: {
        for (final entry in json.entries)
          if (!_tableFieldNames.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}

class AdminListResult {
  const AdminListResult({required this.rows, this.total});

  final List<AdminTableRowData> rows;
  final int? total;

  factory AdminListResult.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'];
    if (rows is! List) return const AdminListResult(rows: []);
    final parsedRows = [
      for (final row in rows)
        AdminTableRowData.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    return AdminListResult(rows: parsedRows, total: _intOrNull(json['total']));
  }
}

const _tableFieldNames = {
  'id',
  'title',
  'subtitle',
  'status',
  'amount',
  'created_at',
};

List<String> _stringList(Object? value) {
  if (value is List) return [for (final item in value) '$item'];
  return const [];
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
