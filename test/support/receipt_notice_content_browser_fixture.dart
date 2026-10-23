// Actual canonical 1600 producer fixture SHA256 69cc1918364be365d3334542526f9b966b6753c8251c43451c93379ffbc75078.
import 'dart:convert';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';

const noticeBrowserActor = '99780000-0000-4000-8000-000000000001';
const noticeBrowserSession = '99780000-0000-4000-8000-000000010001';
AdminReceiptNoticeIntent noticeBrowserIntent([
  String requestId = '99780000-0000-4000-8000-000000009001',
]) {
  final row =
      jsonDecode(r'''{
  "scope": "rw_receipt_notice_content",
  "candidate": {
    "enabled": true,
    "template": {
      "family": "duplicate_copy",
      "language": "rw",
      "body_frame": "Kopi yinyemezabwishyu ya Collect %s yanditswe %s. Amafaranga yanditswe: %s RWF. Ubwizigame bwawe bwanditswe icyo gihe: %s RWF. Ref: %s. Iyi ni kopi yibyanditswe icyo gihe.",
      "consent_rule": "current_receipt_consent_required_no_override",
      "template_key": "collect.notice.duplicate_copy",
      "recipient_rule": "same_original_member",
      "disclosure_rule": "original_recorded_receipt_facts_only",
      "template_sha256": "0f3c848ad2e1457e8f35fb6dd93e40bc04306878d9dacbb71612db2b839f07ef",
      "semantic_version": 1
    },
    "collection_id": "99780000-0000-4000-8000-000000030001",
    "notice_family": "duplicate_copy",
    "approval_basis": "actual_current_owner_policy_action",
    "current_policy": null,
    "recipient_rule": "same_original_member",
    "send_authority": false,
    "consent_override": false,
    "financial_mutation": false,
    "current_policy_status": "unapproved",
    "expected_policy_revision": 0,
    "notice_transport_available": false
  },
  "checked_at": "2026-10-03T06:52:21.261168Z",
  "candidate_sha256": "5b4283579854ea700c84256df4e445ef658b32c524c426aa7e2b333e8482bf01",
  "contract_version": 1,
  "sample_valid_until": "2026-10-03T06:53:21.265235Z"
}
''')
          as Map<String, dynamic>;
  final candidate = row['candidate'] as Map<String, dynamic>;
  final sample = AdminReceiptNoticeInspection.policy(
    row,
    candidate['collection_id'] as String,
    AdminReceiptNoticeFamily.duplicateCopy,
    'rw',
    true,
  );
  return AdminReceiptNoticeIntent.create(
    inspection: sample,
    requestId: requestId,
    actorId: noticeBrowserActor,
    sessionId: noticeBrowserSession,
    reason: 'Reviewed immutable notice evidence',
    now: sample.checkedAt.add(const Duration(seconds: 1)),
  );
}
