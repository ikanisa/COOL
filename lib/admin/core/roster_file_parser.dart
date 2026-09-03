import 'package:excel/excel.dart' as spreadsheet;

String decodeRosterXlsx(List<int> bytes) {
  final workbook = spreadsheet.Excel.decodeBytes(bytes);
  final output = <String>['Member name\tMoMo name\tMoMo number'];
  var candidateRows = 0;
  for (final sheet in workbook.tables.values) {
    final rows = sheet.rows
        .map((row) => row.map(_safeRosterCellText).toList())
        .where((row) => row.any((value) => value.isNotEmpty))
        .toList();
    if (rows.isEmpty) continue;
    final indices = _rosterHeaderIndices(rows.first);
    final hasHeader = indices.values.any((index) => index >= 0);
    final memberIndex = hasHeader ? indices['member_name'] ?? -1 : 0;
    final momoNameIndex = hasHeader ? indices['momo_name'] ?? -1 : 1;
    final momoNumberIndex = hasHeader ? indices['momo_number'] ?? -1 : 2;
    if (hasHeader && momoNumberIndex < 0) {
      throw StateError(
        'Each XLSX sheet with a header must include a MoMo number column.',
      );
    }
    for (final row in rows.skip(hasHeader ? 1 : 0)) {
      String at(int index) => index >= 0 && index < row.length
          ? row[index].replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim()
          : '';
      final momoName = at(momoNameIndex);
      output.add(
        [
          at(memberIndex).isEmpty ? momoName : at(memberIndex),
          momoName,
          at(momoNumberIndex),
        ].join('\t'),
      );
      candidateRows += 1;
      if (candidateRows > 500) {
        throw StateError('Roster preview is limited to 500 members.');
      }
    }
  }
  if (candidateRows == 0) {
    throw StateError('The XLSX file has no member rows.');
  }
  return output.join('\n');
}

String _safeRosterCellText(spreadsheet.Data? cell) {
  final value = cell?.value;
  if (value is spreadsheet.FormulaCellValue) {
    throw StateError('XLSX formulas are not accepted in member rosters.');
  }
  return value?.toString().trim() ?? '';
}

Map<String, int> _rosterHeaderIndices(List<String> row) {
  const aliases = {
    'member_name': {'member', 'member name', 'display name', 'name'},
    'momo_name': {
      'momo name',
      'registered momo name',
      'registered name',
      'account name',
    },
    'momo_number': {
      'momo number',
      'mobile money number',
      'mobile number',
      'phone',
      'phone number',
      'telephone',
    },
  };
  final result = <String, int>{
    'member_name': -1,
    'momo_name': -1,
    'momo_number': -1,
  };
  for (var index = 0; index < row.length; index += 1) {
    final header = row[index]
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), ' ')
        .trim();
    for (final entry in aliases.entries) {
      if (entry.value.contains(header)) result[entry.key] = index;
    }
  }
  return result;
}
