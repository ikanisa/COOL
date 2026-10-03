import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_roster_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Root produced this rollback-only packet using the installed149 routines.
// This test decodes saved evidence and performs no SQL/provider operation.
const receiptPath = String.fromEnvironment('ROSTER_FRESH_SQL_RECEIPTS');

void main() {
  test(
    'actual149 fresh recovery receipts agree with every client decoder',
    () {
      final lines = File(receiptPath).readAsLinesSync();
      final packets = lines.where(
        (s) => s.startsWith('ROSTER_FRESH_AUTH_RECEIPT_JSON|'),
      );
      expect(packets, hasLength(1));
      final packet = rosterObject(
        jsonDecode(packets.single.split('|').skip(1).join('|')),
      );
      final listing = rosterObject(packet['listing']);
      final owner = rosterTextDigest(
        'collect-roster-owner-v1:${listing['actor_id']}:${listing['destination_session_id']}',
      );
      final list = AdminRosterInterruptedList.fromJson(listing, owner);
      expect(list.items, hasLength(1));
      final inspected = AdminRosterInterruptedInspection.fromJson(
        rosterObject(packet['inspected']),
        list.items.single,
        owner,
      );
      final request = rosterObject(packet['transfer_request']);
      final ack = AdminRosterTransferAck.fromJson(
        rosterObject(packet['ack']),
        request: request,
        ownerDigest: owner,
        inspected: inspected,
      );
      final recovery = AdminRosterRecovery.fromJson(
        rosterObject(packet['recovered']),
        uploadRequestId: ack.destinationReferenceId,
        sourceSha256: inspected.initial.sourceSha256,
        importId: ack.toImportId,
      );
      final initial = recovery.initial!;
      expect(initial.canSubmit, isFalse);
      expect(initial.requiresHumanReview, isTrue);
      expect(initial.sourceReceipt.raw, inspected.initial.sourceReceipt.raw);
      expect(
        initial.sourceReceipt.requestId,
        isNot(ack.destinationReferenceId),
      );
      expect(initial.recoveryLineage!.ownerDigest, owner);
      expect(
        initial.recoveryLineage!.originalProofSha256,
        ack.originalProofSha256,
      );
      expect(recovery.checkpointId, ack.checkpointId);
      expect(recovery.draft!['parent_revision_id'], ack.initialRevisionId);
      expect(
        recovery.draft!['rows'],
        jsonDecode(packet['draft_text'] as String)['rows'],
      );
      final reviewed = AdminRosterPreview.fromJson(
        rosterObject(packet['reviewed']),
      );
      reviewed.validateRevision(
        initial,
        (recovery.draft!['rows'] as List).length,
      );
      expect(reviewed.canSubmit, isTrue);
      final committedRaw = rosterObject(packet['commit']);
      final committed = AdminRosterCommit.fromJson(
        committedRaw,
        request: {
          'p_request_id': committedRaw['request_id'],
          'p_import_id': ack.toImportId,
          'p_revision_id': reviewed.revisionId,
          'p_reviewed_rows_sha256': reviewed.reviewedRowsSha256,
          'p_mode': 'create',
          'p_collection_id': null,
        },
        expectedCount: reviewed.rowCount,
      );
      expect(committed.replayed, isFalse);
      expect(rosterObject(packet['committed_status'])['commit'], committedRaw);
      final assertions = lines.singleWhere(
        (s) => s.startsWith('ROSTER_FRESH_AUTH_ASSERTIONS_JSON|'),
      );
      final checks = rosterObject(
        jsonDecode(assertions.split('|').skip(1).join('|')),
      );
      expect(checks['passed'], 51);
      expect(checks['checks'], hasLength(51));
    },
    skip: receiptPath.isEmpty
        ? 'Requires separately executed root rollback SQL149 receipts.'
        : false,
  );
}
