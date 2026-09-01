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
      target: (json['target'] as String?) ?? 'Review Collect queue daily',
      owner: (json['owner'] as String?) ?? 'Collect operations',
      escalation:
          (json['escalation'] as String?) ?? 'Escalate stale exceptions',
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
