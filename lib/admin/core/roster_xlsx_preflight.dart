import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml_events.dart';

/// Engineering limits for the 5 MiB / 500-member roster preview, not an
/// account quota or an approval of production resource budgets.
const rosterXlsxMaxBytes = 5 * 1024 * 1024;
const rosterXlsxMaxExpandedBytes = 8 * 1024 * 1024;
const rosterXlsxMaxEntryBytes = 2 * 1024 * 1024;
const rosterXlsxMaxEntries = 64;
const rosterXlsxMaxSheets = 10;
const rosterXlsxMaxColumns = 32;
const rosterXlsxMaxRows = 501; // One header plus 500 members.
const _maxCells = (500 + rosterXlsxMaxSheets) * rosterXlsxMaxColumns;
const _invalid = 'The XLSX file is malformed or uses unsupported features.';
const _limit = 'The XLSX file exceeds safe roster import limits.';

class _RosterXlsxError extends StateError {
  _RosterXlsxError(super.message);
}

Never _reject([String message = _invalid]) => throw _RosterXlsxError(message);

/// Validates metadata before inflation, caps actual output independently of ZIP
/// size claims, and examines XML lazily before Excel builds any document/sheet.
/// Only canonical stored entries are returned: Excel never re-inflates the
/// untrusted compressed stream with a different (potentially native) decoder.
List<int> preflightRosterXlsx(List<int> source) {
  if (source.length > rosterXlsxMaxBytes) _reject(_limit);
  if (source.length < 22) _reject();
  try {
    final bytes = Uint8List.fromList(source);
    final entries = _ZipIndex(bytes).read();
    final archive = Archive();
    final inflateWork = _InflateWork();
    final xml = _WorkbookBounds(entries.map((e) => e.name).toSet());
    for (final entry in entries) {
      final compressed = Uint8List.sublistView(
        bytes,
        entry.dataOffset,
        entry.dataOffset + entry.compressedSize,
      );
      final Uint8List content;
      if (entry.method == 0) {
        content = compressed;
      } else {
        _DeflateBounds(compressed, entry.expandedSize, inflateWork).validate();
        // Inflate.stream writes incrementally. Do not use ZipDecoder.content,
        // Inflate(bytes), or the platform inflateBuffer, which allocate first.
        final output = _CappedInflateOutput(entry.expandedSize);
        final input = InputStream(compressed);
        Inflate.stream(input, output);
        if (input.position != compressed.length) _reject();
        content = output.bytes;
      }
      if (content.length != entry.expandedSize ||
          getCrc32(content) != entry.crc) {
        _reject();
      }
      if (entry.name.endsWith('.xml') || entry.name.endsWith('.rels')) {
        xml.inspect(entry.name, content);
      }
      archive.addFile(
        ArchiveFile(entry.name, content.length, content)..compress = false,
      );
    }
    xml.finish();
    return ZipEncoder().encode(archive)!;
  } on _RosterXlsxError {
    rethrow;
  } catch (_) {
    // No parser internals, archive contents, or raw member data in UI errors.
    _reject();
  }
}

class _ZipEntry {
  _ZipEntry(
    this.name,
    this.method,
    this.crc,
    this.compressedSize,
    this.expandedSize,
    this.localOffset,
    this.flags,
  );
  final String name;
  final int method, crc, compressedSize, expandedSize, localOffset, flags;
  int dataOffset = 0;
}

class _ZipIndex {
  _ZipIndex(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);

  List<_ZipEntry> read() {
    var end = bytes.length - 22;
    final floor = (end - 65535).clamp(0, end);
    while (end >= floor &&
        !(u32(end) == 0x06054b50 && end + 22 + u16(end + 20) == bytes.length)) {
      end--;
    }
    if (end < floor || u16(end + 4) != 0 || u16(end + 6) != 0) _reject();
    final count = u16(end + 10);
    final directorySize = u32(end + 12);
    final directoryOffset = u32(end + 16);
    if (count == 0 || count > rosterXlsxMaxEntries) _reject(_limit);
    if (u16(end + 8) != count || directoryOffset + directorySize != end) {
      _reject();
    }
    final entries = <_ZipEntry>[];
    final names = <String>{};
    var cursor = directoryOffset;
    var expanded = 0;
    for (var i = 0; i < count; i++) {
      if (cursor + 46 > end || u32(cursor) != 0x02014b50) _reject();
      final flags = u16(cursor + 8);
      final method = u16(cursor + 10);
      final compressedSize = u32(cursor + 20);
      final expandedSize = u32(cursor + 24);
      final nameLength = u16(cursor + 28);
      final extraLength = u16(cursor + 30);
      final commentLength = u16(cursor + 32);
      final next = cursor + 46 + nameLength + extraLength + commentLength;
      // Only store/deflate, standard compression options, descriptors and UTF-8.
      // Reject encryption, patched data, ZIP64, symlinks and special files.
      final fileType = (u32(cursor + 38) >> 16) & 0xf000;
      if (next > end ||
          u16(cursor + 6) > 20 ||
          u16(cursor + 34) != 0 ||
          (flags & ~0x080e) != 0 ||
          (method != 0 && method != 8) ||
          (method == 0 && (flags & 6) != 0) ||
          (fileType != 0 && fileType != 0x8000 && fileType != 0x4000)) {
        _reject();
      }
      if (compressedSize > rosterXlsxMaxBytes ||
          expandedSize > rosterXlsxMaxEntryBytes ||
          (expanded += expandedSize) > rosterXlsxMaxExpandedBytes ||
          expandedSize > 200 * compressedSize + 4096) {
        _reject(_limit);
      }
      if (method == 0 && compressedSize != expandedSize) _reject();
      if (nameLength == 0 || nameLength > 240) _reject();
      final name = utf8.decode(
        Uint8List.sublistView(bytes, cursor + 46, cursor + 46 + nameLength),
      );
      _safePath(name, allowDirectory: true);
      if (!names.add(name.toLowerCase())) _reject();
      if (name.endsWith('/') && (expandedSize != 0 || fileType == 0x8000)) {
        _reject();
      }
      _extras(cursor + 46 + nameLength, extraLength);
      entries.add(
        _ZipEntry(
          name,
          method,
          u32(cursor + 16),
          compressedSize,
          expandedSize,
          u32(cursor + 42),
          flags,
        ),
      );
      cursor = next;
    }
    if (cursor != end) _reject();
    entries.sort((a, b) => a.localOffset.compareTo(b.localOffset));
    var expectedOffset = 0;
    for (final entry in entries) {
      final start = entry.localOffset;
      if (start != expectedOffset ||
          start + 30 > directoryOffset ||
          u32(start) != 0x04034b50 ||
          u16(start + 4) > 20 ||
          u16(start + 6) != entry.flags ||
          u16(start + 8) != entry.method) {
        _reject();
      }
      final nameLength = u16(start + 26);
      final extraLength = u16(start + 28);
      final contentStart = start + 30 + nameLength + extraLength;
      if (contentStart + entry.compressedSize > directoryOffset) _reject();
      if (utf8.decode(
            Uint8List.sublistView(bytes, start + 30, start + 30 + nameLength),
          ) !=
          entry.name) {
        _reject();
      }
      _extras(start + 30 + nameLength, extraLength);
      final descriptor = (entry.flags & 8) != 0;
      if (descriptor) {
        if ((u32(start + 14) != 0 && u32(start + 14) != entry.crc) ||
            (u32(start + 18) != 0 && u32(start + 18) != entry.compressedSize) ||
            (u32(start + 22) != 0 && u32(start + 22) != entry.expandedSize)) {
          _reject();
        }
      } else if (u32(start + 14) != entry.crc ||
          u32(start + 18) != entry.compressedSize ||
          u32(start + 22) != entry.expandedSize) {
        _reject();
      }
      entry.dataOffset = contentStart;
      expectedOffset = contentStart + entry.compressedSize;
      if (descriptor) {
        if (expectedOffset + 12 > directoryOffset) _reject();
        if (u32(expectedOffset) == 0x08074b50) expectedOffset += 4;
        if (expectedOffset + 12 > directoryOffset ||
            u32(expectedOffset) != entry.crc ||
            u32(expectedOffset + 4) != entry.compressedSize ||
            u32(expectedOffset + 8) != entry.expandedSize) {
          _reject();
        }
        expectedOffset += 12;
      }
    }
    if (expectedOffset != directoryOffset) _reject();
    return entries;
  }

  void _extras(int start, int length) {
    final end = start + length;
    while (start < end) {
      if (start + 4 > end) _reject();
      final id = u16(start);
      // ZIP64 / AES / Unicode path overrides create alternate interpretations.
      if (id == 1 || id == 0x9901 || id == 0x7075) _reject();
      start += 4 + u16(start + 2);
    }
    if (start != end) _reject();
  }
}

void _safePath(String name, {bool allowDirectory = false}) {
  if (name.isEmpty ||
      name.length > 240 ||
      name.startsWith('/') ||
      RegExp(r'[\\\x00-\x20\x7f:%?#]').hasMatch(name)) {
    _reject();
  }
  final parts = name.split('/');
  if (allowDirectory && parts.last.isEmpty) parts.removeLast();
  if (parts.any((p) => p.isEmpty || p == '.' || p == '..')) _reject();
}

void _relationshipPath(String path, String target) {
  // OPC relationships may refer to a parent within the package (for example
  // worksheets -> drawings). They may never escape the package or use a URL.
  if (RegExp(r'[\\\x00-\x20\x7f:%?#]').hasMatch(target)) _reject();
  final parts = <String>[];
  if (!target.startsWith('/')) {
    parts.addAll(path.split('/')..removeLast());
  }
  if (parts.isNotEmpty && parts.last == '_rels') parts.removeLast();
  for (final part in target.replaceFirst(RegExp(r'^/'), '').split('/')) {
    if (part == '..') {
      if (parts.isEmpty) _reject();
      parts.removeLast();
    } else if (part != '.') {
      if (part.isEmpty) _reject();
      parts.add(part);
    }
  }
  _safePath(parts.join('/'));
}

/// RFC 1951 structure/output-length validation. archive 3.6.1's inflater does
/// not report every truncated/invalid terminal block; validate the bit stream
/// first, without constructing the expanded output. CRC is checked separately.
/// Format reference: https://www.rfc-editor.org/rfc/rfc1951
class _DeflateBounds {
  _DeflateBounds(this.bytes, this.expected, this.work);
  final Uint8List bytes;
  final int expected;
  final _InflateWork work;
  int bit = 0, produced = 0;
  int bits(int count) {
    if (bit + count > bytes.length * 8) _reject();
    var result = 0;
    for (var i = 0; i < count; i++, bit++) {
      result |= ((bytes[bit >> 3] >> (bit & 7)) & 1) << i;
    }
    return result;
  }

  void grow(int count) {
    produced += count;
    if (produced > expected) _reject(_limit);
  }

  void validate() {
    var blocks = 0;
    bool last;
    do {
      // Empty blocks can consume CPU without increasing the byte budget.
      if (++blocks > 256 || ++work.blocks > 4096) _reject(_limit);
      last = bits(1) == 1;
      final type = bits(2);
      if (type == 0) {
        bit = (bit + 7) & ~7;
        final length = bits(16);
        if ((length ^ bits(16)) != 0xffff) _reject();
        grow(length);
        if (bit + length * 8 > bytes.length * 8) _reject();
        bit += length * 8;
        continue;
      }
      if (type == 3) _reject();
      final _Huffman literal, distance;
      if (type == 1) {
        literal = _Huffman(
          List.generate(
            288,
            (i) => i < 144
                ? 8
                : i < 256
                ? 9
                : i < 280
                ? 7
                : 8,
          ),
        );
        distance = _Huffman(List.filled(32, 5));
      } else {
        final literalCount = bits(5) + 257;
        final distanceCount = bits(5) + 1;
        final codeCount = bits(4) + 4;
        if (literalCount > 286) _reject();
        const order = [
          16,
          17,
          18,
          0,
          8,
          7,
          9,
          6,
          10,
          5,
          11,
          4,
          12,
          3,
          13,
          2,
          14,
          1,
          15,
        ];
        final codes = List.filled(19, 0);
        for (var i = 0; i < codeCount; i++) {
          codes[order[i]] = bits(3);
        }
        final tree = _Huffman(codes, requireComplete: true);
        final lengths = <int>[];
        final total = literalCount + distanceCount;
        while (lengths.length < total) {
          final code = tree.read(this);
          if (code < 16) {
            lengths.add(code);
          } else {
            if (code == 16 && lengths.isEmpty) _reject();
            final repeat = code == 16
                ? bits(2) + 3
                : code == 17
                ? bits(3) + 3
                : bits(7) + 11;
            if (lengths.length + repeat > total) _reject();
            lengths.addAll(List.filled(repeat, code == 16 ? lengths.last : 0));
          }
        }
        if (lengths[256] == 0) _reject();
        literal = _Huffman(lengths.sublist(0, literalCount));
        distance = _Huffman(lengths.sublist(literalCount), allowEmpty: true);
      }
      while (true) {
        final code = literal.read(this);
        if (code < 256) {
          grow(1);
          continue;
        }
        if (code == 256) break;
        if (code > 285) _reject();
        final index = code - 257;
        final length = _lengthBase[index] + bits(_lengthExtra[index]);
        final d = distance.read(this);
        if (d > 29) _reject();
        final offset = _distanceBase[d] + bits(_distanceExtra[d]);
        if (offset > produced) _reject();
        grow(length);
      }
    } while (!last);
    if (produced != expected || (bit + 7) ~/ 8 != bytes.length) _reject();
  }

  static const _lengthBase = [
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    13,
    15,
    17,
    19,
    23,
    27,
    31,
    35,
    43,
    51,
    59,
    67,
    83,
    99,
    115,
    131,
    163,
    195,
    227,
    258,
  ];
  static const _lengthExtra = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    4,
    4,
    4,
    4,
    5,
    5,
    5,
    5,
    0,
  ];
  static const _distanceBase = [
    1,
    2,
    3,
    4,
    5,
    7,
    9,
    13,
    17,
    25,
    33,
    49,
    65,
    97,
    129,
    193,
    257,
    385,
    513,
    769,
    1025,
    1537,
    2049,
    3073,
    4097,
    6145,
    8193,
    12289,
    16385,
    24577,
  ];
  static const _distanceExtra = [
    0,
    0,
    0,
    0,
    1,
    1,
    2,
    2,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    8,
    9,
    9,
    10,
    10,
    11,
    11,
    12,
    12,
    13,
    13,
  ];
}

class _InflateWork {
  int blocks = 0;
}

class _Huffman {
  _Huffman(
    List<int> lengths, {
    bool requireComplete = false,
    bool allowEmpty = false,
  }) {
    final counts = List.filled(16, 0);
    for (final length in lengths) {
      counts[length]++;
    }
    final symbols = lengths.length - counts[0];
    if (symbols == 0) {
      if (!allowEmpty) _reject();
      return;
    }
    var available = 1;
    for (var size = 1; size <= 15; size++) {
      available = available * 2 - counts[size];
      if (available < 0) _reject();
    }
    if (available != 0 && (requireComplete || counts[1] != 1 || symbols != 1)) {
      _reject();
    }
    final next = List.filled(16, 0);
    var code = 0;
    counts[0] = 0;
    for (var size = 1; size <= 15; size++) {
      code = (code + counts[size - 1]) << 1;
      next[size] = code;
    }
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      final size = lengths[symbol];
      if (size != 0) table[(1 << size) | next[size]++] = symbol;
    }
  }
  final Map<int, int> table = {};
  int read(_DeflateBounds input) {
    var code = 1;
    for (var size = 1; size <= 15; size++) {
      code = (code << 1) | input.bits(1);
      final symbol = table[code];
      if (symbol != null) return symbol;
    }
    _reject();
  }
}

/// The dynamic sink protocol used by archive 3.6.1's Inflate.stream. Its
/// backing array never grows. Invalid/empty back references fail immediately
/// instead of allowing a malformed deflate distance to loop without progress.
class _CappedInflateOutput {
  _CappedInflateOutput(int capacity) : _buffer = Uint8List(capacity);
  final Uint8List _buffer;
  int length = 0;
  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, length);
  void writeByte(int value) {
    if (length >= _buffer.length) _reject(_limit);
    _buffer[length++] = value;
  }

  void writeBytes(List<int> bytes, [int? count]) {
    final size = count ?? bytes.length;
    if (size < 0 || size > bytes.length || length + size > _buffer.length) {
      _reject(_limit);
    }
    _buffer.setRange(length, length + size, bytes);
    length += size;
  }

  void writeInputStream(InputStreamBase input) =>
      writeBytes(input.toUint8List());
  List<int> subset(int start, [int? end]) {
    // This method is only called for nonempty backward references by Inflate.
    if (start >= 0) _reject();
    start += length;
    end = end == null ? length : (end < 0 ? length + end : end);
    if (start < 0 || end <= start || end > length) _reject();
    return Uint8List.sublistView(_buffer, start, end);
  }
}

class _WorkbookBounds {
  _WorkbookBounds(this.paths);
  final Set<String> paths;
  final Map<String, String> roots = {};
  final Map<String, String> sheetTargets = {};
  final Map<String, String> sheetIds = {};
  final Set<String> sheetNames = {};
  final List<int> stringRefs = [], styleRefs = [];
  String? stringsTarget, stylesTarget;
  int cells = 0, rows = 0, strings = 0, styles = 0, events = 0;

  void inspect(String path, Uint8List bytes) {
    final text = utf8.decode(bytes);
    // Reject declarations before the XML library can process internal subsets.
    if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) _reject();
    final stack = <String>[];
    var root = '';
    var currentRow = 0, previousRow = 0, previousColumn = 0;
    var stringLength = 0, cellLength = 0;
    var cellType = '';
    var value = '';
    var sheetDataCount = 0;
    final styleElements = <String, int>{};
    for (final event in parseEvents(
      text,
      validateNesting: true,
      validateDocument: true,
    )) {
      if (++events > 200000) _reject(_limit);
      if (event is XmlDoctypeEvent || event is XmlProcessingEvent) _reject();
      if (event is XmlStartElementEvent) {
        final name = event.name;
        if (stack.isEmpty) {
          root = name;
          roots[path] = root;
        }
        if (stack.length >= 32 || event.attributes.length > 32) _reject(_limit);
        final attrs = <String, String>{};
        for (final attr in event.attributes) {
          if (attr.value.length > 2048) _reject(_limit);
          if (attrs.containsKey(attr.name)) _reject();
          attrs[attr.name] = attr.value;
        }
        final parent = stack.lastOrNull;
        if (root == 'worksheet') {
          if (name.contains(':')) _reject();
          switch (name) {
            case 'sheetData':
              if (parent != 'worksheet' || ++sheetDataCount != 1) _reject();
            case 'dimension':
              _range(attrs['ref']);
            case 'row':
              if (parent != 'sheetData') _reject();
              currentRow = _positive(attrs['r'], rosterXlsxMaxRows);
              if (currentRow <= previousRow) _reject();
              previousRow = currentRow;
              previousColumn = 0;
              if (++rows > 500 + rosterXlsxMaxSheets) _reject(_limit);
            case 'c':
              if (parent != 'row' || ++cells > _maxCells) _reject(_limit);
              final point = _coordinate(attrs['r']);
              if (point.$2 != currentRow || point.$1 <= previousColumn) {
                _reject();
              }
              previousColumn = point.$1;
              cellType = attrs['t'] ?? 'n';
              if (cellType == 'str' || cellType == 'e') _formula();
              if (!{'s', 'n', 'b', 'inlineStr'}.contains(cellType)) _reject();
              if (attrs['s'] != null) styleRefs.add(_index(attrs['s'], 255));
              cellLength = 0;
            case 'v':
              if (parent != 'c') _reject();
              value = '';
            case 'f':
              _formula();
            case 'mergeCell':
              _reject('Merged cells are not accepted in member rosters.');
            case 'col':
              final min = _positive(attrs['min'], rosterXlsxMaxColumns);
              if (_positive(attrs['max'], rosterXlsxMaxColumns) < min) {
                _reject();
              }
          }
        }
        if (root == 'sst' && name == 'si') {
          if (parent != 'sst' || ++strings > _maxCells) _reject(_limit);
          stringLength = 0;
        }
        if (root == 'sst' && name == 'sst') {
          if (attrs['uniqueCount'] != null) {
            _index(attrs['uniqueCount'], _maxCells);
          }
          if (attrs['count'] != null) _index(attrs['count'], _maxCells);
        }
        if (root == 'styleSheet') {
          if ({'font', 'fill', 'border', 'numFmt', 'xf'}.contains(name)) {
            final count = styleElements.update(
              name,
              (v) => v + 1,
              ifAbsent: () => 1,
            );
            if (count > 256) _reject(_limit);
          }
          if (name == 'xf' && parent == 'cellXfs' && ++styles > 256) {
            _reject(_limit);
          }
          if (attrs['count'] != null) _index(attrs['count'], 256);
          if (name == 'numFmt' && (attrs['formatCode']?.length ?? 0) > 256) {
            _reject(_limit);
          }
        }
        if (path == 'xl/workbook.xml' && name == 'sheet') {
          final id = attrs['r:id'], sheetName = attrs['name'];
          if (parent != 'sheets' ||
              id == null ||
              sheetName == null ||
              sheetName.isEmpty ||
              sheetName.length > 31 ||
              sheetIds.containsKey(id) ||
              !sheetNames.add(sheetName.toLowerCase())) {
            _reject();
          }
          sheetIds[id] = sheetName;
          if (sheetIds.length > rosterXlsxMaxSheets) _reject(_limit);
        }
        if (name == 'Relationship') {
          // External workbook relationships, embedded objects and active content
          // are unnecessary for roster input and must never be followed.
          if (attrs['TargetMode'] != null &&
              attrs['TargetMode'] != 'Internal') {
            _reject();
          }
          final target = attrs['Target'];
          if (target == null) _reject();
          _relationshipPath(path, target);
          if (path == 'xl/_rels/workbook.xml.rels') {
            // Excel 4.0.6 concatenates these targets with 'xl/' literally.
            _safePath(target);
            final type = attrs['Type'] ?? '';
            final id = attrs['Id'];
            if (id == null) _reject();
            if (type.endsWith('/worksheet')) {
              if (sheetTargets.containsKey(id)) _reject();
              sheetTargets[id] = 'xl/$target';
            } else if (type.endsWith('/sharedStrings')) {
              if (stringsTarget != null) _reject();
              stringsTarget = 'xl/$target';
            } else if (type.endsWith('/styles')) {
              if (stylesTarget != null) _reject();
              stylesTarget = 'xl/$target';
            } else if (!type.endsWith('/theme')) {
              _reject();
            }
          }
        }
        if (!event.isSelfClosing) stack.add(name);
      } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
        final valueText = event is XmlTextEvent
            ? event.value
            : (event as XmlCDATAEvent).value;
        if (valueText.length > 16384) _reject(_limit);
        if (root == 'sst' && stack.contains('si')) {
          if ((stringLength += valueText.length) > 1024) _reject(_limit);
        }
        if (root == 'worksheet' && stack.contains('c')) {
          if ((cellLength += valueText.length) > 1024) _reject(_limit);
          if (stack.last == 'v') value += valueText;
        }
      } else if (event is XmlEndElementEvent) {
        if (root == 'worksheet' && event.name == 'v' && cellType == 's') {
          stringRefs.add(_index(value.trim(), _maxCells - 1));
        }
        stack.removeLast();
      }
    }
    if (root == 'worksheet' && sheetDataCount != 1) _reject();
  }

  void finish() {
    if (roots['[Content_Types].xml'] != 'Types' ||
        roots['xl/workbook.xml'] != 'workbook' ||
        roots['xl/_rels/workbook.xml.rels'] != 'Relationships' ||
        sheetIds.isEmpty ||
        sheetTargets.length != sheetIds.length) {
      _reject();
    }
    final targets = <String>{};
    for (final id in sheetIds.keys) {
      final target = sheetTargets[id];
      if (target == null ||
          !targets.add(target) ||
          roots[target] != 'worksheet') {
        _reject();
      }
    }
    if (roots.values.where((r) => r == 'worksheet').length != targets.length) {
      _reject();
    }
    if (stringRefs.isNotEmpty &&
        (roots[stringsTarget] != 'sst' ||
            stringRefs.any((i) => i >= strings))) {
      _reject();
    }
    if (styleRefs.isNotEmpty &&
        (roots[stylesTarget] != 'styleSheet' ||
            styleRefs.any((i) => i >= styles))) {
      _reject();
    }
    if (paths.any((p) => p.toLowerCase().endsWith('.bin'))) _reject();
  }
}

Never _formula() =>
    _reject('XLSX formulas are not accepted in member rosters.');

int _index(String? value, int max) {
  if (value == null || !RegExp(r'^[0-9]{1,9}$').hasMatch(value)) _reject();
  final result = int.parse(value);
  if (result > max) _reject(_limit);
  return result;
}

int _positive(String? value, int max) {
  final result = _index(value, max);
  if (result == 0) _reject();
  return result;
}

(int, int) _coordinate(String? value) {
  final match = RegExp(
    r'^([A-Z]{1,3})([1-9][0-9]{0,6})$',
  ).firstMatch(value ?? '');
  if (match == null) _reject();
  var column = 0;
  for (final code in match[1]!.codeUnits) {
    column = column * 26 + code - 64;
  }
  if (column > rosterXlsxMaxColumns) _reject(_limit);
  return (column, _positive(match[2], rosterXlsxMaxRows));
}

void _range(String? value) {
  final parts = value?.split(':') ?? [];
  if (parts.isEmpty || parts.length > 2) _reject();
  final start = _coordinate(parts.first), end = _coordinate(parts.last);
  if (end.$1 < start.$1 || end.$2 < start.$2) _reject();
}
