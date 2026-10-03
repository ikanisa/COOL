# ARC05 backend delivery contract

The canonical `scripts/supabase_deploy.sh` now validates an externally reviewed export and approval record before any project operation. It executes a private verified copy of that export. A confirmation environment variable alone no longer starts delivery. This batch performed no hosted deployment, provider, credentials-storage or customer operations.

## Prepare a reviewable candidate

Use the existing exporter against quiescent source, with a fresh destination outside the checkout:

```sh
python3 -B scripts/qa/collect_release_candidate.py export \
  --destination /release/collect-candidate \
  --flutter-sdk /approved/flutter-sdk \
  --report /release/export-report.json
python3 -B scripts/qa/backend_release_delivery.py describe \
  --candidate /release/collect-candidate \
  --manifest-sha256 '<independently retained export manifest SHA-256>'
```

The export remains explicitly unapproved. The description reports the backend scope hash and creates no approval. Backend scope includes every exported Supabase file, the current migration chain/configuration, Edge inventory, CLI/Deno pins and lock, delivery controller/launcher, candidate verifier, migration validator and deployed/readback script dependencies. The exporter now retains `.supabase-cli-version`; older exports without that required deployment input must be recreated and reviewed. Non-atomic checkpoints, changed/unlisted candidate files and source drift are refused. A strict snapshot of authored uncommitted fixes can be separately reviewed; unrelated Git cleanliness is not a substitute for byte review.

The release reviewer must approve the actual candidate bytes, target and operations through an authenticated external process. That process supplies a record with exactly these fields:

```json
{
  "schema_version": 1,
  "kind": "collect_backend_deployment_approval",
  "approval_id": "<fresh UUID from the authorized review process>",
  "reviewer": "<externally authenticated reviewer identifier>",
  "approved_at_utc": "<UTC ISO timestamp>",
  "expires_at_utc": "<UTC ISO timestamp, at most 24 hours after approval>",
  "candidate_manifest_sha256": "<independently retained export manifest SHA-256>",
  "backend_manifest_sha256": "<reviewed backend scope SHA-256>",
  "target": {
    "project_ref": "<exact 20-character project ref>",
    "url": "https://<exact project ref>.supabase.co",
    "environment": "staging"
  },
  "purpose": "remediation",
  "operations": ["migrations", "retired_functions", "edge_functions"],
  "toolchain": {
    "supabase": {"version": "2.114.0", "binary_sha256": "<approved selected executable SHA-256>"},
    "supabase_go": {"version": "2.114.0", "binary_sha256": "<approved selected supabase-go companion SHA-256>"},
    "deno": {"version": "2.5.6", "binary_sha256": "<approved selected executable SHA-256>"}
  }
}
```

This is an invalid placeholder example, not an approval. The record's hash must also be independently retained by the authorized release environment. A self-written reviewer name and matching hashes cannot authenticate a human, establish their authority or attest a vendor binary. The environment label binds the record and invocation; actual project classification still depends on that external review.

## Deliver only the approved operation scope

Supply these nonsecret bindings through the protected release environment:

- `COLLECT_BACKEND_CANDIDATE`, `COLLECT_BACKEND_MANIFEST_SHA256`.
- `COLLECT_BACKEND_APPROVAL`, `COLLECT_BACKEND_APPROVAL_SHA256`.
- `COLLECT_BACKEND_ENVIRONMENT` and a fresh `COLLECT_BACKEND_RECEIPT` path.
- `SUPABASE_PROJECT_REF`, matching `SUPABASE_URL`, and exact `CONFIRM_SUPABASE_DEPLOY`.
- `SUPABASE_BIN`, its approved co-located `supabase-go` companion (or `SUPABASE_GO_BINARY`), and `DENO_BIN` selecting the approved executable bytes. The controller explicitly selects the verified companion for every child invocation.

Provision `SUPABASE_ACCESS_TOKEN` separately. Migration delivery also needs `SUPABASE_DB_PASSWORD`; function-only staging delivery does not. Then run `bash scripts/supabase_deploy.sh` or the existing `make supabase-deploy` target. Passwords/tokens are supplied through environment/secret storage and are not included in approval metadata or command arguments. No worktree `.env` or linked cache is imported.

Allowed operations are ordered, unique selections of `migrations`, `retired_functions`, `edge_functions`, `strict_production_readiness`. The first three describe the entire corresponding reviewed inventory. A function-only staging/remediation approval makes no migration or deletion call. Unselected retired functions are retained and appear in readback; their presence is not permission to delete them.

The broader `strict_production_readiness` operation is available only under an explicit production approval. It includes the existing synthetic database tests inside rollback transactions; it is not wholly read-only. Its database URLs/password and exact target are validated before delivery begins. Local staging/remediation does not require completed final production acceptance to run its independently approved operation set.

## Execution and readback

All current backend source bytes, source modes, approval bytes/expiry and executable hashes are rechecked before each controller operation. The actual Edge entrypoints receive pinned Deno frozen, cached-only, compile-without-execution closure validation before any project call. Missing cached dependencies are an operator prerequisite failure, not permission to download a new graph.

CLI 2.114.0 includes a native main executable and a `supabase-go` companion. Approval must bind both binaries; a missing, swapped or changed companion is refused, including an unapproved `SUPABASE_GO_BINARY` override. The pinned upstream resolver gives that override priority, followed by co-located/package resolution; this controller sets the checked absolute path explicitly. See the [v2.114.0 binary distribution](https://github.com/supabase/cli/blob/v2.114.0/apps/cli/docs/binary-distribution.md) and [pinned resolver source](https://github.com/supabase/cli/blob/v2.114.0/apps/cli/src/shared/legacy/go-proxy.layer.ts). Earlier main-only approval records must be recreated through authorized review.

Migration delivery establishes the exact target link inside its private execution directory, then performs visibility/history checks and a dry run. Supabase documents that linked database commands require linking and that the password can be supplied through `SUPABASE_DB_PASSWORD`; CLI linking may use its native credentials storage, which belongs in the authorized release-host review. See [Supabase CLI link reference](https://supabase.com/docs/reference/cli/supabase-link).

Only explicitly named CLI metadata files are admitted under the private `supabase/.temp` directory. Project ref, pooler URI and linked-project metadata are checked against the approved target. Unknown/nested metadata, symlinks, wrong-target link state, extra backend source, changed config and executable drift stop subsequent operations. The original candidate's verifier still rejects every unlisted file, including `.temp` payloads.

Direct migration apply occurs once after a successful dry run. The established Management API fallback remains limited to recognized connection restrictions; a failed actual apply never becomes another apply attempt. Its guarded transport repeats the local source/approval/target checks before every HTTP request and uses a 60-second transport bound. Earlier per-migration commits remain when a later apply/readback fails. There is no automatic mutation retry.

Every approved delivery requires migration history readback and/or exact active function/auth-mode readback for its operation scope. Readback proves the observed version/name inventory and configured auth modes, not remote SQL-body or bundled-handler byte identity. The Supabase function deployment/compiler/dependency behavior has its own hosted acceptance boundary; local frozen compilation and hash binding do not attest that remote bundle. See [Supabase dependency guidance](https://supabase.com/docs/guides/functions/dependencies) and [Supabase CLI reference](https://supabase.com/docs/reference/cli).

Each attempt writes a fresh owner-only receipt before operations, checkpoints each operation start/result, records bounded output hashes and target/readback metadata, and stops after the first failed or changed input. Ordinary operations have a 180-second deadline, broader readiness 600 seconds; controller output capture is limited to 2 MiB per stream and the attempt to 128 controller operations. A failed/lost mutation response remains failed/uncertain even when readback identifies committed state. Read-only reconciliation is attempted after a mutation failure only while the binding remains valid. An expired or changed binding can block reconciliation and is retained as an unresolved outcome. Review that receipt and remote state before approving a new attempt; do not rerun blindly.

## Remaining acceptance

The offline tests use fabricated approval metadata, fake CLI/Deno/curl and isolated synthetic state. They prove the guard and sequencing behavior, not authentic human approval, real CLI credential storage, hosted compilation, target access, current hosted SQL/provider behavior, rollback rehearsal, protected CI delivery or final production readiness. No real approval was created and no deployment was executed in this batch.
