import 'admin_receipt_aggregate_v3_models.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_models.dart';

class ReceiptAggregateV3SessionChanged implements Exception {
  const ReceiptAggregateV3SessionChanged();
}

/// Separate read-only consumer. It does not infer v3 absence from an immutable
/// legacy worker-side v1 aggregate status, and exposes stale history explicitly.
class AdminReceiptAggregateV3Api {
  const AdminReceiptAggregateV3Api({
    required this.rpc,
    required this.isCurrent,
  });
  final Future<Object?> Function(String, Map<String, dynamic>) rpc;
  final bool Function() isCurrent;
  void _current() {
    if (!isCurrent()) throw const ReceiptAggregateV3SessionChanged();
  }

  Future<AdminReceiptAggregateSampleV3> sample(String requestId) async {
    cancelUuid(requestId);
    _current();
    try {
      final raw = await rpc(
        'admin_get_receipt_aggregate_sample_v3',
        Map.unmodifiable({'p_request_id': requestId}),
      ).timeout(const Duration(seconds: 15));
      _current();
      return AdminReceiptAggregateSampleV3.parse(raw, requestId);
    } catch (_) {
      _current();
      rethrow;
    }
  }
}
