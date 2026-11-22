// QA-only route/geometry bridge. All focus and text input use native UI input.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

const _device = '0AB2E24E-010E-44E6-ADD8-1459F507CA3F';
const _deviceName = 'Collect Complete Design QA 20260905';
const _commands = {'open', 'inspect', 'reveal-field', 'reveal-action'};

Future<void> main() async {
  final inventory = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    '--json',
  ]);
  if (inventory.exitCode != 0) throw StateError('Simulator inventory failed');
  final devices = (jsonDecode(inventory.stdout as String)['devices'] as Map)
      .values
      .expand((items) => items as List);
  if (!devices.any(
    (device) =>
        device['udid'] == _device &&
        device['name'] == _deviceName &&
        device['state'] == 'Booted',
  )) {
    throw StateError('The designated disposable Collect simulator is required');
  }
  final output = Directory(
    Platform.environment['COLLECT_IOS_KEYBOARD_EVIDENCE_DIR']!,
  )..createSync(recursive: true);
  final driver = await FlutterDriver.connect();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final commands = File('${output.path}/commands.jsonl');
  final control = File('${output.path}/control.json');
  await control.writeAsString(
    jsonEncode({
      'status': 'running',
      'url': 'http://127.0.0.1:${server.port}',
      'device': _device,
      'input_emulation': false,
      'scope': 'Synthetic fixture navigation and read-only geometry',
    }),
  );
  stdout.writeln('collect_ios_keyboard:ready');
  try {
    await for (final request in server) {
      request.response.headers.contentType = ContentType.json;
      try {
        if (request.method == 'POST' && request.uri.path == '/finish') {
          request.response.write(jsonEncode({'status': 'stopped'}));
          await request.response.close();
          break;
        }
        if (request.method != 'POST' || request.uri.path != '/command') {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'error': 'Unknown fixture path'}));
          await request.response.close();
          continue;
        }
        final payload = await utf8.decoder.bind(request).join();
        if (payload.length > 8192) {
          throw ArgumentError('Fixture request too large');
        }
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        if (!_commands.contains(decoded['command'])) {
          throw ArgumentError('Unsupported fixture command');
        }
        final response = await driver.runUnsynchronized(
          () =>
              driver.requestData(payload, timeout: const Duration(seconds: 45)),
        );
        await commands.writeAsString(
          '${jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'request': decoded, 'response': jsonDecode(response)})}\n',
          mode: FileMode.append,
        );
        request.response.write(response);
      } catch (error) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write(jsonEncode({'error': '$error'}));
      }
      await request.response.close();
    }
  } finally {
    await server.close(force: true);
    await driver.close();
    await control.writeAsString(
      jsonEncode({
        'status': 'stopped',
        'device': _device,
        'input_emulation': false,
      }),
    );
  }
}
