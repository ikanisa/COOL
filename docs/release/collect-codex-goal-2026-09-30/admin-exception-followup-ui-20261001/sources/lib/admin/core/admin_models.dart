import '../../core/data/exact_json_values.dart';
import 'admin_transaction_lifecycle.dart';

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
      value: _nonEmpty(json['value'], 'Not available'),
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
    if (json['rail'] == 'rw_momo' && json.containsKey('lifecycle')) {
      if (json['lifecycle'] == null) {
        throw const FormatException('Missing transaction lifecycle evidence.');
      }
      AdminTransactionLifecycle.parse(json['lifecycle']);
    }
    return AdminTableRowData(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Record',
      subtitle: (json['subtitle'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'unknown',
      amount: (json['amount'] as String?) ?? '',
      createdAt: _dateTimeOrNull(json['created_at']),
      extra: {
        for (final entry in json.entries)
          if (!_tableFieldNames.contains(entry.key))
            entry.key: _tableExtraValue(entry.key, entry.value),
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
    if (rows is! List) {
      throw const FormatException('Admin list response is missing its rows.');
    }
    final total = _intOrNull(json['total']);
    if (json['total'] != null && total == null) {
      throw const FormatException(
        'Admin list total must be a non-negative integer.',
      );
    }
    if (total != null && total < rows.length) {
      throw const FormatException(
        'Admin list total is smaller than its row count.',
      );
    }
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          (row['id'] as String).trim().isEmpty) {
        throw const FormatException('Admin list contains an invalid record.');
      }
    }
    final parsedRows = [
      for (final row in rows)
        AdminTableRowData.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    return AdminListResult(
      rows: List<AdminTableRowData>.unmodifiable(parsedRows),
      total: total,
    );
  }

  /// Check the server window before showing any rows or page counters.
  /// Missing totals and short/truncated responses are not empty queues.
  AdminListResult validateWindow({required int limit, required int offset}) {
    final count = total;
    if (count == null || count < 0 || count > maxExactJsonInteger) {
      throw const FormatException(
        'Admin list is missing a valid server total.',
      );
    }
    if (limit < 1 || limit > maxExactJsonInteger) {
      throw RangeError.range(limit, 1, maxExactJsonInteger, 'limit');
    }
    if (offset < 0 || offset > maxExactJsonInteger) {
      throw RangeError.range(offset, 0, maxExactJsonInteger, 'offset');
    }
    final remaining = count - offset;
    final expected = remaining <= 0
        ? 0
        : (remaining < limit ? remaining : limit);
    if (rows.length != expected) {
      throw const FormatException(
        'Admin list rows do not match the server window.',
      );
    }
    final ids = <String>{};
    for (final row in rows) {
      if (row.id.trim().isEmpty || !ids.add(row.id)) {
        throw const FormatException(
          'Admin list contains missing or duplicate record IDs.',
        );
      }
    }
    return AdminListResult(
      rows: List<AdminTableRowData>.unmodifiable(rows),
      total: count,
    );
  }
}

class AdminQueueSla {
  const AdminQueueSla({
    required this.target,
    required this.owner,
    required this.escalation,
  });

  final String target;
  final String owner;
  final String escalation;

  factory AdminQueueSla.fromJson(Map<String, dynamic> json) {
    return AdminQueueSla(
      target: _nonEmpty(json['target'], 'Not available'),
      owner: _nonEmpty(json['owner'], 'Not available'),
      escalation: _nonEmpty(json['escalation'], 'Not available'),
    );
  }
}

class AdminRuntimeConfig {
  const AdminRuntimeConfig({
    required this.navigationItems,
    required this.queueSpecs,
  });

  final List<AdminNavigationItemConfig> navigationItems;
  final List<AdminQueueSpecConfig> queueSpecs;

  factory AdminRuntimeConfig.fromJson(Map<String, dynamic> json) {
    return AdminRuntimeConfig(
      navigationItems: [
        for (final item in _mapList(json['navigation_items']))
          AdminNavigationItemConfig.fromJson(item),
      ],
      queueSpecs: [
        for (final item in _mapList(json['queue_specs']))
          AdminQueueSpecConfig.fromJson(item),
      ],
    );
  }
}

class AdminNavigationItemConfig {
  const AdminNavigationItemConfig({
    required this.label,
    required this.iconKey,
    required this.path,
    required this.requiredPermission,
  });

  final String label;
  final String iconKey;
  final String path;
  final String requiredPermission;

  factory AdminNavigationItemConfig.fromJson(Map<String, dynamic> json) {
    return AdminNavigationItemConfig(
      label: _nonEmpty(json['label'], 'Admin'),
      iconKey: _nonEmpty(json['icon_key'], 'admin_panel_settings'),
      path: _nonEmpty(json['route_path'], '/admin'),
      requiredPermission: _nonEmpty(
        json['required_permission'],
        'overview.read',
      ),
    );
  }
}

class AdminQueueSpecConfig {
  const AdminQueueSpecConfig({
    required this.rpcName,
    required this.title,
    required this.subtitle,
    required this.statusOptions,
    required this.sortOptions,
    required this.prioritySignals,
    required this.workflowSteps,
  });

  final String rpcName;
  final String title;
  final String subtitle;
  final List<AdminFilterOptionConfig> statusOptions;
  final List<AdminFilterOptionConfig> sortOptions;
  final List<AdminQueueSignalConfig> prioritySignals;
  final List<AdminQueueSignalConfig> workflowSteps;

  factory AdminQueueSpecConfig.fromJson(Map<String, dynamic> json) {
    return AdminQueueSpecConfig(
      rpcName: _nonEmpty(json['rpc_name'], ''),
      title: _nonEmpty(json['title'], 'Admin queue'),
      subtitle: _nonEmpty(json['subtitle'], 'Review records.'),
      statusOptions: [
        for (final item in _mapList(json['status_options']))
          AdminFilterOptionConfig.fromJson(item),
      ],
      sortOptions: [
        for (final item in _mapList(json['sort_options']))
          AdminFilterOptionConfig.fromJson(item),
      ],
      prioritySignals: [
        for (final item in _mapList(json['priority_signals']))
          AdminQueueSignalConfig.fromJson(item),
      ],
      workflowSteps: [
        for (final item in _mapList(json['workflow_steps']))
          AdminQueueSignalConfig.fromJson(item),
      ],
    );
  }
}

class AdminFilterOptionConfig {
  const AdminFilterOptionConfig({required this.value, required this.label});

  final String value;
  final String label;

  factory AdminFilterOptionConfig.fromJson(Map<String, dynamic> json) {
    return AdminFilterOptionConfig(
      value: (json['value'] as String?) ?? '',
      label: _nonEmpty(json['label'], 'All'),
    );
  }
}

class AdminQueueSignalConfig {
  const AdminQueueSignalConfig({required this.iconKey, required this.label});

  final String iconKey;
  final String label;

  factory AdminQueueSignalConfig.fromJson(Map<String, dynamic> json) {
    return AdminQueueSignalConfig(
      iconKey: _nonEmpty(json['icon_key'], 'info'),
      label: _nonEmpty(json['label'], 'Review'),
    );
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
  return value == null ? null : exactJsonTimestamp(value, field: 'created_at');
}

int? _intOrNull(Object? value) {
  if (value == null) return null;
  try {
    return exactJsonInteger(
      value is String ? value.trim() : value,
      field: 'total',
      minimum: 0,
      allowDigitString: true,
    );
  } on FormatException {
    return null;
  }
}

Object? _tableExtraValue(String key, Object? value) {
  if (value == null) return null;
  return switch (key) {
    'active_members' || 'active_groups' => exactJsonInteger(
      value is String ? value.trim() : value,
      field: key,
      minimum: 0,
      allowDigitString: true,
    ),
    'updated_at' => exactJsonTimestamp(value, field: key),
    'lifecycle' => Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(value as Map),
    ),
    _ => value,
  };
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

String _nonEmpty(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}
