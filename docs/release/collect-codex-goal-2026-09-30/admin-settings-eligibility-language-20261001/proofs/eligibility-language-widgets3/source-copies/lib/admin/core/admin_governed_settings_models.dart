import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/data/exact_json_values.dart';
import 'admin_auth_guard.dart';
import 'admin_models.dart';
import 'admin_governed_settings_registry.dart';

Never governedSettingsInvalid([String? field]) => throw FormatException(
  field == null
      ? 'The Settings response could not be validated.'
      : 'Invalid $field.',
);
Map<String, Object?> settingsObject(Object? raw, Set<String> keys) {
  if (raw is! Map ||
      raw.length != keys.length ||
      raw.keys.any((k) => k is! String || !keys.contains(k))) {
    governedSettingsInvalid();
  }
  return Map<String, Object?>.unmodifiable(raw.cast<String, Object?>());
}

String settingsUuid(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(raw)) {
    governedSettingsInvalid('identifier');
  }
  return raw;
}

String settingsDigest(Object? raw) {
  if (raw is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw)) {
    governedSettingsInvalid('fingerprint');
  }
  return raw;
}

DateTime settingsInstant(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$').hasMatch(raw)) {
    governedSettingsInvalid('timestamp');
  }
  return exactJsonTimestamp(raw, field: 'Settings timestamp');
}

String settingsUtc(DateTime value) {
  exactJsonTimestamp(value, field: 'Settings deadline');
  final text = value.toUtc().toIso8601String();
  return '${text.substring(0, 20)}${text.substring(20, text.length - 1).padRight(6, '0')}Z';
}

String settingsHash(String raw) => sha256.convert(utf8.encode(raw)).toString();
int settingsInteger(Object? raw, {int minimum = 0, int maximum = 1000000000}) {
  if (raw is! int || raw < minimum || raw > maximum) {
    governedSettingsInvalid('integer');
  }
  return raw;
}

bool settingsBoolean(Object? raw) {
  if (raw is! bool) governedSettingsInvalid('boolean');
  return raw;
}

String settingsText(Object? raw, {int maximum = 32768}) {
  if (raw is! String ||
      raw.runes.length > maximum ||
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]').hasMatch(raw)) {
    governedSettingsInvalid('text');
  }
  return raw;
}

List<String> _settingsFields(Object? raw) {
  if (raw is! List || raw.length > 50) governedSettingsInvalid('fields');
  final fields = raw.map((x) => settingsText(x, maximum: 128)).toList();
  if (fields.toSet().length != fields.length ||
      fields.any((x) => !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(x))) {
    governedSettingsInvalid('fields');
  }
  return List.unmodifiable(fields);
}

Object? settingsFreeze(Object? value, [int depth = 0]) {
  if (depth > 5) governedSettingsInvalid('JSON depth');
  if (value == null || value is bool) return value;
  if (value is int) {
    return exactJsonInteger(
      value,
      field: 'Settings JSON',
      minimum: -100000000000,
      maximum: 100000000000,
    );
  }
  if (value is String) return settingsText(value);
  if (value is List && value.length <= 50) {
    return List<Object?>.unmodifiable(
      value.map((v) => settingsFreeze(v, depth + 1)),
    );
  }
  if (value is Map && value.length <= 50) {
    final out = <String, Object?>{};
    for (final e in value.entries) {
      final key = settingsText(e.key, maximum: 80);
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_.:-]*$').hasMatch(key) ||
          RegExp(
            r'(secret|password|credential|api[_-]?key|authorization|access[_-]?token|refresh[_-]?token|private[_-]?key)',
            caseSensitive: false,
          ).hasMatch(key)) {
        governedSettingsInvalid('JSON key');
      }
      out[key] = settingsFreeze(e.value, depth + 1);
    }
    return Map<String, Object?>.unmodifiable(out);
  }
  // JSON settings do allow finite decimal numbers, within exact JSON range.
  if (value is double && value.isFinite && value.abs() <= 100000000000) {
    return value;
  }
  governedSettingsInvalid('JSON value');
}

String _settingsFieldText(String field, Object? raw) {
  final limit =
      {
        'body',
        'body_template',
        'instructions',
        'regulatory_footer_note',
      }.contains(field)
      ? 24000
      : {
          'description',
          'subtitle',
          'summary',
          'short_purpose',
          'target',
          'owner',
          'escalation',
        }.contains(field)
      ? 2000
      : field.endsWith('url')
      ? 2048
      : 500;
  final value = settingsText(raw, maximum: limit);
  if (field == 'receipt_language' &&
      !const {'rw', 'en', 'fr'}.contains(value)) {
    governedSettingsInvalid('receipt language');
  }
  if ({
        'key',
        'queue_key',
        'rpc_name',
        'section_key',
        'icon_key',
        'version',
        'locale',
        'network',
        'currency',
        'country_code',
        'required_permission',
        'template_key',
        'event_type_key',
        'preference_key',
        'collection_type_key',
        'default_category_subtype',
        'default_purpose_template_key',
      }.contains(field) &&
      (value.isEmpty ||
          value.length > 128 ||
          !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(value))) {
    governedSettingsInvalid(field);
  }
  if ({
        'label',
        'display_name',
        'legal_name',
        'title',
        'title_template',
        'body_template',
        'body',
        'target',
        'owner',
        'escalation',
      }.contains(field) &&
      value.trim().isEmpty) {
    governedSettingsInvalid(field);
  }
  if (field.endsWith('url') &&
      (value.length < 10 ||
          !RegExp(
            r'^https://[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,63}(:443)?([/?][^\s@]*)?$',
          ).hasMatch(value) ||
          RegExp(r'^https://[0-9.]+').hasMatch(value))) {
    governedSettingsInvalid('HTTPS URL');
  }
  if ({'title_template', 'body_template'}.contains(field) &&
      RegExp(r'(\{\{|\}\})').hasMatch(
        value.replaceAll(RegExp(r'\{\{[a-z][a-z0-9_]{0,63}\}\}'), ''),
      )) {
    governedSettingsInvalid('template placeholder');
  }
  return value;
}

String settingsReason(String input) {
  const trim = {
    9,
    10,
    11,
    12,
    13,
    32,
    133,
    160,
    5760,
    8192,
    8193,
    8194,
    8195,
    8196,
    8197,
    8198,
    8199,
    8200,
    8201,
    8202,
    8232,
    8233,
    8239,
    8287,
    12288,
    65279,
  };
  final runes = input.runes.toList();
  var first = 0, last = runes.length;
  while (first < last && trim.contains(runes[first])) {
    first++;
  }
  while (last > first && trim.contains(runes[last - 1])) {
    last--;
  }
  final value = String.fromCharCodes(runes.sublist(first, last));
  if (value.runes.length < 8 || value.runes.length > 500) {
    governedSettingsInvalid('reason (8–500 characters)');
  }
  settingsText(value, maximum: 500);
  return value;
}

class AdminSettingsFamily {
  AdminSettingsFamily._(this.key, this.spec);
  static final List<AdminSettingsFamily> values = List.unmodifiable(
    (jsonDecode(adminGovernedSettingsRegistryJson) as Map<String, dynamic>)
        .entries
        .map(
          (e) => AdminSettingsFamily._(
            e.key,
            Map<String, Object?>.unmodifiable(e.value as Map<String, dynamic>),
          ),
        ),
  );
  static AdminSettingsFamily parse(Object? raw) => values.firstWhere(
    (f) => raw is String && f.key == raw,
    orElse: governedSettingsInvalid,
  );
  final String key;
  final Map<String, Object?> spec;
  String get label => key
      .split('_')
      .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
      .join(' ');
  List<String> get identityFields => _settingsFields(spec['identity']);
  List<String> get writableFields => _settingsFields(spec['writable']);
  List<String> get immutableFields => _settingsFields(spec['immutable']);
  List<String> get nullableFields => _settingsFields(spec['nullable']);
  Map<String, String> get fieldTypes => Map<String, String>.unmodifiable(
    (spec['types'] as Map).cast<String, String>(),
  );
  bool get createAllowed => settingsBoolean(spec['create_allowed']);
  bool canRead(AdminIdentity? i) =>
      i != null &&
      i.roles.contains('platform_owner') &&
      i.permissions.contains(spec['read_permission']);
  bool canManage(AdminIdentity? i) =>
      canRead(i) &&
      i!.permissions.contains(spec['permission']) &&
      (spec['additional_permission'] == null ||
          i.permissions.contains(spec['additional_permission']));
  bool canAudit(AdminIdentity? i) =>
      i != null &&
      i.roles.contains('platform_owner') &&
      i.permissions.contains('audit.read');
  Map<String, Object?> identity(Object? raw) {
    final result = settingsObject(raw, identityFields.toSet());
    for (final field in identityFields) {
      final value = result[field];
      switch (fieldTypes[field]) {
        case 'uuid':
          settingsUuid(value);
          break;
        case 'boolean':
          if (value != true) governedSettingsInvalid('singleton identity');
          break;
        case 'text':
          if (value is! String ||
              value.isEmpty ||
              value.length > 128 ||
              !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(value)) {
            governedSettingsInvalid('identity');
          }
          break;
        default:
          governedSettingsInvalid('identity type');
      }
    }
    return Map.unmodifiable({
      for (final field in identityFields) field: result[field],
    });
  }

  Object? fieldValue(String field, Object? raw) {
    if (!fieldTypes.containsKey(field)) governedSettingsInvalid('field');
    if (raw == null) {
      if (!nullableFields.contains(field)) {
        governedSettingsInvalid('$field must have a value');
      }
      return null;
    }
    return switch (fieldTypes[field]) {
      'text' => _settingsFieldText(field, raw),
      'uuid' => settingsUuid(raw),
      'boolean' => settingsBoolean(raw),
      'integer' => settingsInteger(
        raw,
        minimum: -2147483648,
        maximum: 2147483647,
      ),
      'bigint' => exactJsonInteger(
        raw,
        field: field,
        minimum: -100000000000,
        maximum: 100000000000,
      ),
      'timestamp with time zone' => exactJsonTimestamp(
        raw,
        field: field,
      ).toUtc().toIso8601String(),
      'jsonb' => settingsFreeze(raw),
      _ => governedSettingsInvalid('field type'),
    };
  }

  Map<String, Object?> patch(Object? raw) {
    if (raw is! Map ||
        raw.isEmpty ||
        raw.length > writableFields.length ||
        raw.keys.any((k) => k is! String || !writableFields.contains(k))) {
      governedSettingsInvalid('patch');
    }
    final result = <String, Object?>{};
    for (final e in raw.entries) {
      result[e.key as String] = fieldValue(e.key as String, e.value);
      if ({'display_order', 'sort_order'}.contains(e.key) &&
          ((result[e.key] as int) < 0 || (result[e.key] as int) > 10000)) {
        governedSettingsInvalid('display order');
      }
    }
    if (utf8.encode(jsonEncode(result)).length > 65536) {
      governedSettingsInvalid('patch size');
    }
    return Map.unmodifiable(result);
  }
}

class AdminSettingsDescriptor {
  AdminSettingsDescriptor._(this.family, this.canManage);
  final AdminSettingsFamily family;
  final bool canManage;
  factory AdminSettingsDescriptor.parse(
    Object? raw,
    AdminSettingsFamily family,
  ) {
    final row = settingsObject(raw, {
      'identity_fields',
      'writable_fields',
      'immutable_fields',
      'nullable_fields',
      'field_types',
      'create_allowed',
      'can_manage',
    });
    for (final pair in [
      ('identity_fields', family.identityFields),
      ('writable_fields', family.writableFields),
      ('immutable_fields', family.immutableFields),
      ('nullable_fields', family.nullableFields),
    ]) {
      if (jsonEncode(_settingsFields(row[pair.$1])) != jsonEncode(pair.$2)) {
        governedSettingsInvalid('descriptor fields');
      }
    }
    final types = row['field_types'];
    if (types is! Map ||
        types.length != family.fieldTypes.length ||
        family.fieldTypes.entries.any((e) => types[e.key] != e.value) ||
        row['create_allowed'] != family.createAllowed) {
      governedSettingsInvalid('descriptor types');
    }
    return AdminSettingsDescriptor._(
      family,
      settingsBoolean(row['can_manage']),
    );
  }
}

class AdminSettingsSample {
  AdminSettingsSample(this.checkedAt, this.validUntil) {
    if (validUntil.difference(checkedAt) != const Duration(seconds: 60)) {
      governedSettingsInvalid('sample window');
    }
  }
  final DateTime checkedAt, validUntil;
  bool fresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);
}

void _settingsContract(Map<String, Object?> row, AdminSettingsFamily family) {
  if (row['contract_version'] != 2 ||
      row['contract_version'] is! int ||
      row['scope'] != 'runtime_controls' ||
      row['family'] != family.key) {
    governedSettingsInvalid('scope');
  }
}

class AdminSettingsControl {
  AdminSettingsControl._(
    this.family,
    this.identity,
    this.revision,
    this.exists,
    this.redacted,
    this.contentHash,
    this.value, {
    this.sample,
    this.canManage = false,
  });
  final AdminSettingsFamily family;
  final Map<String, Object?> identity, value;
  final int revision;
  final bool exists, redacted, canManage;
  final String? contentHash;
  final AdminSettingsSample? sample;
  factory AdminSettingsControl.row(Object? raw, AdminSettingsFamily family) =>
      _parse(
        settingsObject(raw, {
          'identity',
          'revision',
          'exists',
          'redacted',
          'content_sha256',
          'value',
        }),
        family,
      );
  factory AdminSettingsControl.parse(
    Object? raw,
    AdminSettingsFamily family,
    Map<String, Object?> expected,
  ) {
    final row = settingsObject(raw, {
      'contract_version',
      'scope',
      'ok',
      'family',
      'identity',
      'revision',
      'exists',
      'value',
      'redacted',
      'content_sha256',
      'checked_at',
      'sample_valid_until',
      'can_manage',
    });
    _settingsContract(row, family);
    if (row['ok'] != true ||
        jsonEncode(family.identity(row['identity'])) !=
            jsonEncode(family.identity(expected))) {
      governedSettingsInvalid('control identity');
    }
    return _parse(
      row,
      family,
      sample: AdminSettingsSample(
        settingsInstant(row['checked_at']),
        settingsInstant(row['sample_valid_until']),
      ),
      canManage: settingsBoolean(row['can_manage']),
    );
  }
  static AdminSettingsControl _parse(
    Map<String, Object?> row,
    AdminSettingsFamily family, {
    AdminSettingsSample? sample,
    bool canManage = false,
  }) {
    final identity = family.identity(row['identity']);
    final revision = settingsInteger(row['revision']);
    final exists = settingsBoolean(row['exists']),
        redacted = settingsBoolean(row['redacted']);
    if (exists && revision == 0 || redacted && row['content_sha256'] != null) {
      governedSettingsInvalid('control revision');
    }
    final hash = row['content_sha256'] == null
        ? null
        : settingsDigest(row['content_sha256']);
    if (exists && !redacted && hash == null) {
      governedSettingsInvalid('control hash');
    }
    final raw = row['value'];
    if (exists != (raw is Map)) governedSettingsInvalid('control value');
    final value = <String, Object?>{};
    if (raw is Map) {
      if (raw.keys.any(
            (k) => k is! String || !family.fieldTypes.containsKey(k),
          ) ||
          identity.entries.any((e) => raw[e.key] != e.value) ||
          redacted && raw.containsKey('value')) {
        governedSettingsInvalid('projected value');
      }
      for (final e in raw.entries) {
        value[e.key as String] = family.fieldValue(e.key as String, e.value);
      }
    }
    return AdminSettingsControl._(
      family,
      identity,
      revision,
      exists,
      redacted,
      hash,
      Map.unmodifiable(value),
      sample: sample,
      canManage: canManage,
    );
  }

  bool editableField(String field) =>
      !redacted &&
      family.writableFields.contains(field) &&
      family.key != 'policy_document_sections' &&
      !(family.key == 'notification_templates' &&
          exists &&
          field != 'enabled') &&
      !(exists && family.immutableFields.contains(field)) &&
      !(exists &&
          {
            'policy_documents',
            'notification_template_versions',
          }.contains(family.key) &&
          {'published', 'archived'}.contains(value['status']) &&
          field != 'status');
  List<String> get permittedStatuses => value['status'] == 'archived'
      ? const ['archived']
      : value['status'] == 'published'
      ? const ['published', 'archived']
      : family.key == 'policy_documents'
      ? const ['draft', 'archived']
      : const ['draft', 'published', 'archived'];
}

class AdminSettingsCatalog {
  AdminSettingsCatalog._(
    this.family,
    this.descriptor,
    this.sample,
    this.limit,
    this.rows,
    this.nextCursor,
  );
  final AdminSettingsFamily family;
  final AdminSettingsDescriptor descriptor;
  final AdminSettingsSample sample;
  final int limit;
  final List<AdminSettingsControl> rows;
  final Map<String, Object?>? nextCursor;
  factory AdminSettingsCatalog.parse(
    Object? raw,
    AdminSettingsFamily family, {
    required int limit,
  }) {
    final row = settingsObject(raw, {
      'contract_version',
      'scope',
      'family',
      'checked_at',
      'sample_valid_until',
      'limit',
      'descriptor',
      'rows',
      'next_cursor',
    });
    _settingsContract(row, family);
    if (row['limit'] != limit ||
        limit < 1 ||
        limit > 25 ||
        row['rows'] is! List ||
        (row['rows'] as List).length > limit) {
      governedSettingsInvalid('catalog page');
    }
    final rows = List<AdminSettingsControl>.unmodifiable(
      (row['rows'] as List).map((x) => AdminSettingsControl.row(x, family)),
    );
    final cursor = row['next_cursor'] == null
        ? null
        : family.identity(row['next_cursor']);
    if (rows.map((x) => jsonEncode(x.identity)).toSet().length != rows.length ||
        cursor != null &&
            (rows.length != limit ||
                jsonEncode(cursor) != jsonEncode(rows.last.identity))) {
      governedSettingsInvalid('catalog cursor');
    }
    return AdminSettingsCatalog._(
      family,
      AdminSettingsDescriptor.parse(row['descriptor'], family),
      AdminSettingsSample(
        settingsInstant(row['checked_at']),
        settingsInstant(row['sample_valid_until']),
      ),
      limit,
      rows,
      cursor,
    );
  }
}

class AdminSettingsEligibility {
  AdminSettingsEligibility._(
    this.family,
    this.identity,
    this.revision,
    this.patchSha256,
    this.sample,
    this.canManage,
    this.permittedFields,
    this.permittedStatuses,
    this.createAllowed,
    this.blocker,
  );
  final AdminSettingsFamily family;
  final Map<String, Object?> identity;
  final int revision;
  final String patchSha256;
  final AdminSettingsSample sample;
  final bool canManage, createAllowed;
  final List<String> permittedFields, permittedStatuses;
  final String? blocker;
  static bool requiredFor(AdminSettingsFamily family) => const {
    'policy_documents',
    'policy_document_sections',
    'notification_templates',
    'notification_template_versions',
  }.contains(family.key);
  factory AdminSettingsEligibility.parse(
    Object? raw,
    AdminSettingsFamily family,
    Map<String, Object?> identity,
    int revision,
    String patchJson,
  ) {
    final v = settingsObject(raw, const {
      'contract_version',
      'scope',
      'family',
      'identity',
      'revision',
      'patch_sha256',
      'checked_at',
      'sample_valid_until',
      'can_manage',
      'permitted_fields',
      'permitted_statuses',
      'create_allowed',
      'blocker',
    });
    final bound = family.identity(identity);
    if (v['contract_version'] != 1 ||
        v['scope'] != 'runtime_control_eligibility' ||
        v['family'] != family.key ||
        jsonEncode(family.identity(v['identity'])) != jsonEncode(bound) ||
        settingsInteger(v['revision']) != revision ||
        settingsDigest(v['patch_sha256']) != settingsHash(patchJson)) {
      governedSettingsInvalid('eligibility binding');
    }
    final fields = _settingsFields(v['permitted_fields']),
        statuses = _settingsFields(v['permitted_statuses']);
    if (fields.any((f) => !family.writableFields.contains(f)) ||
        statuses.any(
          (s) => !const ['draft', 'published', 'archived'].contains(s),
        ) ||
        (statuses.isNotEmpty &&
            !const {
              'policy_documents',
              'notification_template_versions',
            }.contains(family.key))) {
      governedSettingsInvalid('eligibility fields');
    }
    final blocker = v['blocker'] == null ? null : settingsText(v['blocker']);
    if (blocker != null &&
        !const {
          'create_not_allowed',
          'sensitive_value',
          'parent_required',
          'parent_missing',
          'parent_published',
          'patch_not_permitted',
          'status_not_permitted',
          'sections_required',
          'manage_required',
        }.contains(blocker))
      governedSettingsInvalid('eligibility blocker');
    final manage = settingsBoolean(v['can_manage']);
    if (!manage &&
        (fields.isNotEmpty ||
            statuses.isNotEmpty ||
            v['create_allowed'] != false ||
            blocker != 'manage_required')) {
      governedSettingsInvalid('eligibility capability');
    }
    return AdminSettingsEligibility._(
      family,
      bound,
      revision,
      settingsDigest(v['patch_sha256']),
      AdminSettingsSample(
        settingsInstant(v['checked_at']),
        settingsInstant(v['sample_valid_until']),
      ),
      manage,
      fields,
      statuses,
      settingsBoolean(v['create_allowed']),
      blocker,
    );
  }
  void validate(AdminSettingsControl control, String patchJson, DateTime now) {
    final patch = control.family.patch(jsonDecode(patchJson));
    if (!sample.fresh(now) ||
        !canManage ||
        blocker != null ||
        family.key != control.family.key ||
        jsonEncode(identity) != jsonEncode(control.identity) ||
        revision != control.revision ||
        patchSha256 != settingsHash(patchJson) ||
        (!control.exists && !createAllowed) ||
        patch.keys.any((f) => !permittedFields.contains(f)) ||
        (patch.containsKey('status') &&
            !permittedStatuses.contains(patch['status']))) {
      governedSettingsInvalid('fresh exact draft eligibility');
    }
  }
}

class AdminSettingsPreparedUpdate {
  AdminSettingsPreparedUpdate._(
    this.requestId,
    this.family,
    this.identity,
    this.patchJson,
    this.reason,
    this.expectedRevision,
    this.createdAt,
    this.expiresAt,
    this.scope,
    this.fingerprint,
    this.eligibilityValidUntil,
  );
  final String requestId, patchJson, reason, fingerprint;
  final AdminSettingsFamily family;
  final Map<String, Object?> identity;
  final int expectedRevision;
  final DateTime createdAt, expiresAt;
  final AdminSessionScope scope;
  final DateTime? eligibilityValidUntil;
  factory AdminSettingsPreparedUpdate.prepare({
    required String requestId,
    required AdminSettingsControl control,
    required Map<String, Object?> patch,
    required String reason,
    required DateTime now,
    required AdminSessionScope scope,
    Duration lifetime = const Duration(seconds: 90),
    AdminSettingsEligibility? eligibility,
  }) {
    if (control.sample?.fresh(now) != true ||
        !control.canManage ||
        control.redacted ||
        !control.exists && !control.family.createAllowed ||
        lifetime <= Duration.zero ||
        lifetime > const Duration(seconds: 120)) {
      governedSettingsInvalid('fresh editable control');
    }
    final parsed = control.family.patch(patch);
    final exactPatch = jsonEncode(parsed);
    if (AdminSettingsEligibility.requiredFor(control.family)) {
      if (eligibility == null)
        governedSettingsInvalid('publication eligibility');
      eligibility.validate(control, exactPatch, now);
    } else if (parsed.keys.any((f) => !control.editableField(f))) {
      governedSettingsInvalid('immutable field');
    }
    final raw = jsonEncode(parsed),
        normalized = settingsReason(reason),
        deadline = now.toUtc().add(lifetime),
        id = settingsUuid(requestId);
    settingsUuid(scope.key.userId);
    settingsUuid(scope.key.sessionId);
    final ident = control.family.identity(control.identity);
    final fingerprint = settingsHash(
      [
        'collect-runtime-control-request-v2',
        id,
        control.family.key,
        for (final field in control.family.identityFields)
          '$field=${ident[field]}',
        '${control.revision}',
        settingsUtc(deadline),
        settingsHash(raw),
        settingsHash(normalized),
      ].join('\n'),
    );
    return AdminSettingsPreparedUpdate._(
      id,
      control.family,
      ident,
      raw,
      normalized,
      control.revision,
      now.toUtc(),
      deadline,
      scope,
      fingerprint,
      eligibility?.sample.validUntil,
    );
  }
  bool current(AdminSessionScope? value, DateTime now) =>
      value == scope &&
      now.toUtc().isBefore(expiresAt) &&
      (eligibilityValidUntil == null ||
          now.toUtc().isBefore(eligibilityValidUntil!)) &&
      !createdAt.isAfter(now.toUtc().add(const Duration(seconds: 5)));
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_family': family.key,
    'p_identity': identity,
    'p_patch_json': patchJson,
    'p_expected_revision': expectedRevision,
    'p_reason': reason,
    'p_expires_at': settingsUtc(expiresAt),
  });
}

class AdminSettingsReceipt {
  AdminSettingsReceipt._(
    this.requestId,
    this.fingerprint,
    this.family,
    this.identity,
    this.previousRevision,
    this.revision,
    this.changed,
    this.updatedAt,
    this.contentHash,
    this.recordedAt,
    this.expiresAt,
  );
  final String requestId, fingerprint;
  final AdminSettingsFamily family;
  final Map<String, Object?> identity;
  final int previousRevision, revision;
  final bool changed;
  final DateTime updatedAt, recordedAt, expiresAt;
  final String contentHash;
  factory AdminSettingsReceipt.parse(Object? raw) {
    final row = settingsObject(raw, {
      'contract_version',
      'scope',
      'request_id',
      'request_fingerprint',
      'family',
      'identity',
      'previous_revision',
      'revision',
      'changed',
      'updated_at',
      'content_sha256',
      'recorded_at',
      'expires_at',
    });
    final family = AdminSettingsFamily.parse(row['family']);
    _settingsContract(row, family);
    final previous = settingsInteger(row['previous_revision']),
        revision = settingsInteger(row['revision'], minimum: 1),
        changed = settingsBoolean(row['changed']);
    final updated = settingsInstant(row['updated_at']),
        recorded = settingsInstant(row['recorded_at']),
        expires = settingsInstant(row['expires_at']);
    if (revision != previous + (changed ? 1 : 0) ||
        updated.isAfter(recorded) ||
        !recorded.isBefore(expires)) {
      governedSettingsInvalid('receipt revision/time');
    }
    return AdminSettingsReceipt._(
      settingsUuid(row['request_id']),
      settingsDigest(row['request_fingerprint']),
      family,
      family.identity(row['identity']),
      previous,
      revision,
      changed,
      updated,
      settingsDigest(row['content_sha256']),
      recorded,
      expires,
    );
  }
  void validatePrepared(AdminSettingsPreparedUpdate intent) {
    if (requestId != intent.requestId ||
        fingerprint != intent.fingerprint ||
        family.key != intent.family.key ||
        jsonEncode(identity) != jsonEncode(intent.identity) ||
        previousRevision != intent.expectedRevision ||
        expiresAt != intent.expiresAt ||
        recordedAt.isBefore(
          intent.createdAt.subtract(const Duration(seconds: 5)),
        )) {
      governedSettingsInvalid('original receipt');
    }
  }
}

/// Durable lookup binding only. It cannot reconstruct the patch, reason or
/// an executable prepared update and carries no prior session credential.
class AdminSettingsBookmark {
  AdminSettingsBookmark._(
    this.ownerDigest,
    this.requestId,
    this.family,
    this.identity,
    this.fingerprint,
    this.expiresAt,
  );
  final String ownerDigest, requestId, fingerprint;
  final AdminSettingsFamily family;
  final Map<String, Object?> identity;
  final DateTime expiresAt;
  factory AdminSettingsBookmark.fromPrepared(
    String ownerDigest,
    AdminSettingsPreparedUpdate intent,
  ) => AdminSettingsBookmark.parse(
    jsonEncode({
      'version': 2,
      'owner_digest': ownerDigest,
      'request_id': intent.requestId,
      'family': intent.family.key,
      'identity': intent.identity,
      'request_fingerprint': intent.fingerprint,
      'expires_at': settingsUtc(intent.expiresAt),
    }),
    ownerDigest,
  );
  factory AdminSettingsBookmark.parse(String raw, String expectedOwner) {
    if (utf8.encode(raw).length > 4096) governedSettingsInvalid('bookmark');
    final row = settingsObject(jsonDecode(raw), {
      'version',
      'owner_digest',
      'request_id',
      'family',
      'identity',
      'request_fingerprint',
      'expires_at',
    });
    final family = AdminSettingsFamily.parse(row['family']);
    if (row['version'] is! int ||
        row['version'] != 2 ||
        row['owner_digest'] != settingsDigest(expectedOwner)) {
      governedSettingsInvalid('bookmark owner');
    }
    return AdminSettingsBookmark._(
      expectedOwner,
      settingsUuid(row['request_id']),
      family,
      family.identity(row['identity']),
      settingsDigest(row['request_fingerprint']),
      settingsInstant(row['expires_at']),
    );
  }
  String encode() => jsonEncode({
    'version': 2,
    'owner_digest': ownerDigest,
    'request_id': requestId,
    'family': family.key,
    'identity': identity,
    'request_fingerprint': fingerprint,
    'expires_at': settingsUtc(expiresAt),
  });
  String get digest => settingsHash(encode());
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_family': family.key,
    'p_identity': identity,
    'p_request_fingerprint': fingerprint,
    'p_expires_at': settingsUtc(expiresAt),
  });
  void validateReceipt(AdminSettingsReceipt receipt) {
    if (receipt.requestId != requestId ||
        receipt.fingerprint != fingerprint ||
        receipt.family.key != family.key ||
        jsonEncode(receipt.identity) != jsonEncode(identity) ||
        receipt.expiresAt != expiresAt) {
      governedSettingsInvalid('bookmark receipt');
    }
  }
}

class AdminSettingsLookup {
  AdminSettingsLookup._(this.status, this.sample, this.receipt);
  final String status;
  final AdminSettingsSample sample;
  final AdminSettingsReceipt? receipt;
  factory AdminSettingsLookup.parse(
    Object? raw,
    AdminSettingsBookmark original,
  ) {
    final row = settingsObject(raw, {
      'contract_version',
      'scope',
      'request_id',
      'request_fingerprint',
      'family',
      'identity',
      'expires_at',
      'checked_at',
      'sample_valid_until',
      'status',
      'receipt',
    });
    _settingsContract(row, original.family);
    if (row['request_id'] != original.requestId ||
        row['request_fingerprint'] != original.fingerprint ||
        jsonEncode(original.family.identity(row['identity'])) !=
            jsonEncode(original.identity) ||
        settingsInstant(row['expires_at']) != original.expiresAt ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(row['status'])) {
      governedSettingsInvalid('lookup binding');
    }
    final receipt = row['receipt'] == null
        ? null
        : AdminSettingsReceipt.parse(row['receipt']);
    if ((row['status'] == 'recorded') != (receipt != null)) {
      governedSettingsInvalid('lookup receipt');
    }
    if (receipt != null) {
      original.validateReceipt(receipt);
      if (receipt.recordedAt.isAfter(settingsInstant(row['checked_at']))) {
        governedSettingsInvalid('lookup receipt time');
      }
    }
    return AdminSettingsLookup._(
      row['status'] as String,
      AdminSettingsSample(
        settingsInstant(row['checked_at']),
        settingsInstant(row['sample_valid_until']),
      ),
      receipt,
    );
  }
}

class AdminSettingsHistoryCursor {
  AdminSettingsHistoryCursor(this.recordedAt, this.eventId);
  final DateTime recordedAt;
  final String eventId;
  factory AdminSettingsHistoryCursor.parse(Object? raw) {
    final row = settingsObject(raw, {'recorded_at', 'event_id'});
    return AdminSettingsHistoryCursor(
      settingsInstant(row['recorded_at']),
      settingsUuid(row['event_id']),
    );
  }
  int compare(AdminSettingsHistoryCursor other) {
    final at = recordedAt.compareTo(other.recordedAt);
    return at != 0 ? at : eventId.compareTo(other.eventId);
  }
}

class AdminSettingsHistoryEvent {
  AdminSettingsHistoryEvent._(
    this.eventId,
    this.requestId,
    this.operation,
    this.previousRevision,
    this.revision,
    this.recordedAt,
    this.actorId,
    this.authority,
    this.changedFields,
    this.oldHash,
    this.newHash,
    this.reasonHash,
    this.reasonCharacters,
    this.redacted,
  );
  final String eventId, operation, authority, reasonHash;
  final String? actorId, requestId, oldHash, newHash;
  final int previousRevision, revision, reasonCharacters;
  final DateTime recordedAt;
  final List<String> changedFields;
  final bool redacted;
  AdminSettingsHistoryCursor get cursor =>
      AdminSettingsHistoryCursor(recordedAt, eventId);
  factory AdminSettingsHistoryEvent.parse(
    Object? raw,
    AdminSettingsFamily family,
  ) {
    final row = settingsObject(raw, {
      'event_id',
      'request_id',
      'operation',
      'previous_revision',
      'revision',
      'recorded_at',
      'actor_id',
      'authority',
      'changed_fields',
      'old_sha256',
      'new_sha256',
      'reason_sha256',
      'reason_characters',
      'redacted',
    });
    final previous = settingsInteger(row['previous_revision']),
        revision = settingsInteger(row['revision'], minimum: 1),
        redacted = settingsBoolean(row['redacted']);
    final old = row['old_sha256'] == null
            ? null
            : settingsDigest(row['old_sha256']),
        next = row['new_sha256'] == null
            ? null
            : settingsDigest(row['new_sha256']);
    if (revision != previous + 1 ||
        !{'insert', 'update', 'delete'}.contains(row['operation']) ||
        !{'live_operator', 'database_owner'}.contains(row['authority']) ||
        redacted && (old != null || next != null)) {
      governedSettingsInvalid('history event');
    }
    return AdminSettingsHistoryEvent._(
      settingsUuid(row['event_id']),
      row['request_id'] == null ? null : settingsUuid(row['request_id']),
      row['operation'] as String,
      previous,
      revision,
      settingsInstant(row['recorded_at']),
      row['actor_id'] == null ? null : settingsUuid(row['actor_id']),
      row['authority'] as String,
      _settingsFields(row['changed_fields']),
      old,
      next,
      settingsDigest(row['reason_sha256']),
      settingsInteger(row['reason_characters'], minimum: 8, maximum: 500),
      redacted,
    );
  }
}

class AdminSettingsHistory {
  AdminSettingsHistory._(
    this.family,
    this.identity,
    this.sample,
    this.limit,
    this.events,
    this.nextCursor,
  );
  final AdminSettingsFamily family;
  final Map<String, Object?> identity;
  final AdminSettingsSample sample;
  final int limit;
  final List<AdminSettingsHistoryEvent> events;
  final AdminSettingsHistoryCursor? nextCursor;
  factory AdminSettingsHistory.parse(
    Object? raw,
    AdminSettingsFamily family,
    Map<String, Object?> identity, {
    required int limit,
    AdminSettingsHistoryCursor? before,
  }) {
    final row = settingsObject(raw, {
      'contract_version',
      'scope',
      'family',
      'identity',
      'checked_at',
      'sample_valid_until',
      'limit',
      'history_complete',
      'changes_only',
      'rows',
      'next_cursor',
    });
    _settingsContract(row, family);
    final bound = family.identity(identity);
    if (jsonEncode(family.identity(row['identity'])) != jsonEncode(bound) ||
        row['limit'] != limit ||
        limit < 1 ||
        limit > 25 ||
        row['history_complete'] != false ||
        row['changes_only'] != true ||
        row['rows'] is! List ||
        (row['rows'] as List).length > limit) {
      governedSettingsInvalid('history scope');
    }
    final sample = AdminSettingsSample(
      settingsInstant(row['checked_at']),
      settingsInstant(row['sample_valid_until']),
    );
    final events = List<AdminSettingsHistoryEvent>.unmodifiable(
      (row['rows'] as List).map(
        (x) => AdminSettingsHistoryEvent.parse(x, family),
      ),
    );
    for (var i = 0; i < events.length; i++) {
      if (events[i].recordedAt.isAfter(sample.checkedAt) ||
          before != null && events[i].cursor.compare(before) >= 0 ||
          i > 0 && events[i - 1].cursor.compare(events[i].cursor) <= 0) {
        governedSettingsInvalid('history order');
      }
    }
    final cursor = row['next_cursor'] == null
        ? null
        : AdminSettingsHistoryCursor.parse(row['next_cursor']);
    if (cursor != null &&
        (events.length != limit || cursor.compare(events.last.cursor) != 0)) {
      governedSettingsInvalid('history cursor');
    }
    return AdminSettingsHistory._(family, bound, sample, limit, events, cursor);
  }
}
