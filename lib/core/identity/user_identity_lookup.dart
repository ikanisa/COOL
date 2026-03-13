import 'package:supabase_flutter/supabase_flutter.dart';

typedef UserIdentityRowsFetcher =
    Future<List<Map<String, dynamic>>> Function({
      required bool includePublicUserId,
    });

Future<List<Map<String, dynamic>>> fetchUserIdentityRows({
  required UserIdentityRowsFetcher fetchRows,
}) async {
  try {
    return await fetchRows(includePublicUserId: true);
  } on PostgrestException catch (error) {
    if (!isMissingPublicUserIdColumnError(error)) {
      rethrow;
    }

    return fetchRows(includePublicUserId: false);
  }
}

String buildUserIdentitySelect({
  bool includePublicUserId = true,
  List<String> extraColumns = const <String>[],
}) {
  final columns = <String>[
    'id',
    if (includePublicUserId) 'public_user_id',
    ...extraColumns.where(
      (column) =>
          column != 'id' &&
          column != 'public_user_id' &&
          column != 'phone' &&
          column.trim().isNotEmpty,
    ),
    'phone',
  ];
  return columns.join(', ');
}

bool isMissingPublicUserIdColumnError(Object error) {
  if (error is! PostgrestException) {
    return false;
  }

  final code = (error.code ?? '').toLowerCase();
  final haystack = [
    error.message,
    error.details,
    error.hint,
  ].whereType<String>().join(' ').toLowerCase();

  final mentionsColumn = haystack.contains('public_user_id');
  final isMissingColumn =
      code == '42703' ||
      haystack.contains('does not exist') ||
      haystack.contains('undefined column');

  return mentionsColumn && isMissingColumn;
}
