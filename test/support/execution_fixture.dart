import 'dart:convert';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';

part 'execution_history_pages.dart';
part 'execution_maximum_page.dart';

const notMaterializedRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": null,
    "route": null,
    "state": "not_materialized",
    "archive": null,
    "attempt": null,
    "revocation": null,
    "execution_events": [],
    "latest_projection": null,
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:46:31.711062Z",
  "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 3,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115",
  "sample_valid_until": "2026-10-02T01:47:31.711062Z"
}
''';
const unarmedRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": null,
    "route": {
      "route_kind": "receipt_successor",
      "approval_id": "c1829c07-df06-4fd2-9566-aa0a45e76477",
      "route_version": 1,
      "dispatch_job_id": "7c102a00-ec24-4847-a3e5-c6302fae98bf",
      "primary_receipt_id": "396fa753-6c74-4d73-a676-237138dcd5ee"
    },
    "state": "unarmed_granted",
    "archive": null,
    "attempt": {
      "run_id": "0891482a-67e7-4b18-9a22-457f588b4ab9",
      "device_id": "0a819a9d-7e83-4fa8-870a-4b353ccac4ef",
      "issued_at": "2026-10-02T01:46:33.025642Z",
      "attempt_id": "99917b98-348c-4217-b427-9f08fc1bf980",
      "expires_at": "2026-10-02T01:47:03.025642Z",
      "body_sha256": "fba790b99cf6fbce2ea675fd0cd5a46031de3ad89cc4f349957968f8e84f444c",
      "fence_version": 1,
      "segment_count": 1,
      "reservation_id": "78d14488-ed54-48ac-8ba8-28c122546c09",
      "grant_request_id": "2cd2aefd-da4f-4f6a-950c-5d5e2f10d926",
      "destination_sha256": "b6d40956b95b9e10c2fbe438758fd29915dda5c6c3eac9f16af33d1f4b752dd2"
    },
    "revocation": null,
    "execution_events": [
      {
        "event_id": "b411d185-4657-4aa9-b1bd-26939d660aa0",
        "event_kind": "grant",
        "request_id": "2cd2aefd-da4f-4f6a-950c-5d5e2f10d926",
        "recorded_at": "2026-10-02T01:46:33.025642Z",
        "lineage_after": 4,
        "lineage_before": 3,
        "approved_event_id": "ff6c8357-e791-4247-8a1d-53ecb9c75481",
        "approval_request_id": "62fc161b-2e2f-4690-8cfe-982b2676d026"
      }
    ],
    "latest_projection": null,
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:46:33.094668Z",
  "approval_id": "c1829c07-df06-4fd2-9566-aa0a45e76477",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 4,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "396fa753-6c74-4d73-a676-237138dcd5ee",
  "sample_valid_until": "2026-10-02T01:47:33.094668Z"
}
''';
const armedUnknownRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": {
      "armed_at": "2026-10-02T01:46:32.953623Z",
      "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
      "reservation_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    },
    "route": {
      "route_kind": "receipt_successor",
      "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
      "route_version": 1,
      "dispatch_job_id": "ec4162e6-8358-4734-a377-7644839b6c86",
      "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115"
    },
    "state": "armed_unknown",
    "archive": null,
    "attempt": {
      "run_id": "0891482a-67e7-4b18-9a22-457f588b4ab9",
      "device_id": "0a819a9d-7e83-4fa8-870a-4b353ccac4ef",
      "issued_at": "2026-10-02T01:46:32.881300Z",
      "attempt_id": "a81de8a2-a818-4fd6-ab32-906a45549d7f",
      "expires_at": "2026-10-02T01:47:02.881300Z",
      "body_sha256": "2e52ab517230ca113355bc5c3621b0df9607f795fccd2380f284e20665ddbe00",
      "fence_version": 1,
      "segment_count": 1,
      "reservation_id": "a70aa2fe-6e25-421b-b48f-b0744db78b77",
      "grant_request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
      "destination_sha256": "b6d40956b95b9e10c2fbe438758fd29915dda5c6c3eac9f16af33d1f4b752dd2"
    },
    "revocation": null,
    "execution_events": [
      {
        "event_id": "63a0df13-20dc-41a1-8b9b-dbc42ae82c03",
        "event_kind": "grant",
        "request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
        "recorded_at": "2026-10-02T01:46:32.881300Z",
        "lineage_after": 4,
        "lineage_before": 3,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      },
      {
        "event_id": "00e64dd3-9a5a-4766-9200-f2ae8b2c0de3",
        "event_kind": "arm",
        "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
        "recorded_at": "2026-10-02T01:46:32.953623Z",
        "lineage_after": 5,
        "lineage_before": 4,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      }
    ],
    "latest_projection": null,
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:46:33.151160Z",
  "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 5,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115",
  "sample_valid_until": "2026-10-02T01:47:33.151160Z"
}
''';
const knownEmptyPageRaw = r'''{
  "items": [],
  "limit": 20,
  "scope": "rw_receipt_successor_observations",
  "status": "available",
  "checked_at": "2026-10-02T01:46:33.213202Z",
  "approval_id": "c1829c07-df06-4fd2-9566-aa0a45e76477",
  "send_action": false,
  "carrier_proof": false,
  "after_revision": null,
  "cutoff_revision": 4,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "primary_receipt_id": "396fa753-6c74-4d73-a676-237138dcd5ee",
  "sample_valid_until": "2026-10-02T01:47:33.213202Z",
  "next_after_revision": null
}
''';
const unavailableRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "unavailable",
  "execution": null,
  "checked_at": "2026-10-02T01:46:33.269695Z",
  "approval_id": "b291c75d-eaec-418e-8473-b8b3323b0046",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": null,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": null,
  "sample_valid_until": "2026-10-02T01:47:33.269695Z"
}
''';
const unavailablePageRaw = r'''{
  "items": [],
  "limit": 20,
  "scope": "rw_receipt_successor_observations",
  "status": "unavailable",
  "checked_at": "2026-10-02T01:46:33.318781Z",
  "approval_id": "b291c75d-eaec-418e-8473-b8b3323b0046",
  "send_action": false,
  "carrier_proof": false,
  "after_revision": null,
  "cutoff_revision": 1,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "primary_receipt_id": null,
  "sample_valid_until": "2026-10-02T01:47:33.318781Z",
  "next_after_revision": null
}
''';
const knownSentRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": {
      "armed_at": "2026-10-02T01:46:32.953623Z",
      "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
      "reservation_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    },
    "route": {
      "route_kind": "receipt_successor",
      "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
      "route_version": 1,
      "dispatch_job_id": "ec4162e6-8358-4734-a377-7644839b6c86",
      "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115"
    },
    "state": "observed_sent",
    "archive": null,
    "attempt": {
      "run_id": "0891482a-67e7-4b18-9a22-457f588b4ab9",
      "device_id": "0a819a9d-7e83-4fa8-870a-4b353ccac4ef",
      "issued_at": "2026-10-02T01:46:32.881300Z",
      "attempt_id": "a81de8a2-a818-4fd6-ab32-906a45549d7f",
      "expires_at": "2026-10-02T01:47:02.881300Z",
      "body_sha256": "2e52ab517230ca113355bc5c3621b0df9607f795fccd2380f284e20665ddbe00",
      "fence_version": 1,
      "segment_count": 1,
      "reservation_id": "a70aa2fe-6e25-421b-b48f-b0744db78b77",
      "grant_request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
      "destination_sha256": "b6d40956b95b9e10c2fbe438758fd29915dda5c6c3eac9f16af33d1f4b752dd2"
    },
    "revocation": null,
    "execution_events": [
      {
        "event_id": "63a0df13-20dc-41a1-8b9b-dbc42ae82c03",
        "event_kind": "grant",
        "request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
        "recorded_at": "2026-10-02T01:46:32.881300Z",
        "lineage_after": 4,
        "lineage_before": 3,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      },
      {
        "event_id": "00e64dd3-9a5a-4766-9200-f2ae8b2c0de3",
        "event_kind": "arm",
        "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
        "recorded_at": "2026-10-02T01:46:32.953623Z",
        "lineage_after": 5,
        "lineage_before": 4,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      }
    ],
    "latest_projection": {
      "state": "observed_sent",
      "request_id": "6e80da64-3428-4f14-8b9f-8ecd0c358953",
      "recorded_at": "2026-10-02T01:46:36.523208Z",
      "lineage_revision": 59
    },
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:46:36.588916Z",
  "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 59,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115",
  "sample_valid_until": "2026-10-02T01:47:36.588916Z"
}
''';
const archivedRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": {
      "armed_at": "2026-10-02T01:46:32.953623Z",
      "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
      "reservation_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    },
    "route": {
      "route_kind": "receipt_successor",
      "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
      "route_version": 1,
      "dispatch_job_id": "ec4162e6-8358-4734-a377-7644839b6c86",
      "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115"
    },
    "state": "observed_sent",
    "archive": {
      "route": {
        "route_kind": "receipt_successor",
        "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
        "route_version": 1,
        "dispatch_job_id": "ec4162e6-8358-4734-a377-7644839b6c86",
        "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115"
      },
      "request_id": "23f781d3-299b-46c8-8a83-9874ee8bd185",
      "journal_ack": true,
      "recorded_at": "2026-10-02T01:46:37.105582Z",
      "carrier_proof": false,
      "archive_ack_id": "1c8b96e4-49f3-4ca7-ac15-c4907bf155b0",
      "send_authority": false,
      "delivery_proven": false,
      "evidence_sha256": "6da03b6bbc7588efe24bc4c217d182df5f3bb182da15abd73292e44d1b74676e",
      "callback_requests": [
        {
          "request_id": "379ebe1b-42cd-4715-9d00-26e295435f37",
          "callback_id": "d9e4f0e4-fe8b-4676-916e-cb1670be62a2",
          "request_sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        },
        {
          "request_id": "57f9a668-f5bf-49f7-bded-26ededf77e51",
          "callback_id": "5a62e03f-519b-4efe-b99b-2a5732d5afc1",
          "request_sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        }
      ]
    },
    "attempt": {
      "run_id": "0891482a-67e7-4b18-9a22-457f588b4ab9",
      "device_id": "0a819a9d-7e83-4fa8-870a-4b353ccac4ef",
      "issued_at": "2026-10-02T01:46:32.881300Z",
      "attempt_id": "a81de8a2-a818-4fd6-ab32-906a45549d7f",
      "expires_at": "2026-10-02T01:47:02.881300Z",
      "body_sha256": "2e52ab517230ca113355bc5c3621b0df9607f795fccd2380f284e20665ddbe00",
      "fence_version": 1,
      "segment_count": 1,
      "reservation_id": "a70aa2fe-6e25-421b-b48f-b0744db78b77",
      "grant_request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
      "destination_sha256": "b6d40956b95b9e10c2fbe438758fd29915dda5c6c3eac9f16af33d1f4b752dd2"
    },
    "revocation": null,
    "execution_events": [
      {
        "event_id": "63a0df13-20dc-41a1-8b9b-dbc42ae82c03",
        "event_kind": "grant",
        "request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
        "recorded_at": "2026-10-02T01:46:32.881300Z",
        "lineage_after": 4,
        "lineage_before": 3,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      },
      {
        "event_id": "00e64dd3-9a5a-4766-9200-f2ae8b2c0de3",
        "event_kind": "arm",
        "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
        "recorded_at": "2026-10-02T01:46:32.953623Z",
        "lineage_after": 5,
        "lineage_before": 4,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      }
    ],
    "latest_projection": {
      "state": "observed_sent",
      "request_id": "6e80da64-3428-4f14-8b9f-8ecd0c358953",
      "recorded_at": "2026-10-02T01:46:36.523208Z",
      "lineage_revision": 59
    },
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:46:37.169714Z",
  "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 59,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115",
  "sample_valid_until": "2026-10-02T01:47:37.169714Z"
}
''';
const lateUncertainRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": {
      "armed_at": "2026-10-02T01:46:32.953623Z",
      "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
      "reservation_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    },
    "route": {
      "route_kind": "receipt_successor",
      "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
      "route_version": 1,
      "dispatch_job_id": "ec4162e6-8358-4734-a377-7644839b6c86",
      "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115"
    },
    "state": "uncertain",
    "archive": {
      "route": {
        "route_kind": "receipt_successor",
        "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
        "route_version": 1,
        "dispatch_job_id": "ec4162e6-8358-4734-a377-7644839b6c86",
        "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115"
      },
      "request_id": "23f781d3-299b-46c8-8a83-9874ee8bd185",
      "journal_ack": true,
      "recorded_at": "2026-10-02T01:46:37.105582Z",
      "carrier_proof": false,
      "archive_ack_id": "1c8b96e4-49f3-4ca7-ac15-c4907bf155b0",
      "send_authority": false,
      "delivery_proven": false,
      "evidence_sha256": "6da03b6bbc7588efe24bc4c217d182df5f3bb182da15abd73292e44d1b74676e",
      "callback_requests": [
        {
          "request_id": "379ebe1b-42cd-4715-9d00-26e295435f37",
          "callback_id": "d9e4f0e4-fe8b-4676-916e-cb1670be62a2",
          "request_sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        },
        {
          "request_id": "57f9a668-f5bf-49f7-bded-26ededf77e51",
          "callback_id": "5a62e03f-519b-4efe-b99b-2a5732d5afc1",
          "request_sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        }
      ]
    },
    "attempt": {
      "run_id": "0891482a-67e7-4b18-9a22-457f588b4ab9",
      "device_id": "0a819a9d-7e83-4fa8-870a-4b353ccac4ef",
      "issued_at": "2026-10-02T01:46:32.881300Z",
      "attempt_id": "a81de8a2-a818-4fd6-ab32-906a45549d7f",
      "expires_at": "2026-10-02T01:47:02.881300Z",
      "body_sha256": "2e52ab517230ca113355bc5c3621b0df9607f795fccd2380f284e20665ddbe00",
      "fence_version": 1,
      "segment_count": 1,
      "reservation_id": "a70aa2fe-6e25-421b-b48f-b0744db78b77",
      "grant_request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
      "destination_sha256": "b6d40956b95b9e10c2fbe438758fd29915dda5c6c3eac9f16af33d1f4b752dd2"
    },
    "revocation": null,
    "execution_events": [
      {
        "event_id": "63a0df13-20dc-41a1-8b9b-dbc42ae82c03",
        "event_kind": "grant",
        "request_id": "26ba6007-ef56-47de-9d75-1d538c09e749",
        "recorded_at": "2026-10-02T01:46:32.881300Z",
        "lineage_after": 4,
        "lineage_before": 3,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      },
      {
        "event_id": "00e64dd3-9a5a-4766-9200-f2ae8b2c0de3",
        "event_kind": "arm",
        "request_id": "f7a0ef65-1b4c-4453-b55f-c98265c11138",
        "recorded_at": "2026-10-02T01:46:32.953623Z",
        "lineage_after": 5,
        "lineage_before": 4,
        "approved_event_id": "65ca569b-1f18-486a-bd5d-3b6c7914a8e4",
        "approval_request_id": "0556be9d-9260-4a15-80d5-536c81a49122"
      }
    ],
    "latest_projection": {
      "state": "uncertain",
      "request_id": "08712519-f6ec-49d1-8d1f-8f3cf1255440",
      "recorded_at": "2026-10-02T01:46:37.224839Z",
      "lineage_revision": 60
    },
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:46:37.300974Z",
  "approval_id": "cce82fac-0183-4b60-8d95-de26308a22f1",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 60,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "f147bf10-a67c-49c2-837d-1b472064e115",
  "sample_valid_until": "2026-10-02T01:47:37.300974Z"
}
''';
const revokedRaw = r'''{
  "scope": "rw_receipt_successor_execution",
  "status": "available",
  "execution": {
    "arm": null,
    "route": {
      "route_kind": "receipt_successor",
      "approval_id": "95a6fa6b-139f-4412-92d5-7340efb1b1a1",
      "route_version": 1,
      "dispatch_job_id": "bd096cca-fccd-4444-bc1a-454bbd4ead83",
      "primary_receipt_id": "7c61bf80-58f3-4827-960a-4a4872e5f62f"
    },
    "state": "unarmed_revoked",
    "archive": null,
    "attempt": {
      "run_id": "8e2c4ebf-627c-4769-a10e-491b8f6eeef5",
      "device_id": "13ee2aeb-5c85-4b78-ac9f-66fa1a087390",
      "issued_at": "2026-10-02T01:49:29.973202Z",
      "attempt_id": "0bf7bb5f-831a-4e7d-87d0-c278107bad71",
      "expires_at": "2026-10-02T01:49:59.973202Z",
      "body_sha256": "71fd54644f48e57c1a63b48fb460d7d322b957f6743b69c47cc184232b05675f",
      "fence_version": 1,
      "segment_count": 1,
      "reservation_id": "2539a3b1-2de8-4121-8e43-fa9f6c3994f0",
      "grant_request_id": "c883db45-a1a1-41f7-b3de-b2ccbbcf2f4f",
      "destination_sha256": "b6d40956b95b9e10c2fbe438758fd29915dda5c6c3eac9f16af33d1f4b752dd2"
    },
    "revocation": {
      "recorded_at": "2026-10-02T01:49:34.898156Z",
      "approval_event_id": "27c2c039-d6b3-4eb6-980b-5aa9430fbd6d"
    },
    "execution_events": [
      {
        "event_id": "8963c8e4-6875-4083-ba03-4f1de2df6856",
        "event_kind": "grant",
        "request_id": "c883db45-a1a1-41f7-b3de-b2ccbbcf2f4f",
        "recorded_at": "2026-10-02T01:49:29.973202Z",
        "lineage_after": 4,
        "lineage_before": 3,
        "approved_event_id": "8629b17b-f058-4d6d-9ea1-85aecd7cc642",
        "approval_request_id": "6356f3ab-8485-4d6f-b8f8-73ed6b8fbbfb"
      }
    ],
    "latest_projection": null,
    "observation_count": null
  },
  "checked_at": "2026-10-02T01:49:34.949460Z",
  "approval_id": "95a6fa6b-139f-4412-92d5-7340efb1b1a1",
  "send_action": false,
  "carrier_proof": false,
  "cutoff_revision": 5,
  "delivery_proven": false,
  "contract_version": 4,
  "financial_action": false,
  "retained_primary": true,
  "primary_receipt_id": "7c61bf80-58f3-4827-960a-4a4872e5f62f",
  "sample_valid_until": "2026-10-02T01:50:34.949460Z"
}
''';

Map<String, dynamic> decoded(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;
AdminReceiptSuccessorExecutionSnapshot snapshot(String raw) {
  final row = decoded(raw);
  return AdminReceiptSuccessorExecutionSnapshot.parse(
    row,
    row['approval_id'] as String,
    row['primary_receipt_id'] as String? ??
        '00000000-0000-0000-0000-000000000001',
  );
}

class ExecutionFixture {
  final original = snapshot(knownSentRaw);
  late final String approval = original.approvalId,
      root = original.primaryReceiptId!;
  DateTime now = snapshot(knownSentRaw).checkedAt;
  List<Map<String, dynamic>> get pages =>
      (jsonDecode(fixedPagesRaw) as List).cast<Map<String, dynamic>>();
}
