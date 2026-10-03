import 'package:collect_app/admin/core/roster_file_parser.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('XLSX roster decoding reconciles rows across sheets', () {
    final workbook = Excel.createExcel();
    final first = workbook['Sheet1'];
    first.appendRow([
      TextCellValue('Member name'),
      TextCellValue('MoMo name'),
      TextCellValue('MoMo number'),
    ]);
    first.appendRow([
      TextCellValue('Aline Uwase'),
      TextCellValue('ALINE UWASE'),
      TextCellValue('0788123456'),
    ]);
    final second = workbook['Second'];
    second.appendRow([
      TextCellValue('Phone'),
      TextCellValue('Registered name'),
      TextCellValue('Display name'),
    ]);
    second.appendRow([
      TextCellValue('0788999000'),
      TextCellValue('ERIC MUGABO'),
      TextCellValue('Eric Mugabo'),
    ]);

    final decoded = decodeRosterXlsx(workbook.encode()!);

    expect(decoded.split('\n'), hasLength(3));
    expect(decoded, contains('Aline Uwase\tALINE UWASE\t0788123456'));
    expect(decoded, contains('Eric Mugabo\tERIC MUGABO\t0788999000'));
  });

  test('XLSX roster decoding rejects formulas', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('Member name'),
      TextCellValue('MoMo name'),
      TextCellValue('MoMo number'),
    ]);
    sheet.appendRow([
      const FormulaCellValue('HYPERLINK("https://example.test")'),
      TextCellValue('UNTRUSTED'),
      TextCellValue('0788123456'),
    ]);

    expect(
      () => decodeRosterXlsx(workbook.encode()!),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('formulas are not accepted'),
        ),
      ),
    );
  });
}
