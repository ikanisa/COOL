#!/usr/bin/env python3
"""Offline structural checks; never a signature, policy or invocation proof.

Requires an already installed jsonschema package; no network or installation.
Observed SQL results remain separate from constructed Edge envelopes and hostile
fixtures. CONTRACT.md and the real SQL/Edge/native validators enforce contextual
bindings, digests, clocks, byte bounds and authenticated one-time authority.
"""

from __future__ import annotations

import argparse
import copy
from datetime import datetime
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = Path(__file__).with_name("schema.json")
FIXTURES = {
    "observed-arm.json": "arm_dispatch_result",
    "observed-complete-callback.json": "callback_result",
    "observed-concurrent-grants.json": "dispatch_grant_result",
    "observed-contradictory-callback.json": "callback_result",
    "observed-grant-paused.json": "dispatch_grant_result",
    "observed-grant-reconciliation.json": "reconcile_result",
    "observed-grant.json": "dispatch_grant_result",
    "observed-owner-automatic-history.json": "owner_receipt_read",
    "observed-partial-callback.json": "callback_result",
    "observed-status.json": "attempt_status_result",
}


def strict_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON object key")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=strict_pairs)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--observed-dir", type=Path, default=ROOT / ".cache/android-dispatch-attempt8")
    parser.add_argument("--report", type=Path, help="New report path; existing files are never overwritten")
    args = parser.parse_args()
    observed_dir = args.observed_dir.resolve()
    source_paths = [SCHEMA, Path(__file__).resolve(), SCHEMA.with_name("CONTRACT.md"), ROOT / "supabase/functions/collect-android-gateway/handler.ts"]
    source_paths += [observed_dir / name for name in sorted(FIXTURES)]
    source_hashes = {relative(path): sha256(path) for path in source_paths}
    observed_names = {path.name for path in observed_dir.glob("observed-*.json")}
    if observed_names != set(FIXTURES):
        raise AssertionError(f"Observed fixture coverage differs: {sorted(observed_names ^ set(FIXTURES))}")

    schema = read_json(SCHEMA)
    Draft202012Validator.check_schema(schema)
    formats = FormatChecker()

    # jsonschema's optional RFC3339 dependency is not assumed to be installed.
    # Assert calendar validity locally instead of silently ignoring date-time.
    @formats.checks("date-time", raises=(ValueError, OverflowError))
    def valid_calendar_time(value):
        if not isinstance(value, str):
            return True
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.tzinfo is not None

    validators = {name: Draft202012Validator({"$schema": schema["$schema"], "$defs": schema["$defs"], "$ref": "#/$defs/" + name}, format_checker=formats) for name in schema["$defs"]}
    validators["root"] = Draft202012Validator(schema, format_checker=formats)
    checks = []

    def check(name, definition, value, expected=True, category="hostile"):
        errors = sorted(validators[definition].iter_errors(value), key=lambda error: str(error.path))
        valid = not errors
        checks.append({"name": name, "definition": definition, "category": category, "expected_valid": expected, "observed_valid": valid})
        if valid != expected:
            detail = "; ".join(error.message for error in errors[:3])
            raise AssertionError(f"{name}: expected_valid={expected}, observed_valid={valid}; {detail}")

    observed = {name: read_json(observed_dir / name) for name in FIXTURES}
    baselines = []
    for name, definition in FIXTURES.items():
        values = observed[name] if name == "observed-concurrent-grants.json" else [observed[name]]
        if not isinstance(values, list) or not values:
            raise AssertionError("Concurrent fixture must contain observed results")
        for index, value in enumerate(values):
            label = name + (f"[{index}]" if len(values) > 1 else "")
            check(label, definition, value, category="observed_result")
            baselines.append((label, definition, value))

    grant = observed["observed-grant.json"]
    arm = observed["observed-arm.json"]
    callback = observed["observed-partial-callback.json"]
    status = observed["observed-status.json"]
    reconciliation = observed["observed-grant-reconciliation.json"]
    owner = observed["observed-owner-automatic-history.json"]
    # Synthetic requests bind to observed values only to exercise schema shape.
    # They were never submitted or authenticated and do not prove request history.
    request_id = "11111111-1111-4111-8111-111111111111"
    callback_plan = [
        {"segment_index": index, "sent_callback_id": f"22222222-2222-4222-8222-{index * 2 + 1:012d}", "delivery_callback_id": f"22222222-2222-4222-8222-{index * 2 + 2:012d}"}
        for index in range(grant["segment_count"])
    ]
    payloads = {
        "dispatch_grant": {},
        "arm_dispatch": {"attempt_id": grant["attempt_id"], "fence_version": grant["fence_version"], "body_sha256": grant["body_sha256"], "destination_sha256": grant["destination_sha256"], "reservation_sha256": arm["reservation_sha256"], "callbacks": callback_plan},
        "callback": {"callback_id": callback["callback_id"], "attempt_id": grant["attempt_id"], "fence_version": grant["fence_version"], "segment_index": 0, "segment_count": grant["segment_count"], "body_sha256": grant["body_sha256"], "destination_sha256": grant["destination_sha256"], "callback_kind": "sent", "result_code": -1, "tp_status": None, "occurred_at": grant["issued_at"]},
        "reconcile": {"target_request_id": grant["request_id"]},
        "attempt_status": {"attempt_id": grant["attempt_id"], "fence_version": grant["fence_version"]},
    }
    results = {"dispatch_grant": grant, "arm_dispatch": arm, "callback": callback, "reconcile": reconciliation, "attempt_status": status}
    requests = {}
    responses = {}
    for action, payload in payloads.items():
        request = {"contract_version": 2, "action": action, "device_id": grant["device_id"], "request_id": request_id, "issued_at": grant["issued_at"], "payload": payload}
        response = {"contract_version": 2, "action": action, "device_id": grant["device_id"], "request_id": results[action].get("request_id", request_id), "result": results[action]}
        requests[action] = request
        responses[action] = response
        for definition, value, category in [(action + "_payload", payload, "constructed_payload"), (action + "_request", request, "constructed_envelope"), ("root", request, "constructed_envelope"), (action + "_response", response, "constructed_envelope"), ("root", response, "constructed_envelope")]:
            check(action + ":" + definition, definition, value, category=category)
        baselines.extend([(action + "_payload", action + "_payload", payload), (action + "_request", action + "_request", request), (action + "_response", action + "_response", response)])

    check("owner_read:root", "root", owner, category="observed_result")
    empty_owner = {**owner, "automatic_attempt": None}
    check("owner_read:no_attempt", "owner_receipt_read", empty_owner, category="constructed_result")
    unknown_lookup = {"target_request_id": request_id, "outcome": "unknown", "recorded_action": None, "recorded_result": None}
    check("reconcile:unknown", "reconcile_result", unknown_lookup, category="constructed_result")
    for action in ["dispatch_grant", "arm_dispatch"]:
        redacted_lookup = {**reconciliation, "recorded_action": action}
        check("reconcile:redacted:" + action, "reconcile_result", redacted_lookup, category="constructed_result")
        check("reconcile:recovered_authority:" + action, "reconcile_result", {**redacted_lookup, "recorded_result": results[action]}, False)
        check("reconcile:refused_body:" + action, "reconcile_result", {**redacted_lookup, "recorded_result": {**redacted_lookup["recorded_result"], "body": "recovered"}}, False)
        check("reconcile:refusal_replay_false:" + action, "reconcile_result", {**redacted_lookup, "recorded_result": {**redacted_lookup["recorded_result"], "replay": False}}, False)
    check("reconcile:callback", "reconcile_result", {**reconciliation, "recorded_action": "callback", "recorded_result": callback}, category="constructed_result")
    check("reconcile:read_is_not_recorded", "reconcile_result", {**reconciliation, "recorded_action": "attempt_status", "recorded_result": status}, False)
    check("reconcile:unknown_cannot_recover", "reconcile_result", {**unknown_lookup, "recorded_result": grant}, False)

    for label, definition, baseline in baselines:
        check(label + ":extra_key", definition, {**baseline, "privileged_recovered_field": "forbidden"}, False)
        for key in baseline:
            missing = copy.deepcopy(baseline)
            del missing[key]
            check(label + ":missing:" + key, definition, missing, False)

    def changed(name, definition, baseline, key, value):
        check(name, definition, {**baseline, key: value}, False)

    for action in payloads:
        changed(action + ":version1", "root", requests[action], "contract_version", 1)
        changed(action + ":foreign_action", "root", requests[action], "action", "heartbeat")
        changed(action + ":refused_caller_body", action + "_payload", payloads[action], "body", "caller supplied")
        changed(action + ":refused_caller_destination", action + "_payload", payloads[action], "destination_e164", grant["destination_e164"])
    for key in ["run_id", "policy_revision", "segment_count", "collection_id", "principal_id", "balance", "country"]:
        changed("grant:refused_selector:" + key, "dispatch_grant_payload", {}, key, 1)
    for definition, baseline in [("dispatch_granted", grant), ("dispatch_armed", arm)]:
        changed(definition + ":replay_success", definition, baseline, "replay", True)
        changed(definition + ":fractional_fence", definition, baseline, "fence_version", 1.5)
        changed(definition + ":boolean_fence", definition, baseline, "fence_version", True)
        changed(definition + ":zero_fence", definition, baseline, "fence_version", 0)
        changed(definition + ":fence_above_cap", definition, baseline, "fence_version", 1000000001)
    for key in ["body", "destination_e164", "reservation_sha256", "callbacks", "spki", "request_sha256"]:
        changed("refusal:privileged:" + key, "dispatch_refusal", observed["observed-grant-paused.json"], key, "forbidden")
        changed("owner:privileged:" + key, "owner_automatic_attempt", owner["automatic_attempt"], key, "forbidden")
    for definition, baseline in [("callback_result", callback), ("attempt_status_result", status), ("owner_automatic_attempt", owner["automatic_attempt"])]:
        for key in ["sent_observations", "delivery_observations"]:
            for suffix, value in [("negative", -1), ("over_cap", 11), ("fractional", 1.1), ("boolean", True)]:
                changed(definition + ":" + key + ":" + suffix, definition, baseline, key, value)
        changed(definition + ":carrier_attestation", definition, baseline, "carrier_proof", True)
        changed(definition + ":delivery_conclusion", definition, baseline, "state", "delivered")
        conflicted_sent = {**baseline, "state": "observed_sent", "conflicting_observations": True}
        check(definition + ":observed_sent_conflict", definition, conflicted_sent, False)
    changed("status:terminal_compaction", "attempt_status_result", status, "terminal_archive_ack", True)
    check("status:granted_has_no_arm", "attempt_status_result", {**status, "state": "granted", "armed_at": None}, category="constructed_result")
    changed("status:granted_with_arm", "attempt_status_result", {**status, "state": "granted"}, "armed_at", arm["armed_at"])
    for suffix, value in [("empty", []), ("eleven", callback_plan * 6), ("duplicate_item", [callback_plan[0], callback_plan[0]])]:
        changed("arm:plan:" + suffix, "arm_dispatch_payload", payloads["arm_dispatch"], "callbacks", value)
    changed("arm:plan_extra_key", "callback_plan_item", callback_plan[0], "callback_kind", "sent")
    changed("arm:plan_index_over_cap", "callback_plan_item", callback_plan[0], "segment_index", 10)
    for name, definition, value in [
        ("grant:empty_body", "dispatch_granted", {**grant, "body": ""}),
        ("grant:body_above_cap", "dispatch_granted", {**grant, "body": "x" * 1001}),
        ("grant:foreign_destination", "dispatch_granted", {**grant, "destination_e164": "+254788978201"}),
        ("grant:unsupported_rwanda_prefix", "dispatch_granted", {**grant, "destination_e164": "+250718978201"}),
        ("grant:segment_count_above_cap", "dispatch_granted", {**grant, "segment_count": 11}),
        ("grant:policy_revision_over_cap", "dispatch_granted", {**grant, "policy_revision": 1000000001}),
        ("grant:uppercase_digest", "dispatch_granted", {**grant, "body_sha256": "A" * 64}),
        ("grant:short_digest", "dispatch_granted", {**grant, "body_sha256": "a" * 63}),
        ("grant:malformed_uuid", "dispatch_granted", {**grant, "attempt_id": "not-a-uuid"}),
        ("grant:nonUTC_time", "dispatch_granted", {**grant, "issued_at": "2026-10-01T12:07:31+00:00"}),
        ("grant:excess_time_precision", "dispatch_granted", {**grant, "issued_at": "2026-10-01T12:07:31.1234567Z"}),
        ("grant:invalid_calendar_time", "dispatch_granted", {**grant, "issued_at": "2026-02-30T12:07:31Z"}),
        ("callback:unsupported_kind", "callback_payload", {**payloads["callback"], "callback_kind": "delivered"}),
        ("callback:result_code_over_cap", "callback_payload", {**payloads["callback"], "result_code": 201}),
        ("callback:tp_status_over_cap", "callback_payload", {**payloads["callback"], "tp_status": 256}),
        ("refusal:invented_code", "dispatch_refusal", {**observed["observed-grant-paused.json"], "code": "SAFE_TO_RETRY"}),
    ]:
        check(name, definition, value, False)

    # Positive limitation probes demonstrate why structural validity is insufficient.
    for name, definition, value in [
        ("runtime_required:actual_body_digest", "dispatch_granted", {**grant, "body_sha256": "0" * 64}),
        ("runtime_required:lease_order_freshness", "dispatch_granted", {**grant, "expires_at": "2000-01-01T00:00:00Z"}),
        ("runtime_required:response_request_binding", "root", {**responses["dispatch_grant"], "request_id": request_id}),
        ("runtime_required:status_count_relationship", "attempt_status_result", {**status, "segment_count": 1, "sent_observations": 2}),
        ("runtime_required:callback_plan_UUID_distinctness", "arm_dispatch_payload", {**payloads["arm_dispatch"], "callbacks": [{**callback_plan[0], "delivery_callback_id": callback_plan[0]["sent_callback_id"]}]}),
    ]:
        check(name, definition, value, category="structural_only_limit")

    after_hashes = {relative(path): sha256(path) for path in source_paths}
    if source_hashes != after_hashes:
        raise AssertionError("Source changed during schema validation")
    categories = {category: sum(item["category"] == category for item in checks) for category in sorted({item["category"] for item in checks})}
    report = {
        "schema_draft": "2020-12",
        "jsonschema_version": importlib.metadata.version("jsonschema"),
        "date_time_assertions": "Explicit local ISO-8601 calendar check plus schema UTC/precision pattern; no optional format dependency required",
        "network_used": False,
        "installed_dependencies": False,
        "scope": "Offline structural schema only; observed SQL results and synthetic envelopes are labelled separately. No signature, native/device, current policy, contextual binding or dispatch authority proof.",
        "recording_contract": "Reconcile publishes only persisted dispatch_grant|arm_dispatch|callback; the current Edge/native validators additionally accept attempt_status as a compatibility branch, which is excluded here because status reads are never recorded.",
        "schema_meta_validation_passed": True,
        "definitions": len(schema["$defs"]),
        "checks_passed": len(checks),
        "checks_failed": 0,
        "categories": categories,
        "source_hashes": source_hashes,
        "source_drift": False,
        "checks": checks,
    }
    if args.report:
        report_path = args.report.resolve()
        report_path.parent.mkdir(parents=True, exist_ok=True)
        with report_path.open("x", encoding="utf-8") as output:
            json.dump(report, output, indent=2)
            output.write("\n")
    print(json.dumps({key: value for key, value in report.items() if key != "checks"}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
