// Native OS captures of the actual app in an isolated synthetic preview.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

Future<void> main() async {
  final adb =
      Platform.environment['ADB'] ??
      '/Volumes/PRO-G40/AppData/android/sdk/platform-tools/adb';
  final serial =
      Platform.environment['COLLECT_STORE_DEVICE'] ?? 'emulator-5562';
  final output = Directory(
    Platform.environment['COLLECT_STORE_SCREENSHOTS'] ??
        '.cache/google-play-submission-20260906/screenshots',
  )..createSync(recursive: true);
  Future<String> android(List<String> args) async {
    final result = await Process.run(adb, ['-s', serial, ...args]);
    if (result.exitCode != 0) {
      throw StateError('${args.first}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  final avd = (await android(['emu', 'avd', 'name'])).split('\n').first.trim();
  if (!serial.startsWith('emulator-') || !avd.startsWith('Collect_')) {
    throw StateError(
      'Store capture is restricted to an isolated Collect emulator.',
    );
  }
  final originalSize = await android(['shell', 'wm', 'size']);
  final originalDensity = await android(['shell', 'wm', 'density']);
  final originalScale = await android([
    'shell',
    'settings',
    'get',
    'system',
    'font_scale',
  ]);
  final cases = <Map<String, dynamic>>[];
  final driver = await FlutterDriver.connect();
  final profiles = {
    'phoneScreenshots': ('1080x1920', '440'),
    'sevenInchScreenshots': ('1200x1920', '240'),
    'tenInchScreenshots': ('1600x2560', '240'),
  };
  final routes = {
    '01-home': '/home',
    '02-groups': '/groups',
    '03-featured-groups': '/groups?filter=featured',
    '04-group': '/groups/qa-private-group',
    '05-contribute': '/groups/qa-private-group/contribute',
    '06-activity': '/activity',
  };
  String? failure;
  try {
    final installed = (await android([
      'shell',
      'pm',
      'path',
      'app.cool.mobile.dev',
    ])).split('package:').last.trim();
    final hash = (await android([
      'shell',
      'sha256sum',
      installed,
    ])).split(RegExp(r'\s+')).first;
    File('${output.path}/installed-artifact.json').writeAsStringSync(
      jsonEncode({
        'package': 'app.cool.mobile.dev',
        'sha256': hash,
        'avd': avd,
        'method': 'Android installed APK sha256sum',
      }),
    );
    await android(['shell', 'settings', 'put', 'system', 'font_scale', '1.0']);
    for (final profile in profiles.entries) {
      await android(['shell', 'wm', 'size', profile.value.$1]);
      await android(['shell', 'wm', 'density', profile.value.$2]);
      final directory = Directory('${output.path}/${profile.key}')
        ..createSync();
      for (final route in routes.entries) {
        final state =
            jsonDecode(
                  await driver.runUnsynchronized(
                    () => driver.requestData(route.key),
                  ),
                )
                as Map<String, dynamic>;
        if (state['route'] != route.value ||
            (state['errors'] as List).isNotEmpty ||
            (state['texts'] as List).isEmpty) {
          throw StateError(
            'Native route validation failed: ${route.key}: $state',
          );
        }
        final capture = await Process.run(adb, [
          '-s',
          serial,
          'exec-out',
          'screencap',
          '-p',
        ], stdoutEncoding: null);
        if (capture.exitCode != 0) throw StateError('Native screencap failed');
        final file = File('${directory.path}/${route.key}.png');
        file.writeAsBytesSync(capture.stdout as List<int>);
        cases.add({
          'profile': profile.key,
          'file': file.path,
          'physical_size': profile.value.$1,
          'density': profile.value.$2,
          ...state,
        });
        stdout.writeln('Captured ${profile.key}/${route.key}');
      }
    }
  } catch (error) {
    failure = '$error';
    rethrow;
  } finally {
    for (final entry in {
      'size': originalSize,
      'density': originalDensity,
    }.entries) {
      final prior = RegExp(
        r'Override (?:size|density): (\S+)',
      ).firstMatch(entry.value)?.group(1);
      await android(['shell', 'wm', entry.key, prior ?? 'reset']);
    }
    await android([
      'shell',
      'settings',
      originalScale == 'null' ? 'delete' : 'put',
      'system',
      'font_scale',
      if (originalScale != 'null') originalScale,
    ]);
    await driver.close();
    File('${output.path}/capture-manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'status': failure == null && cases.length == 18 ? 'pass' : 'fail',
        'failure': failure,
        'captured_at': DateTime.now().toUtc().toIso8601String(),
        'source': 'Android emulator native product capture',
        'boundary':
            'Actual CollectApp and production router/widgets; synthetic repository only. Store imagery, not release-artifact design acceptance.',
        'cases': cases,
      }),
    );
  }
}
