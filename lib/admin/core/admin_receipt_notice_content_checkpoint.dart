import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_receipt_notice_content_checkpoint_web.dart'
    as platform;

abstract interface class AdminReceiptNoticeContentStore {
  Future<AdminReceiptNoticeIntent?> read(String actor, String session);
  Future<void> write(AdminReceiptNoticeIntent intent);
  Future<void> clear(AdminReceiptNoticeIntent intent);
}

AdminReceiptNoticeContentStore? browserReceiptNoticeContentStore() =>
    platform.createStore();
