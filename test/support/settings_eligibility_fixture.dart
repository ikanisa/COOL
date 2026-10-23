import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'settings_fixture.dart' as f;

Map<String, dynamic> observedEligibility(String family) =>
    Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/observed_runtime_eligibility_v1.json',
            ).readAsStringSync(),
          )[family]
          as Map,
    );
Map<String, dynamic> observedLanguageCatalog() => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'test/fixtures/observed_sms_language_catalog_v2.json',
        ).readAsStringSync(),
      )
      as Map,
);
Map<String, dynamic> currentEligibility(
  AdminSettingsControl control,
  String raw, {
  List<String>? fields,
  List<String>? statuses,
  String? blocker,
  bool canManage = true,
  DateTime? at,
}) {
  final value = observedEligibility(control.family.key);
  value['identity'] = control.identity;
  value['revision'] = control.revision;
  value['patch_sha256'] = settingsHash(raw);
  value['checked_at'] = settingsUtc(at ?? f.at);
  value['sample_valid_until'] = settingsUtc(
    (at ?? f.at).add(const Duration(seconds: 60)),
  );
  value['permitted_fields'] =
      fields ??
      control.family.writableFields
          .where(
            (field) =>
                !control.exists ||
                !control.family.immutableFields.contains(field),
          )
          .toList();
  value['permitted_statuses'] =
      statuses ??
      (control.family.fieldTypes.containsKey('status')
          ? ['draft', 'published', 'archived']
          : []);
  value['blocker'] = blocker;
  value['can_manage'] = canManage;
  value['create_allowed'] = canManage && control.family.createAllowed;
  return value;
}

Map<String, dynamic> controlJson(
  String name, {
  bool exists = true,
  String status = 'draft',
}) {
  final family = AdminSettingsFamily.parse(name);
  final identity = family.identity(
    name == 'notification_templates'
        ? {'key': 'qa_runtime_current'}
        : {'id': f.request},
  );
  final values = <String, Object?>{
    'policy_document_sections': {
      'id': f.request,
      'policy_document_id': f.request,
      'section_key': 'terms',
      'title': 'Reviewed terms',
      'body': 'Draft disclosure',
      'display_order': 1,
      'metadata': {},
    },
    'policy_documents': {
      'id': f.request,
      'kind': 'privacy',
      'locale': 'en',
      'version': 'v1',
      'title': 'Draft policy',
      'summary': null,
      'status': status,
      'effective_at': '2026-10-01T00:00:00Z',
      'metadata': {},
    },
    'notification_template_versions': {
      'id': f.request,
      'template_key': 'qa_runtime_current',
      'version': 'v1',
      'title_template': 'Draft title',
      'body_template': 'Draft body',
      'status': status,
      'effective_at': '2026-10-01T00:00:00Z',
      'metadata': {},
    },
    'notification_templates': {
      'key': 'qa_runtime_current',
      'event_type_key': 'notice',
      'locale': 'en',
      'enabled': true,
      'metadata': {},
    },
  };
  return {
    'contract_version': 2,
    'scope': 'runtime_controls',
    'ok': true,
    'family': family.key,
    'identity': identity,
    'revision': exists ? 1 : 0,
    'exists': exists,
    'value': exists ? values[name] : null,
    'redacted': false,
    'content_sha256': exists ? 'a' * 64 : null,
    'checked_at': settingsUtc(f.at),
    'sample_valid_until': settingsUtc(f.at.add(const Duration(seconds: 60))),
    'can_manage': true,
  };
}

AdminSettingsControl control(
  String family, {
  bool exists = true,
  String status = 'draft',
}) {
  final raw = controlJson(family, exists: exists, status: status);
  return AdminSettingsControl.parse(
    raw,
    AdminSettingsFamily.parse(family),
    Map<String, Object?>.from(raw['identity'] as Map),
  );
}

AdminSettingsControl languageControl() {
  final raw = observedLanguageCatalog(),
      row = Map<String, dynamic>.from((raw['rows'] as List).single as Map);
  return AdminSettingsControl.parse(
    {
      ...row,
      'contract_version': 2,
      'scope': raw['scope'],
      'ok': true,
      'family': raw['family'],
      'checked_at': settingsUtc(f.at),
      'sample_valid_until': settingsUtc(f.at.add(const Duration(seconds: 60))),
      'can_manage': true,
    },
    AdminSettingsFamily.parse(raw['family']),
    Map<String, Object?>.from(row['identity'] as Map),
  );
}
