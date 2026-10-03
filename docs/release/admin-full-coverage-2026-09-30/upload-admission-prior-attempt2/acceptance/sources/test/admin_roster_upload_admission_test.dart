import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_roster_fixture.dart';

/// Implements the actual locked FilePicker PlatformFile contract. Whole reads,
/// path access and the length() fallback are observed independently from chunks.
final class _SelectedFile extends PlatformFile {
  _SelectedFile(
    this.name,
    this.chunks, {
    this.reportedLength,
    this.streamError,
  });

  @override
  final String name;
  final List<Uint8List> chunks;
  final int? reportedLength;
  final Object? streamError;
  int wholeReads = 0, streamReads = 0, lengthReads = 0, emittedChunks = 0;
  bool streamClosed = false;

  @override
  Uri get uri => throw StateError('PRIVATE_PATH must not be resolved');
  @override
  Never get xFile => throw StateError('XFile must not be resolved');
  @override
  int? lengthSync() => reportedLength;
  @override
  Future<int> length() async {
    lengthReads++;
    return chunks.fold<int>(0, (total, chunk) => total + chunk.length);
  }

  @override
  Future<Uint8List> readAsBytes() async {
    wholeReads++;
    final bytes = BytesBuilder();
    for (final chunk in chunks) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() async* {
    streamReads++;
    try {
      for (final chunk in chunks) {
        emittedChunks++;
        yield chunk;
      }
      if (streamError != null) throw streamError!;
    } finally {
      streamClosed = true;
    }
  }
}

Uint8List _bytes(int count) => Uint8List(count)..fillRange(0, count, 65);

void _noByteRead(_SelectedFile file) {
  expect(file.wholeReads, 0);
  expect(file.streamReads, 0);
  expect(file.lengthReads, 0);
}

void main() {
  const textLimit = 512000, binaryLimit = 5242880;
  final workbook = Excel.createExcel();
  workbook['Sheet1'].appendRow([
    TextCellValue('Member name'),
    TextCellValue('MoMo name'),
    TextCellValue('MoMo number'),
  ]);
  workbook['Sheet1'].appendRow([
    TextCellValue('Alice One'),
    TextCellValue('ALICE ONE'),
    TextCellValue('0788100000'),
  ]);
  final xlsx = Uint8List.fromList(workbook.encode()!);
  const mimes = {
    'csv': 'text/csv',
    'txt': 'text/plain',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  for (final extension in mimes.keys) {
    test(
      '$extension metadata rejects an oversized source before byte I/O',
      () async {
        final cap = {'csv', 'txt'}.contains(extension)
            ? textLimit
            : binaryLimit;
        // XLSX bytes deliberately cannot parse. Metadata rejection must happen
        // before parser entry, instead of allocating or parsing this source.
        final file = _SelectedFile('Roster.$extension', [
          _bytes(3),
        ], reportedLength: cap + 1);
        await expectLater(
          AdminRosterUpload.file(file, aiConsent: true),
          throwsStateError,
        );
        _noByteRead(file);
      },
    );
    test(
      '$extension admitted chunks preserve exact source SHA and declared MIME',
      () async {
        final bytes = extension == 'xlsx'
            ? xlsx
            : Uint8List.fromList(utf8.encode('Original\r\nRoster $extension'));
        final midpoint = bytes.length ~/ 2;
        final file = _SelectedFile('Roster.${extension.toUpperCase()}', [
          Uint8List.sublistView(bytes, 0, midpoint),
          Uint8List(0),
          Uint8List.sublistView(bytes, midpoint),
        ], reportedLength: bytes.length);
        final upload = await AdminRosterUpload.file(file, aiConsent: true);
        expect(base64Decode(upload.body['content_base64'] as String), bytes);
        expect(upload.sourceSha256, sha256.convert(bytes).toString());
        expect(upload.sourceSize, bytes.length);
        expect(upload.body['mime_type'], mimes[extension]);
        expect(
          upload.sourceKind,
          {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
              ? 'image'
              : extension,
        );
        expect(upload.body['filename'], 'Roster.${extension.toUpperCase()}');
        expect(
          upload.body['ai_consent'],
          {'pdf', 'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
              ? true
              : null,
        );
        expect(
          upload.body['derived_content'],
          extension == 'xlsx'
              ? contains('Alice One\tALICE ONE\t0788100000')
              : isNull,
        );
        expect(file.wholeReads, 0);
        expect(file.lengthReads, 0);
        expect(file.streamReads, 1);
        expect(file.streamClosed, true);
      },
    );
  }
  for (final name in ['Roster.exe', 'Roster', '.csv', 'Roster.csv.exe']) {
    test('$name unsupported extension rejects before byte I/O', () async {
      final file = _SelectedFile(name, [_bytes(3)]);
      await expectLater(
        AdminRosterUpload.file(file, aiConsent: true),
        throwsStateError,
      );
      _noByteRead(file);
    });
  }
  for (final extension in ['pdf', 'png', 'jpg', 'jpeg', 'webp']) {
    test('$extension without AI consent rejects before byte I/O', () async {
      final file = _SelectedFile('Roster.$extension', [_bytes(3)]);
      await expectLater(
        AdminRosterUpload.file(file, aiConsent: false),
        throwsStateError,
      );
      _noByteRead(file);
    });
  }
  for (final reported in [0, -1]) {
    test('invalid metadata length $reported rejects before byte I/O', () async {
      final file = _SelectedFile('Roster.csv', [
        _bytes(3),
      ], reportedLength: reported);
      await expectLater(
        AdminRosterUpload.file(file, aiConsent: false),
        throwsStateError,
      );
      _noByteRead(file);
    });
  }
  for (final extension in ['csv', 'txt', 'pdf', 'png']) {
    final cap = {'csv', 'txt'}.contains(extension) ? textLimit : binaryLimit;
    test('$extension unknown length accepts its exact byte boundary', () async {
      final file = _SelectedFile('Roster.$extension', [
        _bytes(cap ~/ 2),
        _bytes(cap - cap ~/ 2),
      ]);
      final upload = await AdminRosterUpload.file(file, aiConsent: true);
      expect(upload.sourceSize, cap);
      expect(file.wholeReads, 0);
      expect(file.lengthReads, 0);
      expect(file.streamClosed, true);
    });
    test(
      '$extension unknown stream overrun cancels before any later chunk',
      () async {
        final file = _SelectedFile('Roster.$extension', [
          _bytes(cap),
          _bytes(1),
          _bytes(7),
        ]);
        await expectLater(
          AdminRosterUpload.file(file, aiConsent: true),
          throwsStateError,
        );
        expect(file.wholeReads, 0);
        expect(file.lengthReads, 0);
        expect(file.emittedChunks, 2);
        expect(file.streamClosed, true);
      },
    );
  }
  test(
    'a single oversized chunk is rejected and its stream is cancelled',
    () async {
      final file = _SelectedFile('Roster.csv', [
        _bytes(textLimit + 1),
        _bytes(7),
      ]);
      await expectLater(
        AdminRosterUpload.file(file, aiConsent: false),
        throwsStateError,
      );
      expect(file.wholeReads, 0);
      expect(file.emittedChunks, 1);
      expect(file.streamClosed, true);
    },
  );
  for (final reported in [1, 4]) {
    test(
      'lying metadata length $reported cannot bind different source bytes',
      () async {
        final file = _SelectedFile('Roster.csv', [
          _bytes(3),
        ], reportedLength: reported);
        await expectLater(
          AdminRosterUpload.file(file, aiConsent: false),
          throwsStateError,
        );
        expect(file.wholeReads, 0);
        expect(file.streamClosed, true);
      },
    );
  }
  test('an empty unknown-length stream cannot produce an upload', () async {
    final file = _SelectedFile('Roster.csv', []);
    await expectLater(
      AdminRosterUpload.file(file, aiConsent: false),
      throwsStateError,
    );
    expect(file.streamReads, 1);
    expect(file.streamClosed, true);
  });
  test('invalid UTF8 remains rejected after bounded reading', () async {
    final file = _SelectedFile('Roster.csv', [
      Uint8List.fromList([0xff]),
    ]);
    await expectLater(
      AdminRosterUpload.file(file, aiConsent: false),
      throwsFormatException,
    );
    expect(file.wholeReads, 0);
    expect(file.streamClosed, true);
  });
  test(
    'stream errors close reading and expose no draft payload or server call',
    () async {
      final file = _SelectedFile('Roster.csv', [
        _bytes(3),
      ], streamError: StateError('PRIVATE_PATH PRIVATE_FILE_CONTENT'));
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      try {
        await draft.prepare(
          () => AdminRosterUpload.file(file, aiConsent: false),
        );
        expect(file.wholeReads, 0);
        expect(file.streamClosed, true);
        expect(gateway.prepares, isEmpty);
        expect(gateway.reviews, isEmpty);
        expect(gateway.commits, isEmpty);
        expect(draft.preview, isNull);
        expect(
          draft.error,
          'The source could not be read. Check its format and size, then try again.',
        );
        expect(draft.error, isNot(contains('PRIVATE')));
      } finally {
        draft.dispose();
      }
    },
  );
  for (final extension in ['csv', 'xlsx']) {
    test(
      '$extension streamed resource rejection never reaches parser/server preparation',
      () async {
        final cap = extension == 'csv' ? textLimit : binaryLimit;
        final file = _SelectedFile('Roster.$extension', [
          _bytes(cap),
          _bytes(1),
          _bytes(7),
        ]);
        final gateway = FakeRosterGateway();
        final draft = AdminRosterDraft(gateway);
        try {
          await draft.prepare(
            () => AdminRosterUpload.file(file, aiConsent: false),
          );
          expect(file.wholeReads, 0);
          expect(file.emittedChunks, 2);
          expect(file.streamClosed, true);
          expect(gateway.prepares, isEmpty);
          expect(draft.preview, isNull);
        } finally {
          draft.dispose();
        }
      },
    );
  }
  for (final field in ['member_name', 'momo_name']) {
    for (final control in ['', ' ', '\t', '\r\n', '\u0000', '\u000b']) {
      for (final formula in ['=', '+', '-', '@']) {
        test(
          '$field leading ${control.codeUnits} $formula formula is rejected before review dispatch',
          () async {
            final gateway = FakeRosterGateway();
            final draft = AdminRosterDraft(gateway);
            try {
              await draft.prepare(
                () async => AdminRosterUpload.pasted('Roster'),
              );
            draft.edit(0, field, '$control${formula}UNTRUSTED');
              await draft.saveReview('Verified source row');
              expect(gateway.reviews, isEmpty);
              expect(draft.reviewIssues, contains(0));
              expect(draft.canCommit, false);
            } finally {
              draft.dispose();
            }
          },
        );
      }
    }
  }
  test(
    'legitimate Rwanda plus phone and ordinary names remain reviewable',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      try {
        await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
        draft.edit(0, 'momo_number', '+250788100000');
        draft.edit(0, 'member_name', 'Aline Uwase');
        await draft.saveReview('Verified source row');
        expect(gateway.reviews, hasLength(1));
        expect(draft.reviewIssues, isEmpty);
      } finally {
        draft.dispose();
      }
    },
  );
}
