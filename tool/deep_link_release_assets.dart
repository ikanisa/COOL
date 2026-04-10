import 'dart:collection';
import 'dart:convert';
import 'dart:io';

part 'deep_link_release_assets_support.dart';

void main(List<String> args) {
  final command = _parseCommand(args);
  final repoRoot = Directory.current;
  final overrides = _loadReleaseMetadataOverrides(repoRoot);
  final metadataErrors = <String>[];
  final metadata = _loadReleaseMetadata(repoRoot, metadataErrors, overrides);

  if (command.generate && metadata != null) {
    final warnings = _generateReleaseAssets(repoRoot, metadata);
    for (final warning in warnings) {
      stderr.writeln('warning: $warning');
    }
  }

  final errors = <String>[
    ...metadataErrors,
    if (metadata != null && metadata.shouldValidateIosRelease)
      ..._validateIosAssociation(repoRoot, metadata),
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
      'Skipped apple-app-site-association generation because resolved release metadata is missing ios.teamId.',
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
      'apple-app-site-association does not match the resolved release metadata. Run dart tool/deep_link_release_assets.dart --generate.',
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
      'deeplinks/site/assets/store-links.js does not match the resolved release metadata. Run dart tool/deep_link_release_assets.dart --generate.',
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
      'Resolved release metadata is missing android.playAppSigningSha256CertFingerprint; set COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT or populate deeplinks/release_metadata.json.',
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
      'deeplinks/site/.well-known/assetlinks.json does not match the resolved release metadata. Run dart tool/deep_link_release_assets.dart --generate.',
    );
  }
  if (!_jsonDeepEquals(hostingDecoded, expectedAssetLinks)) {
    errors.add(
      'hosting/.well-known/assetlinks.json does not match the resolved release metadata. Run dart tool/deep_link_release_assets.dart --generate.',
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
  if (!metadata.shouldValidateIosRelease) {
    return const <String>[];
  }
  final errors = <String>[];
  if (!metadata.hasIosAssociationMetadata) {
    errors.add(
      'Resolved release metadata is missing ios.teamId; set COOL_IOS_TEAM_ID or populate deeplinks/release_metadata.json.',
    );
  }
  if (!metadata.hasIosStoreMetadata) {
    errors.add(
      'Resolved release metadata is missing ios.appStoreId; set COOL_IOS_APP_STORE_ID or populate deeplinks/release_metadata.json.',
    );
  }
  return errors;
}
