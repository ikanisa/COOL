import 'dart:convert';
import 'dart:io';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';

const operationsRequest = '99430000-0000-4000-8000-000000000040';
const operationsStopRequest = '99430000-0000-4000-8000-000000000041';
const operationsPrincipal = '99430000-0000-4000-8000-000000000042';
const operationsCollection = '99430000-0000-4000-8000-000000000043';
const operationsDevice = '99430000-0000-4000-8000-000000000044';
final operationsTime = DateTime.utc(2026, 10, 1, 12);
Map<String, dynamic> actualOperationsFixture(String name) =>
    jsonDecode(
          File(
            'test/fixtures/admin_receipt_operations_v2/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> operationsPolicyFixture() => {
  ...actualOperationsFixture('observed-policy-default'),
  'checked_at': operationsUtc(operationsTime),
  'updated_at': operationsUtc(
    operationsTime.subtract(const Duration(seconds: 1)),
  ),
};
AdminReceiptOperationsCaps operationsCaps({
  int actions = 5,
  int segments = 10,
}) => AdminReceiptOperationsCaps.parse({
  for (final key in AdminReceiptOperationsCaps.names)
    key: key.endsWith('sms_segments') ? segments : actions,
});
AdminReceiptOperationsIntent operationsIntent({
  bool stop = false,
  String? requestId,
  AdminReceiptOperationsMode mode = AdminReceiptOperationsMode.shadow,
  DateTime? createdAt,
  int expectedRevision = 1,
}) => stop
    ? AdminReceiptOperationsIntent.stop(
        requestId: requestId ?? operationsStopRequest,
        expectedRevision: expectedRevision,
        createdAt: createdAt ?? operationsTime,
        expiresAt: (createdAt ?? operationsTime).add(
          const Duration(seconds: 90),
        ),
        reason: 'Reviewed synthetic emergency stop',
      )
    : AdminReceiptOperationsIntent.configure(
        requestId: requestId ?? operationsRequest,
        expectedRevision: expectedRevision,
        createdAt: createdAt ?? operationsTime,
        expiresAt: (createdAt ?? operationsTime).add(
          const Duration(seconds: 90),
        ),
        reason: 'Reviewed synthetic policy change',
        mode: mode,
        emergencyStop: mode == AdminReceiptOperationsMode.paused,
        principalIds: [operationsPrincipal],
        collectionIds: [operationsCollection],
        deviceIds: [operationsDevice],
        caps: operationsCaps(),
        catchupEnabled: false,
        catchupHours: 24,
      );
Map<String, dynamic> operationsReceipt(AdminReceiptOperationsIntent intent) => {
  'contract_version': 2,
  'request_id': intent.requestId,
  'revision': intent.expectedRevision + 1,
  'mode': intent.mode.label,
  'emergency_stop': intent.emergencyStop,
  'recorded_at': operationsUtc(
    intent.createdAt.add(const Duration(seconds: 1)),
  ),
  'expires_at': operationsUtc(intent.expiresAt),
};
Map<String, dynamic> operationsLookup(
  AdminReceiptOperationsIntent intent,
  DateTime checked, {
  String status = 'not_recorded',
}) => {
  'contract_version': 2,
  'request_id': intent.requestId,
  'checked_at': operationsUtc(checked),
  'sample_valid_until': operationsUtc(checked.add(const Duration(seconds: 60))),
  'status': status,
  'expires_at': status == 'recorded' ? operationsUtc(intent.expiresAt) : null,
  'receipt': status == 'recorded' ? operationsReceipt(intent) : null,
};
