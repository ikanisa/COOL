"""Prepare review-only HTTP fixture candidates without invoking their behavior."""
from pathlib import Path
import datetime as dt
import difflib
import hashlib
import json
import os
import shutil
import stat

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
FAILED = E.parent / "edge-ai-canonical-batch1"
PATH = "scripts/qa/edge_http_runtime_uat.ts"


def observe(path):
    first = path.lstat()
    assert stat.S_ISREG(first.st_mode), str(path)
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    last = path.lstat()
    identity = lambda s: [s.st_dev, s.st_ino, stat.S_IMODE(s.st_mode), s.st_size,
                          s.st_mtime_ns, s.st_ctime_ns, s.st_nlink]
    assert identity(first) == identity(last), str(path)
    return {"sha256": sha, "bytes": last.st_size, "mode": stat.S_IMODE(last.st_mode),
            "identity": identity(last)}


def save(name, value):
    p = E / name
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("x") as out:
        out.write(json.dumps(value, indent=2) + "\n")


def copy(original, destination):
    before = observe(original)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with original.open("rb") as src, destination.open("xb") as dst:
        shutil.copyfileobj(src, dst)
    os.chmod(destination, before["mode"])
    actual, after = observe(destination), observe(original)
    assert before == after
    assert all(before[k] == actual[k] for k in ["sha256", "bytes", "mode"])
    assert before["identity"][:2] != actual["identity"][:2]
    return {"original": str(original), "copy": str(destination),
            "before": before, "copied": actual, "after": after}


NEGATIVES = '''  // Appended after every original HTTP assertion; synthetic policy only.
  // Each well-hashed tuple mismatch must fail before reserve/decode/provider.
  for (
    const [scenario, policyPatch, environmentPatch] of [
      ["missing policy", {}, { ROSTER_AI_APPROVAL_JSON: undefined }],
      ["missing hash", {}, { ROSTER_AI_APPROVAL_SHA256: undefined }],
      ["tampered hash", {}, { ROSTER_AI_APPROVAL_SHA256: "0".repeat(64) }],
      ["wrong model", { model: "synthetic-other-model" }, {}],
      ["wrong decoder URL", { decoder_url: "http://127.0.0.1:1/decode" }, {}],
      ["wrong decoder build", { decoder_build_sha256: "e".repeat(64) }, {}],
      ["wrong organization", { organization_id: "org_other_synthetic" }, {}],
      ["wrong project", { project_id: "proj_other_synthetic" }, {}],
      ["disabled policy", { enabled: false }, {}],
      ["revoked policy", { status: "revoked" }, {}],
      ["expired policy", { valid_until: "2021-01-01T00:00:00Z" }, {}],
      ["future approval", { approved_at: "2098-01-01T00:00:00Z" }, {}],
    ] as const
  ) {
    const negativeApproval = await syntheticRosterAiApproval(
      rosterModel,
      decoderUrl,
      decoderBuild,
      policyPatch,
    );
    const negativeEnvironment = {
      ROSTER_AI_APPROVAL_JSON: negativeApproval.aiApprovalJson,
      ROSTER_AI_APPROVAL_SHA256: negativeApproval.aiApprovalSha256,
      OPENAI_ORGANIZATION_ID: negativeApproval.openAiOrganizationId,
      OPENAI_PROJECT_ID: negativeApproval.openAiProjectId,
      ...environmentPatch,
    };
    const before = providerAttempts.length;
    try {
      for (const [key, value] of Object.entries(negativeEnvironment)) {
        if (typeof value === "string") Deno.env.set(key, value);
        else Deno.env.delete(key);
      }
      const result = await request(
        "prepare-roster-import",
        `roster AI approval: ${scenario} refuses before work`,
        {
          headers: { authorization: userAuthorization },
          body: JSON.stringify(rosterImage()),
        },
      );
      check(
        result.label,
        result.http_status === 503 &&
          (result.response as Record<string, unknown>)?.error ===
            "roster_extraction_unavailable" &&
          JSON.stringify(result.dependencies.map((r) => r.path)) ===
            JSON.stringify(["/auth/v1/user"]) &&
          providerAttempts.length === before && result.no_store === true,
        result,
      );
    } finally {
      for (const [key, value] of Object.entries(rosterApprovalEnvironment)) {
        Deno.env.set(key, value);
      }
    }
  }
'''


def main():
    failed_seal = observe(FAILED / "batch.json")
    assert failed_seal["sha256"] == "3fdac5b5fdc8d1e95015f1df18eb6f56546eacfcc61e89d0fddde5771906b5b7"
    freeze = json.loads((FAILED / "private-source-freeze.json").read_text())
    source = Path(freeze["private_candidate"])
    frozen = {row["path"]: row for row in freeze["source_manifest"]}
    names = [PATH, "scripts/qa/run_edge_http_uat.py",
             "supabase/functions/prepare-roster-import/handler.ts",
             "supabase/functions/prepare-roster-import/index.ts",
             "supabase/functions/_shared/roster_ai_dispatch_policy.ts",
             "supabase/functions/_shared/roster_ai_dispatch_test_fixture.ts",
             "supabase/functions/_shared/roster_decoder.ts",
             "supabase/functions/_shared/roster_provenance.ts",
             "supabase/functions/deno.lock"]
    inputs = []
    current = {}
    for name in names:
        expected = frozen[name]
        actual = observe(source / name)
        assert actual["sha256"] == expected["sha256"] and actual["mode"] == expected["copy_mode"]
        inputs.append(copy(source / name, E / "inputs" / name))
        current[name] = observe(ROOT / name)
        assert all(actual[k] == current[name][k] for k in ["sha256", "bytes", "mode"])
    for name in ["batch.json", "SHA256SUMS", "failure-analysis.json", "phase-summary.json"]:
        inputs.append(copy(FAILED / name, E / "failed-cohort" / name))
    original = (source / PATH).read_text()
    minimal = original
    anchor = 'import { ROSTER_DECODER_TOOLCHAIN } from "../../supabase/functions/_shared/roster_decoder.ts";\n'
    assert minimal.count(anchor) == 1
    minimal = minimal.replace(anchor, anchor + 'import { syntheticRosterAiApproval } from "../../supabase/functions/_shared/roster_ai_dispatch_test_fixture.ts";\n')
    anchor = 'servers.push(decoder);\n\n'
    setup = '''// Synthetic approval only: bind the actual local fixture receipt tuple.
// It represents no owner/vendor acceptance and does not enable provider access.
const decoderUrl = `http://127.0.0.1:${decoder.addr.port}/decode`;
const rosterModel = "synthetic-model";
const rosterApproval = await syntheticRosterAiApproval(
  rosterModel,
  decoderUrl,
  decoderBuild,
);
const rosterApprovalEnvironment = Object.freeze({
  ROSTER_AI_APPROVAL_JSON: rosterApproval.aiApprovalJson,
  ROSTER_AI_APPROVAL_SHA256: rosterApproval.aiApprovalSha256,
  OPENAI_ORGANIZATION_ID: rosterApproval.openAiOrganizationId,
  OPENAI_PROJECT_ID: rosterApproval.openAiProjectId,
});

'''
    assert minimal.count(anchor) == 1
    minimal = minimal.replace(anchor, anchor + setup)
    minimal = minimal.replace('    ROSTER_DECODER_URL: `http://127.0.0.1:${decoder.addr.port}/decode`,\n', '    ROSTER_DECODER_URL: decoderUrl,\n')
    minimal = minimal.replace('    OPENAI_ROSTER_MODEL: "synthetic-model",\n', '    OPENAI_ROSTER_MODEL: rosterModel,\n    ...rosterApprovalEnvironment,\n')
    status_anchor = '  report.status = checks.every((r) => r.status === "pass") ? "pass" : "fail";\n'
    assert minimal.count(status_anchor) == 1
    combined = minimal.replace(status_anchor, NEGATIVES + status_anchor)
    for kind, candidate in [("minimal", minimal), ("candidate", combined)]:
        target = E / kind / PATH
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("x") as out:
            out.write(candidate)
        patch = ''.join(difflib.unified_diff(original.splitlines(True), candidate.splitlines(True),
                                             fromfile="a/" + PATH, tofile="b/" + PATH))
        with (E / (kind + ".patch")).open("x") as out:
            out.write(patch)
    # All original runtime assertions and their ordering are untouched bytes.
    begin = original.index('const report: Record<string, unknown>')
    end = original.index(status_anchor)
    unchanged_checks = original[begin:end]
    assert unchanged_checks in minimal and unchanged_checks in combined
    assert original[original.index(status_anchor):] == combined[combined.index(status_anchor):]
    assert observe(FAILED / "batch.json") == failed_seal
    assert current == {n: observe(ROOT / n) for n in names}
    save("preparation.json", {"prepared_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "status": "review_only_unexecuted", "source_path": PATH, "base_sha256": frozen[PATH]["sha256"],
         "minimal": observe(E / "minimal" / PATH), "candidate": observe(E / "candidate" / PATH),
         "minimal_patch": observe(E / "minimal.patch"), "candidate_patch": observe(E / "candidate.patch"),
         "inputs": inputs, "current_source_before_after": current,
         "failed_cohort_seal_before_after": failed_seal,
         "original91_check_body_byte_identical": True, "original91_relative_order_unchanged": True,
         "original_check_region_sha256": hashlib.sha256(unchanged_checks.encode()).hexdigest(),
         "original_teardown_and_report_tail_identical": True,
         "proposed_additional_negative_checks": 12, "proposed_total_if_executed": 103,
         "proposed_negative_categories": ["missing JSON", "missing hash", "tampered digest",
             "well-hashed wrong model", "well-hashed wrong decoder URL", "well-hashed wrong decoder build",
             "well-hashed wrong organization", "well-hashed wrong project", "disabled", "revoked", "expired", "future approval"],
         "negative_expected_behavior": "Fixed503 extraction_unavailable; exactly auth dependency, no reservation/decoder/provider attempt; no-store; valid tuple restored in finally.",
         "decoder_build_scope": "Existing synthetic HTTP decoder receipt identity d×64; not a Docker image/build acceptance. Signed Linux integration has its separate actual build identity.",
         "provider_endpoint": "https://api.openai.com/v1/responses", "provider_permissions_changed": False,
         "openai_api_key_remains_absent": True, "production_policy_changed": False,
         "maintained_source_mutations": 0, "canonical_invocations": 0, "behavior_tests_executed": False,
         "candidate_is_partial_review_artifact_not_executable_source_export": True,
         "shared_promotion_requires_root_review": True})
    print(json.dumps({"status": "review_only_unexecuted", "base_sha256": frozen[PATH]["sha256"],
                      "candidate_sha256": observe(E / "candidate" / PATH)["sha256"],
                      "original91_unchanged": True, "new_negative_proposal": 12}, indent=2))


if __name__ == "__main__":
    main()
