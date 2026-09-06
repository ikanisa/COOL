// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'package:flutter_driver/flutter_driver.dart';

const device = '0AB2E24E-010E-44E6-ADD8-1459F507CA3F';

Future<void> main() async {
  final inventory = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    '--json',
  ]);
  final devices = (jsonDecode(inventory.stdout as String)['devices'] as Map)
      .values
      .expand((v) => v as List);
  if (!devices.any(
    (d) =>
        d['udid'] == device &&
        d['state'] == 'Booted' &&
        d['name'] == 'Collect Complete Design QA 20260905',
  )) {
    throw StateError('Only the Collect disposable iPhone is permitted');
  }
  final output = Directory(Platform.environment['COLLECT_NAV_EVIDENCE_DIR']!)
    ..createSync(recursive: true);
  final driver = await FlutterDriver.connect();
  final rows = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> command(Map<String, Object> request) async =>
      jsonDecode(
            await driver.runUnsynchronized(
              () => driver.requestData(
                jsonEncode(request),
                timeout: const Duration(seconds: 45),
              ),
            ),
          )
          as Map<String, dynamic>;
  try {
    for (final theme in ['light', 'dark']) {
      for (final scale in [1, 2]) {
        await command({'command': 'open', 'theme': theme, 'scale': scale});
        for (final target in [
          'home',
          'groups',
          'activity',
          'profile',
          'profile-edit',
        ]) {
          if (target == 'profile-edit') {
            await command({'command': 'profile'});
          } else {
            await driver.runUnsynchronized(
              () => driver.tap(find.byValueKey('collect-nav-$target')),
            );
          }
          final name = '$theme-$scale-$target';
          final state = await command({'command': 'inspect'});
          if ((state['errors'] as List).isNotEmpty) {
            throw StateError('${state['errors']}');
          }
          final expected = target == 'profile'
              ? '/settings'
              : target == 'profile-edit'
              ? '/settings/profile'
              : '/$target';
          if (state['route'] != expected) {
            throw StateError('Wrong navigation: ${state['route']}');
          }
          // CoreSimulator writes in /tmp because its service cannot write to the external volume.
          final temporary = File('/tmp/collect-nav-$name.png');
          final os = await Process.run('xcrun', [
            'simctl',
            'io',
            device,
            'screenshot',
            temporary.path,
          ]);
          if (os.exitCode != 0) throw StateError('${os.stderr}');
          await temporary.copy('${output.path}/$name-os.png');
          await temporary.delete();
          final snapshot = await command({'command': 'snapshot', 'name': name});
          await File(
            '${output.path}/$name-uikit.png',
          ).writeAsBytes(base64Decode(snapshot.remove('png') as String));
          await File(
            '${output.path}/$name-engine.png',
          ).writeAsBytes(await driver.screenshot());
          rows.add({'name': name, 'theme': theme, 'scale': scale, ...state});
          await File('${output.path}/report.json').writeAsString(
            const JsonEncoder.withIndent(
              '  ',
            ).convert({'status': 'running', 'results': rows}),
          );
          stdout.writeln('collect_native_navigation:pass:$name');
        }
      }
    }
    await File('${output.path}/report.json').writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'status': 'pass', 'results': rows}),
    );
  } finally {
    await driver.close();
  }
}
