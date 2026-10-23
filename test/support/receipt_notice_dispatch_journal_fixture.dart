import 'dart:async';

import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_checkpoint.dart';

/// Injected platform persistence boundary; exercises the production journal codec.
class NoticeDispatchJournalFixture {
  NoticeDispatchJournalFixture({Map<String, String>? shared})
    : bytes = shared ?? <String, String>{} {
    store = AdminReceiptNoticeDispatchJournalStore(
      readRaw: (key) => refuseReadback ? null : bytes[key],
      writeRaw: (key, value) {
        if (refuseWrite) throw StateError('storage refused');
        bytes[key] = value;
        writes++;
      },
      exclusive: (key, mutate) async {
        final previous = _tail, done = Completer<void>();
        _tail = done.future;
        await previous;
        try {
          mutate();
          await release;
        } finally {
          done.complete();
        }
      },
    );
  }
  final Map<String, String> bytes;
  late final AdminReceiptNoticeDispatchJournalStore store;
  Future<void> _tail = Future<void>.value();
  Future<void>? release;
  bool refuseWrite = false, refuseReadback = false;
  int writes = 0;
}
