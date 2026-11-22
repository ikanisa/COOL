import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(onScreenshot: _saveScreenshot);

Future<bool> _saveScreenshot(
  String name,
  List<int> image, [
  Map<String, Object?>? args,
]) async {
  final outputDir = Platform.environment['INTEGRATION_SCREENSHOT_DIR'];
  if (outputDir == null || outputDir.isEmpty) return true;

  final directory = Directory(outputDir)..createSync(recursive: true);
  final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
  final file = File('${directory.path}/$safeName.png');
  await file.writeAsBytes(image, flush: true);
  final item = <String, Object?>{
    'status': 'pass',
    'name': name,
    'path': file.uri.pathSegments.last,
    'bytes': image.length,
  };
  await File(
    '${directory.path}/screenshots.jsonl',
  ).writeAsString('${jsonEncode(item)}\n', mode: FileMode.append, flush: true);
  return image.length > 8000;
}
