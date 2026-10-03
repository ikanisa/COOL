import 'dart:io';

const _configuredCaptureRoot = String.fromEnvironment('COLLECT_TEST_CAPTURE_DIR');
const _captureNames = <String>{
  'settings-dark.png',
  'settings-large-light.png',
  'investigation-sdk-light-synthetic.png',
  'investigation-sdk-dark-synthetic.png',
  'overview-light-synthetic.png',
  'overview-dark-synthetic.png',
  'feature-revoked.png',
  'roster-page-2-light.png',
  'uncertain-submission.png',
  'roster-compact-2x-errors.png',
};
late final Directory _captureDirectory = _createCaptureDirectory();

// Normal tests use a new system temporary directory owned by this isolate.
// Explicit capture runs may supply an existing absolute output directory.
File collectTestCaptureFile(String name) {
  if (!_captureNames.contains(name)) {
    throw ArgumentError.value(name, 'name', 'Unknown test capture filename');
  }
  final file = File.fromUri(_captureDirectory.uri.resolve(name));
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
    throw FileSystemException('Capture target must be a regular file', file.path);
  }
  return file;
}

Directory _createCaptureDirectory() {
  if (_configuredCaptureRoot.isEmpty) {
    final directory = Directory.systemTemp.createTempSync('collect-test-captures-');
    return Directory(directory.resolveSymbolicLinksSync());
  }
  final directory = Directory(_configuredCaptureRoot);
  if (!directory.isAbsolute || !directory.existsSync()) {
    throw ArgumentError.value(
      _configuredCaptureRoot,
      'COLLECT_TEST_CAPTURE_DIR',
      'Capture directory must be an existing absolute directory',
    );
  }
  return Directory(directory.resolveSymbolicLinksSync());
}
