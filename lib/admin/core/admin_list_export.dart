part of 'admin_runtime.dart';

String _adminRowsToCsv(List<AdminTableRowData> rows) {
  final buffer = StringBuffer('id,title,subtitle,status,amount,created_at\n');
  for (final row in rows) {
    buffer.writeln(
      [
        row.id,
        row.title,
        row.subtitle,
        row.status,
        row.amount,
        row.createdAt?.toIso8601String() ?? '',
      ].map(_csvCell).join(','),
    );
  }
  return buffer.toString();
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  if (escaped.contains(',') ||
      escaped.contains('"') ||
      escaped.contains('\n') ||
      escaped.contains('\r')) {
    return '"$escaped"';
  }
  return escaped;
}
