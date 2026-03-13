import 'dart:collection';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final command = _parseCommand(args);
  final repoRoot = Directory.current;
  final metadataErrors = <String>[];
  final metadata = _loadReleaseMetadata(repoRoot, metadataErrors);

  if (command.generate && metadata != null) {
    final warnings = _generateReleaseAssets(repoRoot, metadata);
    for (final warning in warnings) {
      stderr.writeln('warning: $warning');
    }
  }

  final errors = <String>[
    ...metadataErrors,
    if (metadata != null) ..._validateIosAssociation(repoRoot, metadata),
    if (metadata != null) ..._validateAndroidAssetLinks(repoRoot, metadata),
    if (metadata != null) ..._validateStoreLinkConfig(repoRoot, metadata),
    if (metadata != null) ..._validatePlatformConfig(repoRoot, metadata),
  ];

  if (!command.check) {
    if (errors.isNotEmpty) {
      stderr.writeln(
        'Deep-link release asset generation finished with errors:',
      );
      for (final error in errors) {
        stderr.writeln('- $error');
      }
      exitCode = 1;
    }
    return;
  }

  if (errors.isEmpty) {
    stdout.writeln('Deep-link release assets look production-ready.');
    return;
  }

  stderr.writeln('Deep-link release asset validation failed:');
  for (final error in errors) {
    stderr.writeln('- $error');
  }
  exitCode = 1;
}

List<String> _generateReleaseAssets(
  Directory repoRoot,
  _ReleaseMetadata metadata,
) {
  final warnings = <String>[];
  _writeJsonFile(
    File('${repoRoot.path}/deeplinks/site/.well-known/assetlinks.json'),
    _buildExpectedAndroidAssetLinks(metadata),
  );
  _writeJsonFile(
    File('${repoRoot.path}/hosting/.well-known/assetlinks.json'),
    _buildExpectedAndroidAssetLinks(metadata),
  );
  _writeTextFile(
    File('${repoRoot.path}/deeplinks/site/assets/store-links.js'),
    _buildExpectedStoreLinksScript(metadata),
  );

  if (metadata.hasIosAssociationMetadata) {
    _writeJsonFile(
      File(
        '${repoRoot.path}/deeplinks/site/.well-known/apple-app-site-association',
      ),
      _buildExpectedIosAssociation(metadata),
    );
  } else {
    warnings.add(
      'Skipped apple-app-site-association generation because deeplinks/release_metadata.json is missing ios.teamId.',
    );
  }

  return warnings;
}

List<String> _validateIosAssociation(
  Directory repoRoot,
  _ReleaseMetadata metadata,
) {
  final errors = <String>[];
  final metadataErrors = _iosMetadataErrors(metadata);
  final file = File(
    '${repoRoot.path}/deeplinks/site/.well-known/apple-app-site-association',
  );
  final decoded = _decodeJsonFile(file, errors, 'apple-app-site-association');
  if (decoded is! Map<String, dynamic>) {
    errors.addAll(metadataErrors);
    return errors;
  }

  final applinks = decoded['applinks'];
  if (applinks is! Map<String, dynamic>) {
    errors.add('apple-app-site-association must define an applinks object.');
    errors.addAll(metadataErrors);
    return errors;
  }

  final details = applinks['details'];
  if (details is! List || details.isEmpty) {
    errors.add(
      'apple-app-site-association must include at least one applinks.details entry.',
    );
    errors.addAll(metadataErrors);
    return errors;
  }

  for (var index = 0; index < details.length; index++) {
    final detail = details[index];
    if (detail is! Map<String, dynamic>) {
      errors.add(
        'apple-app-site-association details[$index] must be an object.',
      );
      continue;
    }

    final appId = _normalizeString(detail['appID']);
    final appIds = detail['appIDs'] is List
        ? (detail['appIDs'] as List)
              .map((value) => _normalizeString(value))
              .whereType<String>()
              .toList(growable: false)
        : const <String>[];

    if (appId == null && appIds.isEmpty) {
      errors.add(
        'apple-app-site-association details[$index] must include appID or appIDs.',
      );
    }

    final allAppIds = <String>[...appIds];
    if (appId case final value?) {
      allAppIds.insert(0, value);
    }
    for (final value in allAppIds) {
      if (_containsPlaceholder(value)) {
        errors.add(
          'apple-app-site-association contains a placeholder app identifier: $value',
        );
      }
    }
  }

  errors.addAll(metadataErrors);
  if (!metadata.hasIosAssociationMetadata) {
    return errors;
  }

  final expectedAssociation = _buildExpectedIosAssociation(metadata);
  if (!_jsonDeepEquals(decoded, expectedAssociation)) {
    errors.add(
      'apple-app-site-association does not match deeplinks/release_metadata.json. Run dart tool/deep_link_release_assets.dart --generate.',
    );
  }

  return errors;
}

List<String> _validateStoreLinkConfig(
  Directory repoRoot,
  _ReleaseMetadata metadata,
) {
  final errors = <String>[];
  final configFile = File(
    '${repoRoot.path}/deeplinks/site/assets/store-links.js',
  );
  if (!configFile.existsSync()) {
    errors.add('deeplinks/site/assets/store-links.js is missing.');
  } else if (configFile.readAsStringSync() !=
      _buildExpectedStoreLinksScript(metadata)) {
    errors.add(
      'deeplinks/site/assets/store-links.js does not match deeplinks/release_metadata.json. Run dart tool/deep_link_release_assets.dart --generate.',
    );
  }

  for (final relativePath in const <String>[
    'deeplinks/site/index.html',
    'deeplinks/site/404.html',
    'deeplinks/site/download-ios/index.html',
  ]) {
    final contents = File('${repoRoot.path}/$relativePath').readAsStringSync();
    if (!contents.contains('/assets/store-links.js')) {
      errors.add('$relativePath must load /assets/store-links.js.');
    }
  }

  final deeplinkScript = File(
    '${repoRoot.path}/deeplinks/site/assets/deeplink.js',
  ).readAsStringSync();
  if (!deeplinkScript.contains('window.COOL_STORE_LINKS')) {
    errors.add(
      'deeplinks/site/assets/deeplink.js must read store links from window.COOL_STORE_LINKS.',
    );
  }

  return errors;
}

List<String> _validateAndroidAssetLinks(
  Directory repoRoot,
  _ReleaseMetadata metadata,
) {
  final errors = <String>[];
  if (!metadata.hasAndroidPlayAppSigningFingerprint) {
    errors.add(
      'deeplinks/release_metadata.json is missing android.playAppSigningSha256CertFingerprint; final Play-distributed app links are not release-ready.',
    );
  }
  final siteFile = File(
    '${repoRoot.path}/deeplinks/site/.well-known/assetlinks.json',
  );
  final hostingFile = File(
    '${repoRoot.path}/hosting/.well-known/assetlinks.json',
  );

  final siteDecoded = _decodeJsonFile(
    siteFile,
    errors,
    'deeplinks assetlinks.json',
  );
  final hostingDecoded = _decodeJsonFile(
    hostingFile,
    errors,
    'hosting assetlinks.json',
  );

  if (siteDecoded is! List || hostingDecoded is! List) {
    return errors;
  }

  final expectedAssetLinks = _buildExpectedAndroidAssetLinks(metadata);
  if (!_jsonDeepEquals(siteDecoded, expectedAssetLinks)) {
    errors.add(
      'deeplinks/site/.well-known/assetlinks.json does not match deeplinks/release_metadata.json. Run dart tool/deep_link_release_assets.dart --generate.',
    );
  }
  if (!_jsonDeepEquals(hostingDecoded, expectedAssetLinks)) {
    errors.add(
      'hosting/.well-known/assetlinks.json does not match deeplinks/release_metadata.json. Run dart tool/deep_link_release_assets.dart --generate.',
    );
  }
  if (!_jsonDeepEquals(siteDecoded, hostingDecoded)) {
    errors.add(
      'deeplinks/site and hosting assetlinks.json must stay identical.',
    );
  }

  final serialized = jsonEncode(siteDecoded);
  if (serialized.contains('REPLACE_WITH_PLAY_APP_SIGNING_SHA256')) {
    errors.add(
      'assetlinks.json still contains REPLACE_WITH_PLAY_APP_SIGNING_SHA256.',
    );
  }

  for (var index = 0; index < siteDecoded.length; index++) {
    final entry = siteDecoded[index];
    if (entry is! Map<String, dynamic>) {
      errors.add('assetlinks.json entry $index must be an object.');
      continue;
    }

    final target = entry['target'];
    if (target is! Map<String, dynamic>) {
      errors.add('assetlinks.json entry $index must include a target object.');
      continue;
    }

    final packageName = _normalizeString(target['package_name']);
    if (packageName == null || packageName.isEmpty) {
      errors.add('assetlinks.json entry $index is missing package_name.');
    }

    final fingerprints = target['sha256_cert_fingerprints'];
    if (fingerprints is! List || fingerprints.isEmpty) {
      errors.add(
        'assetlinks.json entry $index must include sha256_cert_fingerprints.',
      );
      continue;
    }

    for (final fingerprintValue in fingerprints) {
      final fingerprint = _normalizeString(fingerprintValue);
      if (fingerprint == null) {
        errors.add(
          'assetlinks.json entry $index has a blank certificate fingerprint.',
        );
        continue;
      }
      if (_containsPlaceholder(fingerprint)) {
        errors.add(
          'assetlinks.json entry $index still contains a placeholder fingerprint.',
        );
        continue;
      }
      if (!_sha256FingerprintPattern.hasMatch(fingerprint)) {
        errors.add(
          'assetlinks.json entry $index has an invalid SHA-256 fingerprint format: $fingerprint',
        );
      }
    }
  }

  return errors;
}

List<String> _validatePlatformConfig(
  Directory repoRoot,
  _ReleaseMetadata metadata,
) {
  final errors = <String>[];
  final entitlements = File(
    '${repoRoot.path}/ios/Runner/Runner.entitlements',
  ).readAsStringSync();
  for (final host in metadata.hosts) {
    if (!entitlements.contains('applinks:$host')) {
      errors.add('Runner.entitlements must declare applinks:$host.');
    }
  }

  final manifest = File(
    '${repoRoot.path}/android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  if (!manifest.contains('android:autoVerify="true"')) {
    errors.add('AndroidManifest.xml must keep android:autoVerify="true".');
  }
  for (final host in metadata.hosts) {
    if (!manifest.contains('android:host="$host"')) {
      errors.add('AndroidManifest.xml must keep $host app-link host.');
    }
  }

  return errors;
}

_Command _parseCommand(List<String> args) {
  var check = args.isEmpty;
  var generate = false;

  for (final arg in args) {
    switch (arg) {
      case '--check':
        check = true;
        break;
      case '--generate':
        generate = true;
        break;
      default:
        stderr.writeln('Unknown argument: $arg');
        stderr.writeln(
          'Usage: dart tool/deep_link_release_assets.dart [--generate] [--check]',
        );
        exit(64);
    }
  }

  return _Command(check: check, generate: generate);
}

List<String> _iosMetadataErrors(_ReleaseMetadata metadata) {
  final errors = <String>[];
  if (!metadata.hasIosAssociationMetadata) {
    errors.add(
      'deeplinks/release_metadata.json is missing ios.teamId; apple-app-site-association cannot be generated.',
    );
  }
  if (!metadata.hasIosStoreMetadata) {
    errors.add(
      'deeplinks/release_metadata.json is missing ios.appStoreId; iPhone store fallback is not production-ready.',
    );
  }
  return errors;
}

_ReleaseMetadata? _loadReleaseMetadata(
  Directory repoRoot,
  List<String> errors,
) {
  final file = File('${repoRoot.path}/deeplinks/release_metadata.json');
  final decoded = _decodeJsonFile(
    file,
    errors,
    'deeplinks/release_metadata.json',
  );
  if (decoded is! Map<String, dynamic>) {
    return null;
  }

  final hosts = _requireStringList(decoded['hosts'], errors, 'hosts');
  final pathPatterns = _requireStringList(
    decoded['pathPatterns'],
    errors,
    'pathPatterns',
  );
  final android = decoded['android'];
  if (android is! Map<String, dynamic>) {
    errors.add(
      'deeplinks/release_metadata.json must define an android object.',
    );
    return null;
  }

  final packageName = _normalizeString(android['packageName']);
  if (packageName == null) {
    errors.add(
      'deeplinks/release_metadata.json android.packageName must be a non-empty string.',
    );
  }

  final uploadFingerprints = _requireStringList(
    android['uploadSha256CertFingerprints'],
    errors,
    'android.uploadSha256CertFingerprints',
  );
  for (final fingerprint in uploadFingerprints) {
    if (_containsPlaceholder(fingerprint)) {
      errors.add(
        'deeplinks/release_metadata.json contains a placeholder Android upload fingerprint: $fingerprint',
      );
    } else if (!_sha256FingerprintPattern.hasMatch(fingerprint)) {
      errors.add(
        'deeplinks/release_metadata.json has an invalid Android upload SHA-256 fingerprint: $fingerprint',
      );
    }
  }

  final playAppSigningFingerprint = _normalizeString(
    android['playAppSigningSha256CertFingerprint'],
  );
  if (playAppSigningFingerprint != null) {
    if (_containsPlaceholder(playAppSigningFingerprint)) {
      errors.add(
        'deeplinks/release_metadata.json contains a placeholder Android Play signing fingerprint: $playAppSigningFingerprint',
      );
    } else if (!_sha256FingerprintPattern.hasMatch(playAppSigningFingerprint)) {
      errors.add(
        'deeplinks/release_metadata.json has an invalid Android Play signing SHA-256 fingerprint: $playAppSigningFingerprint',
      );
    }
  }

  final ios = decoded['ios'];
  if (ios is! Map<String, dynamic>) {
    errors.add('deeplinks/release_metadata.json must define an ios object.');
    return null;
  }

  final bundleId = _normalizeString(ios['bundleId']);
  if (bundleId == null) {
    errors.add(
      'deeplinks/release_metadata.json ios.bundleId must be a non-empty string.',
    );
  }

  final teamId = _normalizeString(ios['teamId']);
  if (teamId != null && _containsPlaceholder(teamId)) {
    errors.add(
      'deeplinks/release_metadata.json contains a placeholder iOS teamId: $teamId',
    );
  }

  final appStoreId = _normalizeString(ios['appStoreId']);
  if (appStoreId != null &&
      (_containsPlaceholder(appStoreId) ||
          !_numericIdentifierPattern.hasMatch(appStoreId))) {
    errors.add(
      'deeplinks/release_metadata.json ios.appStoreId must be numeric when populated.',
    );
  }

  if (errors.isNotEmpty || packageName == null || bundleId == null) {
    return null;
  }

  return _ReleaseMetadata(
    hosts: hosts,
    pathPatterns: pathPatterns,
    androidPackageName: packageName,
    androidUploadFingerprints: uploadFingerprints,
    androidPlayAppSigningFingerprint: playAppSigningFingerprint,
    iosBundleId: bundleId,
    iosTeamId: teamId,
    iosAppStoreId: appStoreId,
  );
}

List<String> _requireStringList(
  Object? value,
  List<String> errors,
  String label,
) {
  if (value is! List) {
    errors.add('deeplinks/release_metadata.json $label must be a list.');
    return const <String>[];
  }

  final values = value
      .map(_normalizeString)
      .whereType<String>()
      .toList(growable: false);
  if (values.isEmpty || values.length != value.length) {
    errors.add(
      'deeplinks/release_metadata.json $label must contain only non-empty strings.',
    );
  }
  return values;
}

List<Map<String, Object>> _buildExpectedAndroidAssetLinks(
  _ReleaseMetadata metadata,
) {
  return <Map<String, Object>>[
    <String, Object>{
      'relation': const <String>['delegate_permission/common.handle_all_urls'],
      'target': <String, Object>{
        'namespace': 'android_app',
        'package_name': metadata.androidPackageName,
        'sha256_cert_fingerprints': metadata.androidFingerprints,
      },
    },
  ];
}

Map<String, Object> _buildExpectedIosAssociation(_ReleaseMetadata metadata) {
  return <String, Object>{
    'applinks': <String, Object>{
      'apps': const <Object>[],
      'details': <Map<String, Object>>[
        <String, Object>{
          'appID': '${metadata.iosTeamId}.${metadata.iosBundleId}',
          'paths': metadata.pathPatterns,
        },
      ],
    },
  };
}

void _writeJsonFile(File file, Object value) {
  const encoder = JsonEncoder.withIndent('  ');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${encoder.convert(value)}\n');
}

void _writeTextFile(File file, String value) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(value);
}

bool _jsonDeepEquals(Object? left, Object? right) {
  return jsonEncode(_canonicalizeJson(left)) ==
      jsonEncode(_canonicalizeJson(right));
}

Object? _canonicalizeJson(Object? value) {
  if (value is Map) {
    final canonical = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      canonical['${entry.key}'] = _canonicalizeJson(entry.value);
    }
    return canonical;
  }
  if (value is List) {
    return value.map(_canonicalizeJson).toList(growable: false);
  }
  return value;
}

dynamic _decodeJsonFile(File file, List<String> errors, String label) {
  if (!file.existsSync()) {
    errors.add('$label is missing at ${file.path}.');
    return null;
  }

  try {
    return jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    errors.add('$label is not valid JSON: ${error.message}');
    return null;
  }
}

String? _normalizeString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _containsPlaceholder(String value) {
  final upper = value.toUpperCase();
  return upper.contains('TEAMID') ||
      upper.contains('PLACEHOLDER') ||
      upper.contains('REPLACE_WITH') ||
      upper.contains('COM.EXAMPLE') ||
      upper.contains('0000000000');
}

String _buildExpectedStoreLinksScript(_ReleaseMetadata metadata) {
  final appStoreUrl = metadata.appStoreUrl;
  return '''
window.COOL_STORE_LINKS = Object.freeze({
  playStoreUrl: ${jsonEncode(metadata.playStoreUrl)},
  iosFallbackUrl: ${jsonEncode(metadata.iosFallbackUrl)},
  appStoreUrl: ${appStoreUrl == null ? 'null' : jsonEncode(appStoreUrl)}
});
''';
}

final _sha256FingerprintPattern = RegExp(r'^[A-F0-9]{2}(?::[A-F0-9]{2}){31}$');
final _numericIdentifierPattern = RegExp(r'^\d+$');

final class _Command {
  const _Command({required this.check, required this.generate});

  final bool check;
  final bool generate;
}

final class _ReleaseMetadata {
  const _ReleaseMetadata({
    required this.hosts,
    required this.pathPatterns,
    required this.androidPackageName,
    required this.androidUploadFingerprints,
    required this.androidPlayAppSigningFingerprint,
    required this.iosBundleId,
    required this.iosTeamId,
    required this.iosAppStoreId,
  });

  final List<String> hosts;
  final List<String> pathPatterns;
  final String androidPackageName;
  final List<String> androidUploadFingerprints;
  final String? androidPlayAppSigningFingerprint;
  final String iosBundleId;
  final String? iosTeamId;
  final String? iosAppStoreId;

  bool get hasAndroidPlayAppSigningFingerprint =>
      androidPlayAppSigningFingerprint != null;
  bool get hasIosAssociationMetadata => iosTeamId != null;
  bool get hasIosStoreMetadata => iosAppStoreId != null;
  // Older toolchains in this repo choke on the null-aware element syntax here.
  List<String> get androidFingerprints => <String>[
    ...androidUploadFingerprints,
    // ignore: use_null_aware_elements
    if (androidPlayAppSigningFingerprint != null)
      androidPlayAppSigningFingerprint!,
  ];
  String get primaryHost => hosts.first;
  String get playStoreUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackageName';
  String get iosFallbackUrl => 'https://$primaryHost/download-ios/';
  String? get appStoreUrl => hasIosStoreMetadata
      ? 'https://apps.apple.com/app/id$iosAppStoreId'
      : null;
}
