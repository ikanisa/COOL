import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collect_app/admin/core/roster_file_parser.dart';
import 'package:collect_app/admin/core/roster_xlsx_preflight.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

const _sheetPath = 'xl/worksheets/sheet1.xml';
const _relsPath = 'xl/_rels/workbook.xml.rels';

void main() {
  late Map<String, List<int>> fixture;
  setUpAll(() {
    final excel = Excel.createExcel();
    excel['Sheet1'].appendRow([
      TextCellValue('Member name'),
      TextCellValue('MoMo name'),
      TextCellValue('MoMo number'),
    ]);
    excel['Sheet1'].appendRow([
      TextCellValue('Élodie 李'),
      TextCellValue('ÉLODIE 李'),
      TextCellValue('0788123456'),
    ]);
    fixture = {
      for (final f in ZipDecoder().decodeBytes(excel.encode()!))
        f.name: List<int>.from(f.content as List<int>),
    };
  });

  Map<String, List<int>> withXml(String path, String content) => {
    ...fixture,
    path: utf8.encode(content),
  };
  void rejects(List<int> bytes, [String? reason]) => expect(
    () => decodeRosterXlsx(bytes),
    throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'stable error',
        reason == null ? startsWith('The XLSX file') : contains(reason),
      ),
    ),
  );

  for (final level in [0, 1, 6, 9]) {
    test(
      'native zlib level $level is accepted and canonicalized to stored entries',
      () {
        final files = {
          ...fixture,
          'padding.dat': List.generate(8192, (i) => Random(i).nextInt(256)),
        };
        final bytes = _zip(files, level: level);
        final safe = preflightRosterXlsx(bytes);
        final index = _centralOffsets(safe);
        final data = ByteData.sublistView(Uint8List.fromList(safe));
        expect(
          index.every(
            (offset) => data.getUint16(offset + 10, Endian.little) == 0,
          ),
          isTrue,
        );
        expect(
          decodeRosterXlsx(bytes),
          contains('Élodie 李\tÉLODIE 李\t0788123456'),
        );
      },
    );
  }
  test('stored ZIP and signed data descriptors are accepted', () {
    expect(
      decodeRosterXlsx(_zip(fixture, stored: true)),
      contains('0788123456'),
    );
    expect(
      decodeRosterXlsx(_zip(fixture, descriptor: true)),
      contains('0788123456'),
    );
  });
  test('500 member rows plus header are accepted', () {
    final rows =
        '${_row(1, ['Member name', 'MoMo name', 'MoMo number'])}'
        '${List.generate(500, (i) => _row(i + 2, ['Member $i', 'NAME $i', '0788${i.toString().padLeft(6, '0')}'])).join()}';
    expect(
      decodeRosterXlsx(_zip(withXml(_sheetPath, _sheet(rows)))).split('\n'),
      hasLength(501),
    );
  });
  test('501 members cannot hide behind the per-sheet header allowance', () {
    final files = withXml(
      _sheetPath,
      _sheet(
        List.generate(
          501,
          (i) => _row(i + 1, ['A$i', 'B$i', '0788123456']),
        ).join(),
      ),
    );
    rejects(_zip(files), '500 members');
  });
  test('headerless rows and leading blank rows retain the roster contract', () {
    final rows = '<row r="1"/>${_row(2, ['Aline', 'ALINE', '0788123456'])}';
    expect(
      decodeRosterXlsx(_zip(withXml(_sheetPath, _sheet(rows)))),
      endsWith('Aline\tALINE\t0788123456'),
    );
  });
  test('missing phone header and empty workbooks still fail clearly', () {
    rejects(
      _zip(withXml(_sheetPath, _sheet(_row(1, ['Member name'])))),
      'MoMo number column',
    );
    rejects(_zip(withXml(_sheetPath, _sheet(''))), 'no member rows');
  });

  test(
    '5 MiB input bound runs before ZIP parsing',
    () =>
        rejects(Uint8List(rosterXlsxMaxBytes + 1), 'safe roster import limits'),
  );
  test('entry count is bounded before expansion', () {
    final files = {
      ...fixture,
      for (var i = 0; i < 65; i++) 'part$i.dat': [i],
    };
    rejects(_zip(files), 'safe roster import limits');
  });
  test('declared entry size and compression expansion ratio are bounded', () {
    rejects(
      _zip({...fixture, 'large.dat': Uint8List(rosterXlsxMaxEntryBytes + 1)}),
      'safe roster import limits',
    );
    rejects(
      _zip({...fixture, 'ratio.dat': Uint8List(1024 * 1024)}),
      'safe roster import limits',
    );
  });
  test(
    'aggregate expanded size is bounded even with moderate per-entry ratios',
    () {
      final random = Random(19);
      final block = List.generate(16000, (_) => random.nextInt(256));
      final megabyte = List<int>.generate(
        1800000,
        (i) => block[i % block.length],
      );
      rejects(
        _zip({...fixture, for (var i = 0; i < 5; i++) 'part$i.dat': megabyte}),
        'safe roster import limits',
      );
    },
  );
  test('forged small expanded size cannot bypass actual output bound', () {
    final bytes = _zip(
      {...fixture, 'bomb.dat': Uint8List(1024 * 1024)},
      sizeOverrides: {'bomb.dat': 16},
    );
    rejects(bytes, 'safe roster import limits');
  });
  test('empty deflate blocks cannot consume unbounded work', () {
    final raw = [
      for (var i = 0; i < 257; i++) ...[0, 0, 0, 255, 255],
      1,
      0,
      0,
      255,
      255,
    ];
    rejects(
      _zip({...fixture, 'empty.dat': []}, rawOverrides: {'empty.dat': raw}),
      'safe roster import limits',
    );
  });
  test('forged central/local sizes, CRC and names are rejected', () {
    for (final offset in [14, 18, 22, 30]) {
      final bytes = _zip(fixture);
      bytes[offset] ^= 1;
      rejects(bytes);
    }
    final bytes = _zip(fixture);
    final first = _centralOffsets(bytes).first;
    bytes[first + 16] ^= 1;
    bytes[14] ^= 1;
    rejects(bytes);
  });
  test(
    'truncation, missing directory, trailing junk and extra disk are rejected',
    () {
      final bytes = _zip(fixture);
      rejects(bytes.sublist(0, bytes.length - 1));
      rejects(bytes.sublist(0, 30));
      rejects([...bytes, 0]);
      final multiDisk = Uint8List.fromList(bytes);
      multiDisk[multiDisk.length - 18] = 1;
      rejects(multiDisk);
    },
  );
  test('overlapping local offsets and duplicate names are rejected', () {
    final bytes = _zip(fixture);
    final offsets = _centralOffsets(bytes);
    ByteData.sublistView(bytes).setUint32(offsets[1] + 42, 0, Endian.little);
    rejects(bytes);
    rejects(_zip({...fixture, 'XL/workbook.xml': fixture['xl/workbook.xml']!}));
  });
  for (final path in [
    '../escape.xml',
    '/absolute.xml',
    r'xl\evil.xml',
    'xl/./evil.xml',
    'xl//evil.xml',
    'xl/evil%2fpart.xml',
  ]) {
    test(
      'unsafe ZIP entry $path is rejected',
      () => rejects(_zip({...fixture, path: utf8.encode('<root/>')})),
    );
  }
  test(
    'encryption, unsupported compression, ZIP64 and symlinks are rejected',
    () {
      for (final mutation in [(6, 8, 1), (8, 10, 99), (4, 6, 45)]) {
        final bytes = _zip(fixture);
        final first = _centralOffsets(bytes).first;
        bytes[mutation.$1] = mutation.$3;
        bytes[first + mutation.$2] = mutation.$3;
        rejects(bytes);
      }
      final bytes = _zip(fixture);
      ByteData.sublistView(
        bytes,
      ).setUint32(_centralOffsets(bytes).first + 38, 0xa0000000, Endian.little);
      rejects(bytes);
    },
  );
  test('damaged or missing descriptor is rejected', () {
    final bytes = _zip(fixture, descriptor: true);
    final first = _centralOffsets(bytes).first;
    final compressed = ByteData.sublistView(
      bytes,
    ).getUint32(first + 20, Endian.little);
    final dataStart = 30 + utf8.encode(fixture.keys.first).length;
    bytes[dataStart + compressed + 4] ^= 1;
    rejects(bytes);
  });
  for (final malformed in <String, List<int>>{
    'reserved block': [7],
    'missing final block': [0, 0, 0, 255, 255],
    'bad stored complement': [1, 0, 0, 0, 0],
    'truncated fixed block': [3],
    'truncated dynamic tree': [5],
    'extra compressed bytes': [3, 0, 0],
    // Fixed code 257 (length 3), distance 1 before any literal exists.
    'back reference before output': _packedBits('1100000001000000000000'),
    // Fixed code 286 is reserved even though the fixed tree assigns it bits.
    'reserved literal symbol': _packedBits('11011000110'),
    // Four length-one code-length symbols oversubscribe a dynamic tree.
    'oversubscribed dynamic tree': _packedBits('10100000000000000100100100100'),
  }.entries) {
    test('${malformed.key} is rejected even with correct zero CRC/size', () {
      rejects(
        _zip(
          {...fixture, 'empty.dat': []},
          rawOverrides: {'empty.dat': malformed.value},
        ),
      );
    });
  }

  for (final payload in <String, String>{
    'sparse row': _sheet('<row r="1048576"/>'),
    'sparse column': _sheet('<row r="1"><c r="XFD1"/></row>'),
    'forged dimension': _sheet('', extra: '<dimension ref="A1:XFD1048576"/>'),
    'row/cell mismatch': _sheet('<row r="1"><c r="A2"/></row>'),
    'duplicate row': _sheet('<row r="1"/><row r="1"/>'),
    'duplicate cell': _sheet('<row r="1"><c r="A1"/><c r="A1"/></row>'),
    'column metadata': _sheet(
      '',
      extra: '<cols><col min="1" max="16384"/></cols>',
    ),
    'XML nesting': _sheet('${'<x>' * 33}${'</x>' * 33}'),
    'DTD': '<!DOCTYPE worksheet [<!ENTITY x "repeated">]>${_sheet('')}',
    'broken XML': '<worksheet><sheetData></worksheet>',
    'duplicate attributes': _sheet('<row r="1" r="2"/>'),
    'overlong cell': _sheet(_row(1, ['a' * 1025, 'NAME', '0788123456'])),
    'bad shared string index': _sheet(
      '<row r="1"><c r="A1" t="s"><v>9999</v></c></row>',
    ),
    'negative shared string index': _sheet(
      '<row r="1"><c r="A1" t="s"><v>-1</v></c></row>',
    ),
    'bad style index': _sheet(
      '<row r="1"><c r="A1" s="999999"><v>1</v></c></row>',
    ),
  }.entries) {
    test(
      '${payload.key} is rejected before sheet decoding',
      () => rejects(_zip(withXml(_sheetPath, payload.value))),
    );
  }
  test('merged regions and hidden formulas are rejected before decoding', () {
    rejects(
      _zip(
        withXml(
          _sheetPath,
          _sheet(
            '',
            extra: '<mergeCells><mergeCell ref="A1:AF501"/></mergeCells>',
          ),
        ),
      ),
      'Merged cells',
    );
    rejects(
      _zip(
        withXml(
          _sheetPath,
          _sheet('<row r="1"><c r="A1" t="s"><f>1+1</f><v>0</v></c></row>'),
        ),
      ),
      'formulas are not accepted',
    );
  });
  test('excess shared strings and rich-text expansion are bounded', () {
    rejects(
      _zip(withXml('xl/sharedStrings.xml', '<sst uniqueCount="1000000"/>')),
      'safe roster import limits',
    );
    rejects(
      _zip(
        withXml(
          'xl/sharedStrings.xml',
          '<sst><si>${'<r><t>${'a' * 100}</t></r>' * 11}</si></sst>',
        ),
      ),
      'safe roster import limits',
    );
  });
  test('actual XML event, attribute and style counts are bounded', () {
    rejects(
      _zip({
        ...fixture,
        'unused.xml': utf8.encode('<root>${'<n/>' * 200001}</root>'),
      }, stored: true),
      'safe roster import limits',
    );
    rejects(
      _zip({
        ...fixture,
        'unused.xml': utf8.encode(
          '<root ${List.generate(33, (i) => 'a$i="x"').join(' ')}/>',
        ),
      }),
      'safe roster import limits',
    );
    rejects(
      _zip(
        withXml(
          'xl/styles.xml',
          '<styleSheet><fonts count="1">${'<font/>' * 257}</fonts></styleSheet>',
        ),
      ),
      'safe roster import limits',
    );
    rejects(
      _zip(
        withXml(
          'xl/sharedStrings.xml',
          '<sst uniqueCount="1">${'<si><t>x</t></si>' * 16321}</sst>',
        ),
        stored: true,
      ),
      'safe roster import limits',
    );
  });
  test('missing/aliased sheet parts and too many sheets are rejected', () {
    final noSheet = {...fixture}..remove(_sheetPath);
    rejects(_zip(noSheet));
    final workbook = utf8.decode(fixture['xl/workbook.xml']!);
    final many = List.generate(
      11,
      (i) => '<sheet name="S$i" sheetId="${i + 1}" r:id="r$i"/>',
    ).join();
    rejects(
      _zip(
        withXml(
          'xl/workbook.xml',
          workbook.replaceFirst(
            RegExp(r'<sheets>.*?</sheets>', dotAll: true),
            '<sheets>$many</sheets>',
          ),
        ),
      ),
      'safe roster import limits',
    );
    final rels = utf8.decode(fixture[_relsPath]!);
    rejects(
      _zip(
        withXml(
          _relsPath,
          rels.replaceAll('worksheets/sheet1.xml', 'styles.xml'),
        ),
      ),
    );
  });
  test(
    'external relationships, escaping targets and active content are rejected',
    () {
      final rels = utf8.decode(fixture[_relsPath]!);
      rejects(
        _zip(
          withXml(
            _relsPath,
            rels.replaceFirst('Target=', 'TargetMode="External" Target='),
          ),
        ),
      );
      rejects(
        _zip(
          withXml(
            _relsPath,
            rels.replaceAll('worksheets/sheet1.xml', '../../outside.xml'),
          ),
        ),
      );
      rejects(
        _zip({
          ...fixture,
          'xl/vbaProject.bin': [0, 1, 2],
        }),
      );
    },
  );
}

String _sheet(String rows, {String extra = ''}) =>
    '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">$extra<sheetData>$rows</sheetData></worksheet>';
String _row(int index, List<String> values) =>
    '<row r="$index">${List.generate(values.length, (i) => '<c r="${String.fromCharCode(65 + i)}$index" t="inlineStr"><is><t>${values[i]}</t></is></c>').join()}</row>';

/// Independent native-zlib fixture writer. Metadata overrides deliberately
/// bypass the production parser and do not allocate declared expanded sizes.
Uint8List _zip(
  Map<String, List<int>> files, {
  int level = 6,
  bool stored = false,
  bool descriptor = false,
  Map<String, int> sizeOverrides = const {},
  Map<String, List<int>> rawOverrides = const {},
}) {
  final local = BytesBuilder(), central = BytesBuilder();
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final raw =
        rawOverrides[entry.key] ??
        (stored
            ? entry.value
            : io.ZLibEncoder(raw: true, level: level).convert(entry.value));
    final size = sizeOverrides[entry.key] ?? entry.value.length;
    final crc = getCrc32(entry.value);
    final flags = 0x800 | (descriptor ? 8 : 0);
    final lh = ByteData(30), ch = ByteData(46);
    void l16(int o, int v) => lh.setUint16(o, v, Endian.little);
    void l32(int o, int v) => lh.setUint32(o, v, Endian.little);
    void c16(int o, int v) => ch.setUint16(o, v, Endian.little);
    void c32(int o, int v) => ch.setUint32(o, v, Endian.little);
    l32(0, 0x04034b50);
    l16(4, 20);
    l16(6, flags);
    l16(8, stored ? 0 : 8);
    if (!descriptor) {
      l32(14, crc);
      l32(18, raw.length);
      l32(22, size);
    }
    l16(26, name.length);
    c32(0, 0x02014b50);
    c16(4, 20);
    c16(6, 20);
    c16(8, flags);
    c16(10, stored ? 0 : 8);
    c32(16, crc);
    c32(20, raw.length);
    c32(24, size);
    c16(28, name.length);
    c32(42, local.length);
    local.add(lh.buffer.asUint8List());
    local.add(name);
    local.add(raw);
    if (descriptor) {
      final d = ByteData(16)
        ..setUint32(0, 0x08074b50, Endian.little)
        ..setUint32(4, crc, Endian.little)
        ..setUint32(8, raw.length, Endian.little)
        ..setUint32(12, size, Endian.little);
      local.add(d.buffer.asUint8List());
    }
    central.add(ch.buffer.asUint8List());
    central.add(name);
  }
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, central.length, Endian.little)
    ..setUint32(16, local.length, Endian.little);
  return (BytesBuilder()
        ..add(local.takeBytes())
        ..add(central.takeBytes())
        ..add(end.buffer.asUint8List()))
      .takeBytes();
}

List<int> _centralOffsets(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  var cursor = data.getUint32(bytes.length - 6, Endian.little);
  final offsets = <int>[];
  while (data.getUint32(cursor, Endian.little) == 0x02014b50) {
    offsets.add(cursor);
    cursor +=
        46 +
        data.getUint16(cursor + 28, Endian.little) +
        data.getUint16(cursor + 30, Endian.little) +
        data.getUint16(cursor + 32, Endian.little);
  }
  return offsets;
}

List<int> _packedBits(String bits) {
  final bytes = Uint8List((bits.length + 7) ~/ 8);
  for (var i = 0; i < bits.length; i++) {
    if (bits[i] == '1') bytes[i ~/ 8] |= 1 << (i % 8);
  }
  return bytes;
}
