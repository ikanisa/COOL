@TestOn('browser')
library;

import 'dart:js_interop';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_gateway_checkpoint.dart';
import 'package:collect_app/admin/core/admin_governed_settings_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_cancel_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_checkpoint.dart';
import 'package:collect_app/admin/core/admin_recovery_namespace.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('window.localStorage')
external _Storage get _local;
@JS('window.sessionStorage')
external _Storage get _session;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

typedef _Case = ({
  String name,
  String retired,
  String current,
  bool local,
  bool multiple,
  String owner,
  Future<Object?> Function(String) read,
});

void main() {
  const actor = '99970000-0000-4000-8000-000000000001';
  final cases = <_Case>[
    (
      name: 'gateway',
      retired: 'collect.admin.gateway.recovery.v1.',
      current: 'collect.admin.gateway.recovery.v2.',
      local: false,
      multiple: false,
      owner: adminGatewayOwnerDigest(actor),
      read: (owner) async => browserAdminGatewayCheckpointStore()!.read(owner),
    ),
    (
      name: 'exception',
      retired: 'collect.admin.exceptions.recovery.v1.',
      current: 'collect.admin.exceptions.recovery.v2.',
      local: false,
      multiple: false,
      owner: adminExceptionOwnerDigest(actor),
      read: (owner) async =>
          browserAdminExceptionCheckpointStore()!.read(owner),
    ),
    (
      name: 'receipt cancellation',
      retired: 'collect.admin.receipt-cancel.recovery.v1.',
      current: 'collect.admin.receipt-cancel.recovery.v2.',
      local: false,
      multiple: false,
      owner: adminReceiptCancelOwnerDigest(actor),
      read: (owner) async =>
          browserAdminReceiptCancelCheckpointStore()!.read(owner),
    ),
    (
      name: 'successor',
      retired: 'collect.admin.receipt-successor.recovery.v1.',
      current: 'collect.admin.receipt-successor.recovery.v2.',
      local: false,
      multiple: false,
      owner: successorOwnerDigest(actor),
      read: (owner) async =>
          browserReceiptSuccessorCheckpointStore()!.read(owner),
    ),
    (
      name: 'operations',
      retired: 'collect.admin.receipt-operations.recovery.v2.',
      current: 'collect.admin.receipt-operations.recovery.v3.',
      local: true,
      multiple: true,
      owner: adminReceiptOperationsOwnerDigest(actor),
      read: (owner) async =>
          browserAdminReceiptOperationsCheckpointStore()!.read(owner),
    ),
    (
      name: 'settings',
      retired: 'collect.admin.settings.recovery.v2.',
      current: 'collect.admin.settings.recovery.v3.',
      local: true,
      multiple: true,
      owner: adminSettingsOwnerDigest(actor),
      read: (owner) async => browserAdminSettingsCheckpointStore()!.read(owner),
    ),
    (
      name: 'principal',
      retired: 'collect.admin.receipt-principal.recovery.v3.',
      current: 'collect.admin.receipt-principal.recovery.v4.',
      local: true,
      multiple: true,
      owner: adminReceiptPrincipalOwnerDigest(actor),
      read: (owner) async =>
          browserAdminReceiptPrincipalCheckpointStore()!.read(owner),
    ),
  ];
  for (final item in cases) {
    test(
      '${item.name} refuses an earlier original without hiding or rewriting it',
      () async {
        final storage = item.local ? _local : _session;
        final previous =
            '${item.retired}${'f' * 64}${item.multiple ? '.retained-request' : ''}';
        const original = 'exact earlier original bytes; outcome unknown';
        storage.setItem(previous, original);
        addTearDown(() => storage.removeItem(previous));
        await expectLater(
          item.read(item.owner),
          throwsA(isA<AdminEarlierRecoveryPending>()),
        );
        expect(storage.getItem(previous), original);
      },
    );
    test(
      '${item.name} clean current state ignores another current owner',
      () async {
        final storage = item.local ? _local : _session;
        final foreign =
            '${item.current}${'e' * 64}${item.multiple ? '.99970000-0000-4000-8000-000000000002' : ''}';
        const private = 'unread bytes owned by a different current account';
        storage.setItem(foreign, private);
        addTearDown(() => storage.removeItem(foreign));
        final result = await item.read(item.owner);
        expect(result, item.multiple ? isEmpty : isNull);
        expect(storage.getItem(foreign), private);
      },
    );
  }
}
