import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_roster_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Root executes the rollback-only SQL fixture; this decoder only reads its
// preserved stdout and does not connect to any database or provider.
const receiptPath = String.fromEnvironment('ROSTER_SQL_RECEIPTS');

void main() {
  test(
    'actual PostgreSQL142 receipts agree with the Admin decoders',
    () {
      final file = File(receiptPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Pass root-owned SQL stdout with --dart-define=ROSTER_SQL_RECEIPTS=/absolute/path',
      );
      final lines = file.readAsLinesSync();
      expect(
        lines.where((line) => line.trim() == 'ROSTER_RECEIPT_FIXTURE_PASS|2'),
        hasLength(1),
      );
      final packets = lines
          .where((line) => line.startsWith('ROSTER_RECEIPT_JSON|'))
          .map(
            (line) => rosterObject(
              jsonDecode(line.substring('ROSTER_RECEIPT_JSON|'.length)),
            ),
          )
          .toList();
      expect(packets.map((p) => p['case']).toSet(), {'deterministic', 'ai'});
      expect(packets, hasLength(2));
      for (final packet in packets) {
        final browser = rosterObject(packet['browser_request']);
        final source = rosterObject(packet['source']);
        final kind = browser['source_type'] as String;
        final bytes = kind == 'text'
            ? utf8.encode(browser['content'] as String)
            : base64Decode(browser['content_base64'] as String);
        final initial = AdminRosterPreview.fromJson(
          rosterObject(packet['initial_preview']),
        );
        initial.validateInitial(
          sourceKind: kind,
          sourceSha256: sha256.convert(bytes).toString(),
          requestId: browser['request_id'] as String,
          sourceSize: bytes.length,
          filename: browser['filename'] as String? ?? 'pasted-roster.txt',
          declaredMime: browser['mime_type'] as String? ?? 'text/plain',
          derivedSha256: browser['derived_content'] == null
              ? null
              : sha256
                    .convert(utf8.encode(browser['derived_content'] as String))
                    .toString(),
        );
        expect(initial.importId, source['import_id']);
        final reviewRequest = rosterObject(packet['review_request']);
        final reviewed = AdminRosterPreview.fromJson(
          rosterObject(packet['reviewed_preview']),
        );
        reviewed.validateRevision(
          initial,
          (reviewRequest['p_rows'] as List).length,
        );
        expect(reviewed.canSubmit, true);
        expect(reviewRequest['p_parent_revision_id'], initial.revisionId);
        final commitRequest = rosterObject(packet['commit_request']);
        final committed = AdminRosterCommit.fromJson(
          rosterObject(packet['commit']),
          request: commitRequest,
          expectedCount: reviewed.rowCount,
        );
        final replayed = AdminRosterCommit.fromJson(
          rosterObject(packet['commit_replay']),
          request: commitRequest,
          expectedCount: reviewed.rowCount,
        );
        expect(committed.replayed, false);
        expect(replayed.replayed, true);
        expect(committed.collectionId, replayed.collectionId);
        final read = rosterObject(packet['read']);
        expect(read['state'], 'committed');
        expect(read['import_id'], initial.importId);
        final historical = AdminRosterPreview.fromJson(
          rosterObject(read['preview']),
        );
        expect(historical.revisionId, reviewed.revisionId);
        expect(historical.canSubmit, false);
        expect(historical.sourceReceipt.raw, initial.sourceReceipt.raw);
        if (packet['case'] == 'ai') {
          expect(initial.sourceReceipt.aiConsent, true);
          expect(
            initial.sourceReceipt.raw['extraction_id'],
            source['extraction_id'],
          );
          expect(reviewed.model, initial.model);
          expect(initial.processingMethod, 'openai_structured_extraction');
          expect(reviewed.processingMethod, 'human_review');
        }
      }
    },
    skip: receiptPath.isEmpty
        ? 'Requires separately executed root-owned rollback SQL stdout.'
        : false,
  );
}
