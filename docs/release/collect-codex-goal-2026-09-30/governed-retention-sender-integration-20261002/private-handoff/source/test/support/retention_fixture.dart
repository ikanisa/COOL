import 'dart:convert';
import 'package:collect_app/admin/core/admin_sender_retention_models.dart';

Map<String, dynamic> decoded(String raw) =>
    Map<String, dynamic>.from(jsonDecode(raw) as Map);
const readInitialRaw = r'''{
  "cron": {
    "state": "inactive",
    "job_id": 12,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "scope": "rw_receipt_retention_controls",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "retention": {
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "cold_expiry_allowed": false,
    "raw_financial_expiry_allowed": false,
    "unknown_outcome_hold_required": true,
    "late_callback_bindings_retained": true
  },
  "checked_at": "2026-10-02T03:19:23.775020Z",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "configuration": {
    "enabled": false,
    "revision": 6,
    "byte_limit": 4194304,
    "updated_at": "2026-10-02T01:59:18.840289Z",
    "batch_limit": 25
  },
  "contract_version": 1,
  "mutation_allowed": true,
  "platform_policies": {
    "android": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "e72be359be948dd74ec1d84ce83aa8238e13a93d9abe5a7e9d639d157722ab1c"
    },
    "scheduler": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "559819220b3503ddb0ad13af669cf878bb00107b0c88accae0b86a3fb042c5b6"
    }
  },
  "sample_valid_until": "2026-10-02T03:20:23.775020Z"
}
''';
const readNoManageRaw = r'''{
  "cron": {
    "state": "inactive",
    "job_id": 16,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "scope": "rw_receipt_retention_controls",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "retention": {
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "cold_expiry_allowed": false,
    "raw_financial_expiry_allowed": false,
    "unknown_outcome_hold_required": true,
    "late_callback_bindings_retained": true
  },
  "checked_at": "2026-10-02T03:04:40.175997Z",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "configuration": {
    "enabled": false,
    "revision": 7,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:39.047398Z",
    "batch_limit": 12
  },
  "contract_version": 1,
  "mutation_allowed": false,
  "platform_policies": {
    "android": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "e72be359be948dd74ec1d84ce83aa8238e13a93d9abe5a7e9d639d157722ab1c"
    },
    "scheduler": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "559819220b3503ddb0ad13af669cf878bb00107b0c88accae0b86a3fb042c5b6"
    }
  },
  "sample_valid_until": "2026-10-02T03:05:40.175997Z"
}
''';
const cronUnavailableRaw = r'''{
  "cron": {
    "state": "unavailable",
    "job_id": null,
    "schedule": null,
    "command_sha256": null
  },
  "scope": "rw_receipt_retention_controls",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "retention": {
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "cold_expiry_allowed": false,
    "raw_financial_expiry_allowed": false,
    "unknown_outcome_hold_required": true,
    "late_callback_bindings_retained": true
  },
  "checked_at": "2026-10-02T03:04:40.554398Z",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "configuration": {
    "enabled": false,
    "revision": 7,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:39.047398Z",
    "batch_limit": 12
  },
  "contract_version": 1,
  "mutation_allowed": true,
  "platform_policies": {
    "android": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "e72be359be948dd74ec1d84ce83aa8238e13a93d9abe5a7e9d639d157722ab1c"
    },
    "scheduler": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "559819220b3503ddb0ad13af669cf878bb00107b0c88accae0b86a3fb042c5b6"
    }
  },
  "sample_valid_until": "2026-10-02T03:05:40.554398Z"
}
''';
const recordedRaw = r'''{
  "scope": "rw_receipt_retention_control_request",
  "intent": {
    "reason": "Synthetic governed maintenance test",
    "enabled": false,
    "actor_id": "99780000-0000-4000-8000-000000000001",
    "byte_limit": 1048576,
    "expires_at": "2026-10-02T03:21:03.831180Z",
    "request_id": "36645690-8adb-413f-901b-b1c899fa56a6",
    "session_id": "99780000-0000-4000-8000-000000010001",
    "batch_limit": 12,
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "expected_revision": 6
  },
  "status": "recorded",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "after_cron": {
    "state": "inactive",
    "job_id": 16,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "request_id": "36645690-8adb-413f-901b-b1c899fa56a6",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "before_cron": {
    "state": "inactive",
    "job_id": 12,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "recorded_at": "2026-10-02T03:19:23.893574Z",
  "contract_version": 1,
  "fingerprint_sha256": "db68606041a262a8bf5093112444d6f7b3476b990f41165ed223f35c214b78a1",
  "after_configuration": {
    "enabled": false,
    "revision": 7,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:19:23.892676Z",
    "batch_limit": 12
  },
  "before_configuration": {
    "enabled": false,
    "revision": 6,
    "byte_limit": 4194304,
    "updated_at": "2026-10-02T01:59:18.840289Z",
    "batch_limit": 25
  }
}
''';
const recoveredRaw = r'''{
  "scope": "rw_receipt_retention_control_request",
  "intent": {
    "reason": "Synthetic governed maintenance test",
    "enabled": false,
    "actor_id": "99780000-0000-4000-8000-000000000001",
    "byte_limit": 1048576,
    "expires_at": "2026-10-02T03:21:03.831180Z",
    "request_id": "36645690-8adb-413f-901b-b1c899fa56a6",
    "session_id": "99780000-0000-4000-8000-000000010001",
    "batch_limit": 12,
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "expected_revision": 6
  },
  "status": "recorded",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "after_cron": {
    "state": "inactive",
    "job_id": 16,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "request_id": "36645690-8adb-413f-901b-b1c899fa56a6",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "before_cron": {
    "state": "inactive",
    "job_id": 12,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "recorded_at": "2026-10-02T03:19:23.893574Z",
  "contract_version": 1,
  "fingerprint_sha256": "db68606041a262a8bf5093112444d6f7b3476b990f41165ed223f35c214b78a1",
  "after_configuration": {
    "enabled": false,
    "revision": 7,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:19:23.892676Z",
    "batch_limit": 12
  },
  "before_configuration": {
    "enabled": false,
    "revision": 6,
    "byte_limit": 4194304,
    "updated_at": "2026-10-02T01:59:18.840289Z",
    "batch_limit": 25
  }
}
''';

const enabledRaw = r'''{
  "scope": "rw_receipt_retention_control_request",
  "intent": {
    "reason": "Synthetic governed maintenance test",
    "enabled": true,
    "actor_id": "99780000-0000-4000-8000-000000000001",
    "byte_limit": 1048576,
    "expires_at": "2026-10-02T03:06:18.988061Z",
    "request_id": "e42d90ef-85ce-48d9-924b-825692861ccc",
    "session_id": "99780000-0000-4000-8000-000000010001",
    "batch_limit": 12,
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "expected_revision": 7
  },
  "status": "recorded",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "after_cron": {
    "state": "active",
    "job_id": 17,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "request_id": "e42d90ef-85ce-48d9-924b-825692861ccc",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "before_cron": {
    "state": "inactive",
    "job_id": 16,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "recorded_at": "2026-10-02T03:04:40.818329Z",
  "contract_version": 1,
  "fingerprint_sha256": "25781f59161d73e9a32f853df8abecf61dd42c50068f6cfbed25bba05c613a0b",
  "after_configuration": {
    "enabled": true,
    "revision": 8,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:40.817452Z",
    "batch_limit": 12
  },
  "before_configuration": {
    "enabled": false,
    "revision": 7,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:39.047398Z",
    "batch_limit": 12
  }
}
''';
const readEnabledRaw = r'''{
  "cron": {
    "state": "active",
    "job_id": 17,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "scope": "rw_receipt_retention_controls",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "retention": {
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "cold_expiry_allowed": false,
    "raw_financial_expiry_allowed": false,
    "unknown_outcome_hold_required": true,
    "late_callback_bindings_retained": true
  },
  "checked_at": "2026-10-02T03:04:40.871668Z",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "configuration": {
    "enabled": true,
    "revision": 8,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:40.817452Z",
    "batch_limit": 12
  },
  "contract_version": 1,
  "mutation_allowed": true,
  "platform_policies": {
    "android": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "e72be359be948dd74ec1d84ce83aa8238e13a93d9abe5a7e9d639d157722ab1c"
    },
    "scheduler": {
      "observed_at": null,
      "verification_state": "release_declared",
      "specification_sha256": "559819220b3503ddb0ad13af669cf878bb00107b0c88accae0b86a3fb042c5b6"
    }
  },
  "sample_valid_until": "2026-10-02T03:05:40.871668Z"
}
''';
const disabledRaw = r'''{
  "scope": "rw_receipt_retention_control_request",
  "intent": {
    "reason": "Synthetic governed maintenance test",
    "enabled": false,
    "actor_id": "99780000-0000-4000-8000-000000000001",
    "byte_limit": 1048576,
    "expires_at": "2026-10-02T03:06:18.988061Z",
    "request_id": "18c4675a-9149-4a70-94be-144d34771520",
    "session_id": "99780000-0000-4000-8000-000000010001",
    "batch_limit": 12,
    "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
    "expected_revision": 8
  },
  "status": "recorded",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "after_cron": {
    "state": "inactive",
    "job_id": 19,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "request_id": "18c4675a-9149-4a70-94be-144d34771520",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "before_cron": {
    "state": "active",
    "job_id": 17,
    "schedule": "* * * * *",
    "command_sha256": "765ed6e1d6b8067b3fc886d80c66f2e7111aa6e1613e517d466167ecc5e19674"
  },
  "recorded_at": "2026-10-02T03:04:48.373608Z",
  "contract_version": 1,
  "fingerprint_sha256": "6eea20077ea027d3f930eb5d580852780bc76fa85f4e870c8c54206a9268fa36",
  "after_configuration": {
    "enabled": false,
    "revision": 9,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:48.372292Z",
    "batch_limit": 12
  },
  "before_configuration": {
    "enabled": true,
    "revision": 8,
    "byte_limit": 1048576,
    "updated_at": "2026-10-02T03:04:40.817452Z",
    "batch_limit": 12
  }
}
''';
AdminRetentionIntent originalIntent() =>
    AdminRetentionIntent.parse(decoded(recordedRaw)['intent']);
String get actor => originalIntent().actorId;
String get session => originalIntent().sessionId;
DateTime get fixtureNow =>
    originalIntent().expiresAt.subtract(const Duration(seconds: 100));
AdminRetentionSnapshot initial() =>
    AdminRetentionSnapshot.parse(decoded(readInitialRaw), actor, session);
AdminRetentionRequest recorded() =>
    AdminRetentionRequest.parse(decoded(recordedRaw), originalIntent());
const gatewayActiveRaw = r'''{
  "rows": [
    {
      "state": "pending",
      "health": null,
      "device_id": "b02f7194-816a-4dc5-beb8-64e9d34324ce",
      "key_sha256": "dc0ce633dbcc913dafafa4b89ac44d8ce683fdfc3f60c8bdf21213b9f2b534ba",
      "revoked_at": null,
      "enrolled_at": "2026-09-30T22:47:41.926854Z",
      "activated_at": null,
      "installation_id": "4318a478-bb42-44ba-8554-00503a008735",
      "last_owner_action": {
        "action": "enroll",
        "receipt": {
          "replay": false,
          "device_id": "b02f7194-816a-4dc5-beb8-64e9d34324ce",
          "request_id": "77886760-b30e-48a6-8064-4bc34ea9ad27",
          "recorded_at": "2026-09-30T22:47:41.926854Z",
          "state_at_action": "pending"
        }
      },
      "dispatch_authority": "pending",
      "dispatch_available": false,
      "callback_observations": {
        "sent": 0,
        "total": 0,
        "delivery": 0
      },
      "signing_certificate_sha256": "2222222222222222222222222222222222222222222222222222222222222222"
    },
    {
      "state": "active",
      "health": {
        "network": "unvalidated",
        "freshness": "fresh",
        "telephony": "unknown",
        "ingested_at": "2026-09-30T22:47:44.401366Z",
        "local_pause": true,
        "reported_at": "2026-09-30T22:47:44.077000Z",
        "sim_selected": false,
        "carrier_proof": false,
        "observation_id": "b39f39d4-3bd7-462e-b1f2-63bdb0f39f58",
        "sms_permission": false,
        "observation_valid_until": "2026-09-30T22:49:44.077000Z"
      },
      "device_id": "ab7b10e5-99a1-4252-af4a-92f144de929c",
      "key_sha256": "5cd252fb0ce8932436faf8ccd1040981b89ee4ad6b9fe9e2a2b7e71aacb27cd3",
      "revoked_at": null,
      "enrolled_at": "2026-09-30T22:47:41.674653Z",
      "activated_at": "2026-09-30T22:47:45.355049Z",
      "installation_id": "a6690ed4-1cf3-472a-a058-f4f631078a5f",
      "last_owner_action": {
        "action": "activate",
        "receipt": {
          "replay": false,
          "device_id": "ab7b10e5-99a1-4252-af4a-92f144de929c",
          "request_id": "8f4dfb52-a75e-4df7-bab6-18a2e4cce302",
          "recorded_at": "2026-09-30T22:47:45.355049Z",
          "state_at_action": "active"
        }
      },
      "dispatch_authority": "pending",
      "dispatch_available": false,
      "callback_observations": {
        "sent": 0,
        "total": 0,
        "delivery": 0
      },
      "signing_certificate_sha256": "1111111111111111111111111111111111111111111111111111111111111111"
    }
  ],
  "limit": 20,
  "scope": "platform_global",
  "total": 2,
  "checked_at": "2026-09-30T22:47:45.892362Z",
  "next_cursor": null,
  "contract_version": 1,
  "sample_valid_until": "2026-09-30T22:48:45.892362Z"
}
''';

const notRecordedDelayedPredeadlineRaw = r'''{
  "scope": "rw_receipt_retention_control_request",
  "intent": null,
  "status": "not_recorded",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "after_cron": null,
  "checked_at": "2026-10-02T03:19:24.406354Z",
  "request_id": "ca3b4e18-f087-4a06-b342-78506ce43332",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "before_cron": null,
  "recorded_at": null,
  "contract_version": 1,
  "fingerprint_sha256": "ab2000805e9e3bb3e8e3577892434e8210ec0fe4e0cac199b2f1702e2f82bce9",
  "after_configuration": null,
  "before_configuration": null
}
''';

const notRecordedAfterDeadlineRaw = r'''{
  "scope": "rw_receipt_retention_control_request",
  "intent": null,
  "status": "not_recorded",
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "after_cron": null,
  "checked_at": "2026-10-02T03:19:25.772369Z",
  "request_id": "ca3b4e18-f087-4a06-b342-78506ce43332",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "before_cron": null,
  "recorded_at": null,
  "contract_version": 1,
  "fingerprint_sha256": "ab2000805e9e3bb3e8e3577892434e8210ec0fe4e0cac199b2f1702e2f82bce9",
  "after_configuration": null,
  "before_configuration": null
}
''';

const missingIntentRaw = r'''{
  "reason": "Synthetic governed maintenance test",
  "enabled": false,
  "actor_id": "99780000-0000-4000-8000-000000000001",
  "byte_limit": 1048576,
  "expires_at": "2026-10-02T03:19:25.300755Z",
  "request_id": "ca3b4e18-f087-4a06-b342-78506ce43332",
  "session_id": "99780000-0000-4000-8000-000000010001",
  "batch_limit": 12,
  "protocol_sha256": "c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3",
  "expected_revision": 7
}
''';
AdminRetentionIntent missingIntent() =>
    AdminRetentionIntent.parse(decoded(missingIntentRaw));
