part of 'deep_link_release_assets.dart';

_ReleaseMetadata? _loadReleaseMetadata(
  Directory repoRoot,
  List<String> errors,
  _ReleaseMetadataOverrides overrides,
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

  final playAppSigningFingerprint =
      overrides.androidPlayAppSigningFingerprint ??
      _normalizeString(android['playAppSigningSha256CertFingerprint']);
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

  final teamId = overrides.iosTeamId ?? _normalizeString(ios['teamId']);
  if (teamId != null && _containsPlaceholder(teamId)) {
    errors.add(
      'deeplinks/release_metadata.json contains a placeholder iOS teamId: $teamId',
    );
  }

  final appStoreId =
      overrides.iosAppStoreId ?? _normalizeString(ios['appStoreId']);
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

_ReleaseMetadataOverrides _loadReleaseMetadataOverrides(Directory repoRoot) {
  final values = <String, String>{
    ..._loadDotEnvFile(File('${repoRoot.path}/.env')),
    ..._loadDotEnvJsonFile(File('${repoRoot.path}/.env.json')),
    ...Platform.environment,
  };

  return _ReleaseMetadataOverrides(
    androidPlayAppSigningFingerprint: _readFirstEnvValue(values, const <String>[
      'COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT',
      'ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT',
    ]),
    iosTeamId: _readFirstEnvValue(values, const <String>[
      'COOL_IOS_TEAM_ID',
      'IOS_TEAM_ID',
    ]),
    iosAppStoreId: _readFirstEnvValue(values, const <String>[
      'COOL_IOS_APP_STORE_ID',
      'IOS_APP_STORE_ID',
    ]),
  );
}

Map<String, String> _loadDotEnvFile(File file) {
  if (!file.existsSync()) {
    return const <String, String>{};
  }

  final values = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }

    final separatorIndex = line.indexOf('=');
    final key = line.substring(0, separatorIndex).trim();
    final value = line
        .substring(separatorIndex + 1)
        .trim()
        .replaceAll(RegExp("^['\"]|['\"]\$"), '');
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    values[key] = value;
  }

  return values;
}

Map<String, String> _loadDotEnvJsonFile(File file) {
  if (!file.existsSync()) {
    return const <String, String>{};
  }

  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return const <String, String>{};
    }

    final values = <String, String>{};
    for (final entry in decoded.entries) {
      final value = '${entry.value}'.trim();
      if (entry.key.trim().isEmpty || value.isEmpty || value == 'null') {
        continue;
      }
      values[entry.key] = value;
    }
    return values;
  } on FormatException {
    return const <String, String>{};
  }
}

String? _readFirstEnvValue(Map<String, String> values, List<String> keys) {
  for (final key in keys) {
    final value = _normalizeString(values[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
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

final class _ReleaseMetadataOverrides {
  const _ReleaseMetadataOverrides({
    required this.androidPlayAppSigningFingerprint,
    required this.iosTeamId,
    required this.iosAppStoreId,
  });

  final String? androidPlayAppSigningFingerprint;
  final String? iosTeamId;
  final String? iosAppStoreId;
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
