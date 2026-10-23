// Public-code defaults exporter; no credentials, provider calls or file writes.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> runtimeJson(CollectRuntimeConfig c) => {
  'brand': {
    'display_name': c.brandDisplayName,
    'legal_name': c.legalName,
    'public_url': c.publicUrl,
    'admin_url': c.adminUrl,
    'app_download_url': c.appDownloadUrl,
    'regulatory_footer_note': c.regulatoryFooterNote,
  },
  'support_channels': [
    {
      'key': 'support.whatsapp',
      'value': c.whatsAppSupportPhone,
      'display_value': c.whatsAppSupportDisplay,
    },
    {'key': 'support.email', 'value': c.supportEmail},
  ],
};
Map<String, dynamic> optionJson(CollectionCatalogOption o) => {
  'key': o.key,
  'label': o.label,
};
Map<String, dynamic> catalogJson(CollectionTypeCatalogConfig c) => {
  'country_code': c.countryCode,
  'locale': c.locale,
  'types': [
    for (final t in c.types)
      {
        'key': t.type.storageValue,
        'label': t.label,
        'short_purpose': t.shortPurpose,
        'icon_key': t.iconKey,
        'default_category_subtype': t.defaultCategorySubtype,
        'default_purpose_template_key': t.defaultPurposeTemplateKey,
        'subtypes': t.subtypes.map(optionJson).toList(),
        'purpose_templates': t.purposeTemplates.map(optionJson).toList(),
      },
  ],
};
Map<String, dynamic> reasonJson(AccountRequestReasonOption r) => {
  'key': r.key,
  'label': r.label,
};
Map<String, dynamic> clone(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

/// Bind the exact public package map explicitly passed to the Flutter compiler.
/// The wrapper pins this file before and after Flutter uses its package map.
/// Normal test mode never calls this function and never reads source files.
Future<Map<String, dynamic>> resolvedSourceInputs() async {
  final path = Platform.environment['COLLECT_PUBLIC_DEFAULTS_PACKAGE_CONFIG'];
  final expected =
      Platform.environment['COLLECT_PUBLIC_DEFAULTS_PACKAGE_CONFIG_SHA256'];
  expect(path, isNotNull, reason: 'Export requires the compiler package map');
  expect(expected, matches(RegExp(r'^[a-f0-9]{64}$')));
  final configFile = File(path!);
  expect(configFile.path, configFile.absolute.path);
  expect(
    FileSystemEntity.typeSync(configFile.path, followLinks: false),
    FileSystemEntityType.file,
  );
  expect(configFile.resolveSymbolicLinksSync(), configFile.absolute.path);
  final configBytes = configFile.readAsBytesSync();
  expect(configBytes.length, lessThanOrEqualTo(1024 * 1024));
  expect(sha256.convert(configBytes).toString(), expected);
  final config = jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>;
  expect(config['configVersion'], isA<int>());
  expect(config['configVersion'], 2);
  final packages = config['packages'] as List;
  final names = packages.map((entry) => (entry as Map)['name']).toList();
  expect(
    names.toSet().length,
    names.length,
    reason: 'Package names must be unique',
  );
  final own = packages.where(
    (entry) => (entry as Map)['name'] == 'collect_app',
  );
  expect(
    own.length,
    1,
    reason: 'Exactly one compiled Collect package is required',
  );
  final mapping = own.single as Map;
  expect(mapping['rootUri'], isA<String>());
  expect(mapping['packageUri'], 'lib/');
  final root = configFile.uri.resolve(mapping['rootUri'] as String);
  expect(root.scheme, 'file');
  expect(root.query, isEmpty);
  expect(root.fragment, isEmpty);
  final physicalRoot = Directory.fromUri(root).resolveSymbolicLinksSync();
  expect(
    Directory(physicalRoot).uri,
    root,
    reason: 'The compiler map must resolve a physical package root',
  );
  final lib = root.resolve(mapping['packageUri'] as String);
  expect(lib, root.resolve('lib/'));
  expect(Directory(Directory.fromUri(lib).resolveSymbolicLinksSync()).uri, lib);
  const modelPath = 'lib/shared/models/collect_models.dart';
  const paths = [
    modelPath,
    'lib/shared/models/collect_payment_models.dart',
    'lib/shared/models/collect_payment_json.dart',
    'lib/shared/models/collect_model_json_helpers.dart',
    'lib/shared/models/collect_summary_json.dart',
    'lib/shared/models/collect_profile_country_rules.dart',
    'lib/core/data/exact_json_values.dart',
    'lib/shared/repositories/collect_repository_providers.dart',
    'pubspec.yaml',
    'pubspec.lock',
  ];
  final result = <String, dynamic>{};
  final sources = <String, File>{};
  for (final relative in paths) {
    final uri = relative.startsWith('lib/')
        ? lib.resolve(relative.substring(4))
        : root.resolve(relative);
    expect(uri, root.resolve(relative));
    final file = File.fromUri(uri);
    expect(
      FileSystemEntity.typeSync(file.path, followLinks: false),
      FileSystemEntityType.file,
    );
    expect(
      file.resolveSymbolicLinksSync(),
      file.absolute.path,
      reason: 'An aliased public source is not compiler provenance',
    );
    final before = file.statSync();
    final bytes = file.readAsBytesSync();
    final after = file.statSync();
    expect(bytes.length, lessThanOrEqualTo(1024 * 1024));
    expect(after.size, before.size);
    expect(after.modified, before.modified);
    expect(after.changed, before.changed);
    result[relative] = {
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    };
    sources[relative] = file;
  }
  final model = sources[modelPath]!.readAsStringSync();
  final parts = RegExp(
    r"^part '([^']+)';$",
    multiLine: true,
  ).allMatches(model).map((match) => match[1]).toSet();
  expect(
    parts,
    {
      'collect_payment_models.dart',
      'collect_payment_json.dart',
      'collect_model_json_helpers.dart',
      'collect_summary_json.dart',
    },
    reason: 'New or renamed compiled model parts require a provenance update',
  );
  for (final source in sources.entries) {
    final bytes = source.value.readAsBytesSync();
    expect(sha256.convert(bytes).toString(), result[source.key]['sha256']);
    expect(bytes.length, result[source.key]['bytes']);
  }
  expect(
    sha256.convert(configFile.readAsBytesSync()).toString(),
    expected,
    reason: 'The actual compiler map must remain byte-identical',
  );
  return result;
}

void main() {
  test(
    'public defaults roundtrip every field and export binds compiler source',
    () async {
      const runtime = CollectRuntimeConfig.defaults;
      const catalog = collectDefaultCollectionTypeCatalog;
      final runtimeValue = runtimeJson(runtime);
      final catalogValue = catalogJson(catalog);
      final reasons = collectDefaultAccountDeletionReasons
          .map(reasonJson)
          .toList();
      var checkedMutations = 0;
      expect(
        runtimeJson(CollectRuntimeConfig.fromJson(clone(runtimeValue))),
        runtimeValue,
      );
      expect(
        catalogJson(CollectionTypeCatalogConfig.fromJson(clone(catalogValue))),
        catalogValue,
      );
      expect((runtimeValue['brand'] as Map).keys.toSet(), {
        'display_name',
        'legal_name',
        'public_url',
        'admin_url',
        'app_download_url',
        'regulatory_footer_note',
      });
      // Defaults alone could conceal a missing field behind the factory fallback.
      // Change each field independently and require that exact value to survive.
      for (final key in (runtimeValue['brand'] as Map).keys.cast<String>()) {
        final changed = clone(runtimeValue);
        (changed['brand'] as Map)[key] = 'transport-sentinel-$key';
        expect(
          runtimeJson(CollectRuntimeConfig.fromJson(changed)),
          changed,
          reason: 'runtime brand field $key must not fall back',
        );
        checkedMutations++;
      }
      final support = runtimeValue['support_channels'] as List;
      expect(support.map((c) => (c as Map)['key']).toList(), [
        'support.whatsapp',
        'support.email',
      ]);
      for (var i = 0; i < support.length; i++) {
        for (final key in (support[i] as Map).keys.cast<String>().where(
          (k) => k != 'key',
        )) {
          final changed = clone(runtimeValue);
          ((changed['support_channels'] as List)[i] as Map)[key] =
              'support-sentinel-$i-$key';
          expect(
            runtimeJson(CollectRuntimeConfig.fromJson(changed)),
            changed,
            reason: 'support channel $i field $key must survive',
          );
          checkedMutations++;
        }
      }
      expect(
        catalog.types.map((t) => t.type).toSet(),
        CollectionType.values.toSet(),
      );
      expect(catalog.types.length, CollectionType.values.length);
      for (final key in ['country_code', 'locale']) {
        final changed = clone(catalogValue)..[key] = 'transport-sentinel-$key';
        expect(
          catalogJson(CollectionTypeCatalogConfig.fromJson(changed)),
          changed,
        );
        checkedMutations++;
      }
      final rows = catalogValue['types'] as List;
      var subtypes = 0;
      var templates = 0;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i] as Map;
        expect(row.keys.toSet(), {
          'key',
          'label',
          'short_purpose',
          'icon_key',
          'default_category_subtype',
          'default_purpose_template_key',
          'subtypes',
          'purpose_templates',
        });
        final actual = catalog.types[i];
        expect(
          actual.subtypes.map((o) => o.key),
          contains(actual.defaultCategorySubtype),
        );
        expect(
          actual.purposeTemplates.map((o) => o.key),
          contains(actual.defaultPurposeTemplateKey),
        );
        for (final key in [
          'label',
          'short_purpose',
          'icon_key',
          'default_category_subtype',
          'default_purpose_template_key',
        ]) {
          final changed = clone(catalogValue);
          ((changed['types'] as List)[i] as Map)[key] =
              'catalog-sentinel-$i-$key';
          expect(
            catalogJson(CollectionTypeCatalogConfig.fromJson(changed)),
            changed,
            reason: 'catalog $i $key must not fall back',
          );
          checkedMutations++;
        }
        final changedType = clone(catalogValue);
        final nextType = catalog.types[(i + 1) % rows.length].type;
        ((changedType['types'] as List)[i] as Map)['key'] =
            nextType.storageValue;
        expect(
          CollectionTypeCatalogConfig.fromJson(changedType).types[i].type,
          nextType,
        );
        expect(
          catalogJson(CollectionTypeCatalogConfig.fromJson(changedType)),
          changedType,
        );
        checkedMutations++;
        for (final listKey in ['subtypes', 'purpose_templates']) {
          final options = row[listKey] as List;
          expect(options, isNotEmpty);
          if (listKey == 'subtypes') {
            subtypes += options.length;
          } else {
            templates += options.length;
          }
          for (var j = 0; j < options.length; j++) {
            expect((options[j] as Map).keys.toSet(), {'key', 'label'});
            for (final key in ['key', 'label']) {
              final changed = clone(catalogValue);
              ((((changed['types'] as List)[i] as Map)[listKey] as List)[j]
                      as Map)[key] =
                  'option-sentinel-$i-$listKey-$j-$key';
              expect(
                catalogJson(CollectionTypeCatalogConfig.fromJson(changed)),
                changed,
                reason: 'every option $i/$listKey/$j/$key must survive',
              );
              checkedMutations++;
            }
          }
        }
      }
      expect(reasons.length, collectDefaultAccountDeletionReasons.length);
      expect(reasons.map((r) => r['key']).toSet().length, reasons.length);
      for (final reason in reasons) {
        expect(reason.keys.toSet(), {'key', 'label'});
        expect(
          reasonJson(AccountRequestReasonOption.fromJson(clone(reason))),
          reason,
        );
        for (final key in ['key', 'label']) {
          final changed = clone(reason)..[key] = 'reason-sentinel-$key';
          expect(
            reasonJson(AccountRequestReasonOption.fromJson(changed)),
            changed,
          );
          checkedMutations++;
        }
      }
      expect(subtypes, 13);
      expect(templates, 9);
      expect(checkedMutations, 91);
      // The normal suite checks all91 transport mutations without source reads.
      // Explicit export additionally requires the wrapper-pinned compiler map.
      if (Platform.environment['COLLECT_PUBLIC_DEFAULTS_EXPORT_STDOUT'] ==
          '1') {
        final sourceInputs = await resolvedSourceInputs();
        final document = {
          'schema_version': 1,
          'kind': 'collect_mobile_public_configuration_defaults',
          'source_inputs': sourceInputs,
          'values': {
            'get_public_runtime_config': runtimeValue,
            'get_collection_type_catalog': catalogValue,
            'list_account_request_reasons': reasons,
          },
        };
        final encoded = base64Encode(utf8.encode(jsonEncode(document)));
        // Required test-only machine frame; normal mode emits no payload.
        // ignore: avoid_print
        print('COLLECT_PUBLIC_DEFAULTS_EXPORT_BASE64:$encoded');
      }
    },
  );
}
