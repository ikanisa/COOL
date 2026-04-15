import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sdk.dart';

void main() {
  late Directory tempRepo;
  late String toolSource;
  late String toolSupportSource;

  setUp(() async {
    toolSource = File(
      '${Directory.current.path}/tool/deep_link_release_assets.dart',
    ).readAsStringSync();
    toolSupportSource = File(
      '${Directory.current.path}/tool/deep_link_release_assets_support.dart',
    ).readAsStringSync();
    tempRepo = await Directory.systemTemp.createTemp(
      'cool_deep_link_release_assets_test_',
    );
    _writeFile(tempRepo, 'tool/deep_link_release_assets.dart', toolSource);
    _writeFile(
      tempRepo,
      'tool/deep_link_release_assets_support.dart',
      toolSupportSource,
    );
  });

  tearDown(() async {
    if (tempRepo.existsSync()) {
      await tempRepo.delete(recursive: true);
    }
  });

  test('generate and check succeed with complete release metadata', () async {
    _writeBaseRepoFiles(
      tempRepo,
      metadata: <String, Object?>{
        'hosts': <String>['cool.app', 'www.cool.app'],
        'pathPatterns': <String>[
          '/basket',
          '/invite/*',
          '/groups',
          '/groups/*',
        ],
        'android': <String, Object?>{
          'packageName': 'app.cool.mobile',
          'uploadSha256CertFingerprints': <String>[
            '9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10',
          ],
          'playAppSigningSha256CertFingerprint':
              'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
        },
        'ios': <String, Object?>{
          'bundleId': 'app.cool.mobile',
          'teamId': 'ABCDE12345',
          'appStoreId': '1234567890',
        },
      },
      appleAssociation: const <String, Object?>{
        'applinks': <String, Object?>{
          'apps': <Object>[],
          'details': <Object>[],
        },
      },
    );

    final result = await _runTool(tempRepo, <String>[
      'tool/deep_link_release_assets.dart',
      '--generate',
      '--check',
    ]);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

    final assetlinks =
        jsonDecode(
              _readFile(tempRepo, 'deeplinks/site/.well-known/assetlinks.json'),
            )
            as List<dynamic>;
    expect(assetlinks, hasLength(1));
    expect(
      ((assetlinks.first as Map<String, dynamic>)['target']
              as Map<String, dynamic>)['sha256_cert_fingerprints']
          as List<dynamic>,
      hasLength(2),
    );

    final storeLinks = _readFile(
      tempRepo,
      'deeplinks/site/assets/store-links.js',
    );
    expect(storeLinks, contains('https://apps.apple.com/app/id1234567890'));

    final association =
        jsonDecode(
              _readFile(
                tempRepo,
                'deeplinks/site/.well-known/apple-app-site-association',
              ),
            )
            as Map<String, dynamic>;
    expect(
      ((((association['applinks'] as Map<String, dynamic>)['details']
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>)['appID'])
          as String,
      'ABCDE12345.app.cool.mobile',
    );
  });

  test(
    'Android-only check fails when Play signing fingerprint is missing',
    () async {
      _writeBaseRepoFiles(
        tempRepo,
        metadata: <String, Object?>{
          'hosts': <String>['cool.app', 'www.cool.app'],
          'pathPatterns': <String>['/basket'],
          'android': <String, Object?>{
            'packageName': 'app.cool.mobile',
            'uploadSha256CertFingerprints': <String>[
              '9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10',
            ],
            'playAppSigningSha256CertFingerprint': '',
          },
          'ios': <String, Object?>{
            'bundleId': 'app.cool.mobile',
            'teamId': '',
            'appStoreId': '',
          },
        },
        appleAssociation: const <String, Object?>{
          'applinks': <String, Object?>{
            'apps': <Object>[],
            'details': <Object>[],
          },
        },
        assetlinks: <Map<String, Object?>>[
          <String, Object?>{
            'relation': <String>['delegate_permission/common.handle_all_urls'],
            'target': <String, Object?>{
              'namespace': 'android_app',
              'package_name': 'app.cool.mobile',
              'sha256_cert_fingerprints': <String>[
                '9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10',
              ],
            },
          },
        ],
      );

      final result = await _runTool(tempRepo, <String>[
        'tool/deep_link_release_assets.dart',
        '--check',
      ]);

      expect(result.exitCode, isNonZero);
      final stderr = '${result.stderr}';
      expect(
        stderr,
        contains('missing android.playAppSigningSha256CertFingerprint'),
      );
    },
  );

  test(
    'Android-only check succeeds when iOS release metadata is omitted',
    () async {
      _writeBaseRepoFiles(
        tempRepo,
        metadata: <String, Object?>{
          'hosts': <String>['cool.app', 'www.cool.app'],
          'pathPatterns': <String>['/basket', '/invite/*'],
          'android': <String, Object?>{
            'packageName': 'app.cool.mobile',
            'uploadSha256CertFingerprints': <String>[
              '9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10',
            ],
            'playAppSigningSha256CertFingerprint':
                'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
          },
          'ios': <String, Object?>{
            'bundleId': 'app.cool.mobile',
            'teamId': '',
            'appStoreId': '',
          },
        },
        appleAssociation: const <String, Object?>{
          'applinks': <String, Object?>{
            'apps': <Object>[],
            'details': <Object>[],
          },
        },
      );

      final result = await _runTool(tempRepo, <String>[
        'tool/deep_link_release_assets.dart',
        '--generate',
        '--check',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      final association =
          jsonDecode(
                _readFile(
                  tempRepo,
                  'deeplinks/site/.well-known/apple-app-site-association',
                ),
              )
              as Map<String, dynamic>;
      expect(
        ((association['applinks'] as Map<String, dynamic>)['details']
                as List<dynamic>)
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'iOS release enforcement reports missing identifiers without disabled AASA noise',
    () async {
      _writeBaseRepoFiles(
        tempRepo,
        metadata: <String, Object?>{
          'hosts': <String>['cool.app', 'www.cool.app'],
          'pathPatterns': <String>['/basket', '/invite/*'],
          'android': <String, Object?>{
            'packageName': 'app.cool.mobile',
            'uploadSha256CertFingerprints': <String>[
              '9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10',
            ],
            'playAppSigningSha256CertFingerprint':
                'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
          },
          'ios': <String, Object?>{
            'bundleId': 'app.cool.mobile',
            'teamId': '',
            'appStoreId': '',
          },
        },
        appleAssociation: const <String, Object?>{
          'applinks': <String, Object?>{
            'apps': <Object>[],
            'details': <Object>[],
          },
        },
      );

      final result = await _runTool(
        tempRepo,
        <String>['tool/deep_link_release_assets.dart', '--generate', '--check'],
        environment: <String, String>{'COOL_REQUIRE_IOS_RELEASE_METADATA': '1'},
      );

      expect(result.exitCode, isNonZero);
      final stderr = '${result.stderr}';
      expect(stderr, contains('missing ios.teamId'));
      expect(stderr, contains('missing ios.appStoreId'));
      expect(
        stderr,
        isNot(contains('must include at least one applinks.details entry')),
      );
    },
  );

  test('env overrides satisfy missing release identifiers', () async {
    _writeBaseRepoFiles(
      tempRepo,
      metadata: <String, Object?>{
        'hosts': <String>['cool.app', 'www.cool.app'],
        'pathPatterns': <String>['/basket', '/invite/*'],
        'android': <String, Object?>{
          'packageName': 'app.cool.mobile',
          'uploadSha256CertFingerprints': <String>[
            '9E:E1:21:72:C7:8A:8A:48:79:06:D9:15:9B:FD:D1:7B:4D:78:AB:A3:54:1F:17:B4:10:65:9E:6D:60:DD:CC:10',
          ],
          'playAppSigningSha256CertFingerprint': '',
        },
        'ios': <String, Object?>{
          'bundleId': 'app.cool.mobile',
          'teamId': '',
          'appStoreId': '',
        },
      },
      appleAssociation: const <String, Object?>{
        'applinks': <String, Object?>{
          'apps': <Object>[],
          'details': <Object>[],
        },
      },
    );

    final result = await _runTool(
      tempRepo,
      <String>['tool/deep_link_release_assets.dart', '--generate', '--check'],
      environment: <String, String>{
        'COOL_ANDROID_PLAY_APP_SIGNING_SHA256_CERT_FINGERPRINT':
            'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
        'COOL_IOS_TEAM_ID': 'ABCDE12345',
        'COOL_IOS_APP_STORE_ID': '1234567890',
        'COOL_REQUIRE_IOS_RELEASE_METADATA': '1',
      },
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

    final association =
        jsonDecode(
              _readFile(
                tempRepo,
                'deeplinks/site/.well-known/apple-app-site-association',
              ),
            )
            as Map<String, dynamic>;
    expect(
      ((((association['applinks'] as Map<String, dynamic>)['details']
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>)['appID'])
          as String,
      'ABCDE12345.app.cool.mobile',
    );

    final assetlinks =
        jsonDecode(
              _readFile(tempRepo, 'deeplinks/site/.well-known/assetlinks.json'),
            )
            as List<dynamic>;
    expect(
      ((assetlinks.first as Map<String, dynamic>)['target']
              as Map<String, dynamic>)['sha256_cert_fingerprints']
          as List<dynamic>,
      contains(
        'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99',
      ),
    );
  });
}

Future<ProcessResult> _runTool(
  Directory repo,
  List<String> args, {
  Map<String, String>? environment,
  String? dartBinary,
}) {
  final bin = dartBinary ?? resolveDartBinary();
  return Process.run(
    bin,
    args,
    workingDirectory: repo.path,
    environment: environment,
  );
}

void _writeBaseRepoFiles(
  Directory repo, {
  required Map<String, Object?> metadata,
  required Map<String, Object?> appleAssociation,
  List<Map<String, Object?>>? assetlinks,
}) {
  _writeJsonFile(repo, 'deeplinks/release_metadata.json', metadata);
  _writeJsonFile(
    repo,
    'deeplinks/site/.well-known/apple-app-site-association',
    appleAssociation,
  );
  if (assetlinks != null) {
    _writeJsonFile(
      repo,
      'deeplinks/site/.well-known/assetlinks.json',
      assetlinks,
    );
    _writeJsonFile(repo, 'hosting/.well-known/assetlinks.json', assetlinks);
  }
  _writeFile(
    repo,
    'deeplinks/site/index.html',
    '<script src="/assets/store-links.js"></script>\n<script src="/assets/deeplink.js"></script>\n',
  );
  _writeFile(
    repo,
    'deeplinks/site/404.html',
    '<script src="/assets/store-links.js"></script>\n<script src="/assets/deeplink.js"></script>\n',
  );
  _writeFile(
    repo,
    'deeplinks/site/download-ios/index.html',
    '<script src="/assets/store-links.js"></script>\n',
  );
  _writeFile(
    repo,
    'deeplinks/site/assets/deeplink.js',
    'window.COOL_STORE_LINKS = window.COOL_STORE_LINKS || {};\n',
  );
  _writeFile(
    repo,
    'deeplinks/site/assets/store-links.js',
    'window.COOL_STORE_LINKS = Object.freeze({});\n',
  );
  _writeFile(repo, 'ios/Runner/Runner.entitlements', '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:cool.app</string>
    <string>applinks:www.cool.app</string>
  </array>
</dict>
</plist>
''');
  _writeFile(repo, 'android/app/src/main/AndroidManifest.xml', '''
<manifest package="app.cool.mobile">
  <application>
    <activity android:name=".MainActivity">
      <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="cool.app" />
        <data android:scheme="https" android:host="www.cool.app" />
      </intent-filter>
    </activity>
  </application>
</manifest>
''');
}

void _writeJsonFile(Directory repo, String relativePath, Object value) {
  const encoder = JsonEncoder.withIndent('  ');
  _writeFile(repo, relativePath, '${encoder.convert(value)}\n');
}

void _writeFile(Directory repo, String relativePath, String contents) {
  final file = File('${repo.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String _readFile(Directory repo, String relativePath) {
  return File('${repo.path}/$relativePath').readAsStringSync();
}
