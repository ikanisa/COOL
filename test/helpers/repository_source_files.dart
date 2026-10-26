import 'dart:io';
import 'dart:typed_data';

/// Recognizes observed macOS AppleDouble metadata without trusting a filename.
///
/// The binary header and bounded entry table follow the repository's existing
/// scripts/qa/collect_ci_policy.py check. This text-scan adapter is deliberately
/// narrower: it also requires an ordinary paired source file, FinderInfo and
/// optional resource-fork entries, and no unclaimed bytes or symbolic links.
/// Text, malformed containers and unpaired ._ files remain normal scan inputs.
bool isVerifiedAppleDoubleMetadata(File file) {
  final name = file.uri.pathSegments.last;
  if (!name.startsWith('._') ||
      FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
    return false;
  }
  final companion = File.fromUri(file.uri.resolve(name.substring(2)));
  if (FileSystemEntity.typeSync(companion.path, followLinks: false) !=
      FileSystemEntityType.file) {
    return false;
  }
  try {
    if (file.lengthSync() > 16 * 1024 * 1024) return false;
    final bytes = file.readAsBytesSync();
    if (bytes.length < 26) return false;
    final data = ByteData.sublistView(bytes);
    final count = data.getUint16(24);
    final tableEnd = 26 + count * 12;
    if (data.getUint32(0) != 0x00051607 ||
        data.getUint32(4) != 0x00020000 ||
        count < 1 ||
        count > 2 ||
        tableEnd > bytes.length) {
      return false;
    }
    final ids = <int>{};
    final spans = <({int start, int end})>[];
    for (var index = 0; index < count; index++) {
      final entry = 26 + index * 12;
      final id = data.getUint32(entry);
      final offset = data.getUint32(entry + 4);
      final length = data.getUint32(entry + 8);
      if (!const {2, 9}.contains(id) ||
          !ids.add(id) ||
          offset < tableEnd ||
          offset + length > bytes.length ||
          (id == 9 && length < 32)) {
        return false;
      }
      spans.add((start: offset, end: offset + length));
    }
    if (!ids.contains(9)) return false;
    spans.sort((left, right) => left.start.compareTo(right.start));
    var end = tableEnd;
    for (final span in spans) {
      if (span.start != end) return false;
      end = span.end;
    }
    return end == bytes.length;
  } on FileSystemException {
    return false;
  } on RangeError {
    return false;
  }
}
