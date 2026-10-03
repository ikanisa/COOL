import 'admin_models.dart';

/// The exact server page whose rows are being displayed; never a clamped label
/// attached to rows fetched from a different offset.
class AdminLoadedPage {
  const AdminLoadedPage({
    required this.result,
    required this.page,
    required this.pageSize,
  });

  final AdminListResult result;
  final int page;
  final int pageSize;

  int get total => result.total!;
  int get lastPage => total == 0 ? 0 : (total - 1) ~/ pageSize;
  int get start => total == 0 ? 0 : page * pageSize + 1;
  int get end => total == 0 ? 0 : page * pageSize + result.rows.length;
}

/// An obsolete read must not update page state or the last-refresh timestamp.
/// This cancels publication and recovery reads, not the network request itself.
class AdminPageRequestSuperseded implements Exception {
  const AdminPageRequestSuperseded();

  @override
  String toString() => 'This admin page request has been superseded.';
}

typedef AdminPageFetcher =
    Future<AdminListResult> Function(int limit, int offset);

/// Recover when deletions/reconciliation make the requested page disappear.
/// A small bounded retry prevents realtime churn from creating a request loop.
/// Authorization and transport errors propagate; no unscoped fallback is used.
Future<AdminLoadedPage> loadAdminListPage({
  required AdminPageFetcher fetch,
  required int page,
  int pageSize = 25,
  bool Function()? isCurrent,
  int maxRecoveryAttempts = 2,
}) async {
  if (page < 0) throw RangeError.range(page, 0, null, 'page');
  if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
  if (maxRecoveryAttempts < 0) {
    throw RangeError.range(maxRecoveryAttempts, 0, null, 'maxRecoveryAttempts');
  }
  void checkCurrent() {
    if (isCurrent != null && !isCurrent()) {
      throw const AdminPageRequestSuperseded();
    }
  }

  var requestedPage = page;
  var probingFirstPage = false;
  for (var attempt = 0; ; attempt++) {
    checkCurrent();
    final response = await fetch(pageSize, requestedPage * pageSize);
    checkCurrent();
    final result = response.validateWindow(
      limit: pageSize,
      offset: requestedPage * pageSize,
    );
    final total = result.total!;
    if (total == 0) {
      if (requestedPage == 0) {
        return AdminLoadedPage(result: result, page: 0, pageSize: pageSize);
      }
      // Some legacy RPCs calculate `total` from the paged result. An offset
      // beyond their last row therefore returns zero even when earlier pages
      // still exist. Probe the first page before declaring the queue empty.
      if (attempt >= maxRecoveryAttempts) {
        throw StateError('Admin results changed repeatedly. Refresh the list.');
      }
      requestedPage = 0;
      probingFirstPage = true;
      continue;
    }
    final lastPage = (total - 1) ~/ pageSize;
    if (probingFirstPage) {
      probingFirstPage = false;
      if (lastPage > 0) {
        if (attempt >= maxRecoveryAttempts) {
          throw StateError(
            'Admin results changed repeatedly. Refresh the list.',
          );
        }
        requestedPage = lastPage;
        continue;
      }
    }
    if (requestedPage <= lastPage) {
      return AdminLoadedPage(
        result: result,
        page: requestedPage,
        pageSize: pageSize,
      );
    }
    if (attempt >= maxRecoveryAttempts) {
      throw StateError('Admin results changed repeatedly. Refresh the list.');
    }
    requestedPage = lastPage;
  }
}
