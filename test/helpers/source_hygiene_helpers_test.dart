import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'android_manifest_permissions.dart';
import 'repository_source_files.dart';

Uint8List _metadata({int entryId = 9}) {
  final bytes = Uint8List(70);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x00051607);
  data.setUint32(4, 0x00020000);
  data.setUint16(24, 1);
  data.setUint32(26, entryId);
  data.setUint32(30, 38);
  data.setUint32(34, 32);
  return bytes;
}

void main() {
  late Directory temporary;
  late File metadata;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('collect_metadata_scan_');
    File(
      '${temporary.path}/ci.yml',
    ).writeAsStringSync('name: Active workflow\n');
    metadata = File('${temporary.path}/._ci.yml');
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'bounded AppleDouble FinderInfo with ordinary paired source is metadata',
    () {
      metadata.writeAsBytesSync(_metadata());
      expect(isVerifiedAppleDoubleMetadata(metadata), isTrue);
    },
  );

  test('hidden-looking YAML remains an active security scan input', () {
    metadata.writeAsStringSync('steps:\n  - uses: actions/checkout@main\n');
    expect(isVerifiedAppleDoubleMetadata(metadata), isFalse);
    expect(metadata.readAsStringSync(), contains('actions/checkout@main'));
  });

  test('binary magic with an out-of-bounds entry does not bypass scans', () {
    final bytes = _metadata();
    ByteData.sublistView(bytes).setUint32(30, bytes.length + 1);
    metadata.writeAsBytesSync(bytes);
    expect(isVerifiedAppleDoubleMetadata(metadata), isFalse);
  });

  test('unclaimed appended text cannot hide inside a metadata exemption', () {
    metadata.writeAsBytesSync([
      ..._metadata(),
      ...'unsafe active text'.codeUnits,
    ]);
    expect(isVerifiedAppleDoubleMetadata(metadata), isFalse);
  });

  test('data-fork content is not accepted as metadata', () {
    metadata.writeAsBytesSync(_metadata(entryId: 1));
    expect(isVerifiedAppleDoubleMetadata(metadata), isFalse);
  });

  test('unpaired or symbolic-link sidecars remain scan inputs', () {
    metadata.writeAsBytesSync(_metadata());
    File('${temporary.path}/ci.yml').deleteSync();
    expect(isVerifiedAppleDoubleMetadata(metadata), isFalse);
    final target = File('${temporary.path}/target')
      ..writeAsBytesSync(_metadata());
    metadata.deleteSync();
    Link(metadata.path).createSync(target.path);
    expect(isVerifiedAppleDoubleMetadata(metadata), isFalse);
  });

  const android = 'http://schemas.android.com/apk/res/android';
  const tools = 'http://schemas.android.com/tools';
  test('real XML removal markers cannot request restricted permissions', () {
    const manifest = '''<manifest xmlns:android="$android" xmlns:tools="$tools">
      <uses-permission tools:node="remove" android:name="android.permission.READ_SMS"/>
      <uses-permission android:name="android.permission.RECEIVE_SMS"/>
      <!-- <uses-permission android:name="android.permission.SEND_SMS"/> -->
    </manifest>''';
    expect(requestedAndroidPermissions(manifest), {
      'android.permission.RECEIVE_SMS',
    });
    expect(removedAndroidPermissions(manifest), {
      'android.permission.READ_SMS',
    });
  });

  test(
    'lookalike tools namespace cannot disguise an active restricted grant',
    () {
      const manifest =
          '''<manifest xmlns:android="$android" xmlns:tools="https://invalid.example/tools">
      <uses-permission android:name="android.permission.READ_SMS" tools:node="remove"/>
    </manifest>''';
      expect(requestedAndroidPermissions(manifest), {
        'android.permission.READ_SMS',
      });
      expect(removedAndroidPermissions(manifest), isEmpty);
    },
  );

  test('SDK-scoped declarations remain active permission inputs', () {
    const manifest = '''<manifest xmlns:android="$android">
      <uses-permission-sdk-23 android:name="android.permission.READ_SMS"/>
    </manifest>''';
    expect(requestedAndroidPermissions(manifest), {
      'android.permission.READ_SMS',
    });
  });
}
