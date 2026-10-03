# Release acceptance follow-up — 1 October 2026

The owner authorized release preparation and fixes and delegated business
preparation to the agent. That authorization is recorded independently from
actual account identity, device possession, carrier behavior, deployed bytes,
security entitlement and recovery proof. No repeated ownership-name question
is required by this follow-up. The master register and historical packets were
preserved; production acceptance remains open on the facts below.

## Actual current changes and checks

- Standard GitHub API readback confirmed repository workflow defaults were
  `write` and automated PR approval was allowed. After checking all six declared
  workflows' explicit permissions, the authorized change set defaults to `read`
  and disables automated PR approval. A fresh GET confirms both settings. The
  original values are retained for a reversible rollback. No workflow was
  dispatched and no protection, billing, licensing, allowed-actions, signing,
  deployment or environment setting changed.
- Sixteen checkout sites now set `persist-credentials: false` in `ci.yml`,
  `codeql.yml`, `ios-app-store.yml` and `public-website.yml`. CodeQL's push and PR
  filters include the MCP bridge and its lock. The existing Node24.19.0,
  pnpm10.33.2/frozen-lock/test lane is retained; CI additionally runs the new
  declared-policy checker and its regression tests. This is local source; it
  has not been committed, pushed or executed as hosted CI.
- Explicit email CLI renewal now reads current GoTrue `/auth/v1/user` using the
  rotated current-user token before storing it. The selected verified email,
  UUID subject and valid nonfuture confirmation timestamp must agree. The
  bounded identity read refuses redirects and strips errors. A wrong email,
  legacy phone, missing confirmation, timeout or malformed response preserves
  the refresh tombstone, and never replays that consumed refresh token. General
  existing profile renewal semantics remain separate from this explicit email
  path; current backend authority is still required.
- Operational receipt detail/list projections accept only integer content
  versions1 and2 for the fixed template key. They still omit bodies, recipients,
  amounts, balances and arbitrary diagnostics, and report operator observation
  separately from handset delivery or external settlement. Version2 backend
  publication/UAT is a separate source-bound scope.
- Actual credential-free current checks passed: TypeScript7.0.2, **146/146 Node
  cases in18 files**, the six-workflow declared-policy check, and **18/18 Python
  tooling cases**. All54 selected inputs match before/after. Actual stdout,
  stderr, commands, exit codes and pinned Node/compiler hashes are retained.
  These counts are not added to prior139,80 or frontend scopes. Tests used
  synthetic Auth/HTTP and no host credentials, Keychain, OTP or live provider.

The runner is `run_checks.py`; its actual command receipt is `checks.json`.
Copied selected source is evidence only; the original runner owns the recorded
workspace-bound invocation. The bridge README was updated after successful
checks and is separately hashed as documentation, without a runtime rerun.

## Installed MCP observation

Two actual available read tools were invoked before the new local fixes:

| Tool | Actual projected reason | Implication |
| --- | --- | --- |
| `collect_notification_health` | `OPERATOR_SESSION_REAUTHENTICATION_REQUIRED` | Fresh operator sign-in is required. |
| `get_collect_health` | `COLLECT_CURRENT_USER_SESSION_REQUIRED` | No successful current authenticated health sample. |

No further authenticated read or OTP/send action was requested. Only the exact
reason codes are retained. The receipt records its retention time, not an
invented exact tool-call timestamp. Safe host configuration parsing confirms
exactly the existing five read tools, startup15 seconds/tool45 seconds. The
host configuration was not changed. Reload of the source after these fixes,
fresh GoTrue/session authority and successful current hosted health/readback
remain unverified.

## Acceptance matrix and source association

`acceptance-matrix-observation02.json` preserves all **36 feature tasks** and
their exact mappings to the **102 original master items,101 open**. These counts
overlap and are not additive. It records delegated preparation authorization
without clearing an external proof or creating an actual policy decision. It
also binds selected current source, register bytes and a176-migration inventory.
The earlier observation01 retains its175-migration state and pre-final bridge
inputs. The later financial policy source appeared between these observations;
neither is an atomic whole-tree freeze or complete credential/history scan.

The source06 reference remains exactly its historical1,905-file unapproved
checkpoint with manifest
`3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f`.
Its configured155-artifact Admin compilation, scoped39 frontend checks, prior
MCP association and175-chain rehearsal do not automatically cover these later
CI/renewal/receipt-version changes or later receipt-policy migration.

| Current acceptance work | Local progress and actual next proof |
| --- | --- |
| C01–C08: source, account, connection, manual read flow, build/deployment and integration | Source/build/scoped test evidence is retained. Obtain an actual selected-email account/session and current five-read MCP success; bind latest SQL/Edge/Admin deployed bytes, grants/configuration and hosted negative cases. Hosted compatibility cannot be inferred from local mock-Auth replay or compilation. |
| C09–C17: Admin operations, investigation, exception/cancellation/gateway/audit/policy UX | Source06 and separate strict DTO/session/navigation/capture scopes are retained. Run the current authenticated routes/actions with real permissions, expired/departed sessions, accessibility and applicable Revolut comparators against exact deployed bytes. |
| C18–C26: financial/receipt policy, paused work, independent supervisor, durable events/actions/exceptions and modes/caps | Delegated preparation can choose and document conservative policy without further owner-name questions. Version2 policy preparation is a later backend scope. Complete immutable policy/content acceptance, server-derived bounded action/run/fence contracts, uncertainty recovery and governed mode/cap/pause enforcement before any send grant exists. Cancellation and read-only/shadow sampling do not complete event processing or correction/resend authority. |
| C27–C31: selected Android gateway, enrollment, runner, capacity/cost and failure matrix | Keystore/journal/protocol/state-machine code has scoped synthetic evidence. Obtain exact signed bytes and a real organization-owned handset/SIM, current activation/key possession and permission/telephony/journal proof; then exercise only approved allowlisted grants and correlated multipart callbacks, uncertainty/crash/pause/revocation. No attached physical device or carrier/delivery proof is created by authorization. Prove bounded scheduling/recovery and representative latency/capacity/cost. |
| C32–C34: privacy/source/security/supply-chain/signing/store/recovery | Current GitHub defaults are genuinely tightened. Main remains unprotected at the retained readback; protection/rulesets and private code-scanning capability have explicit403 limitations. Complete source access/exposure/history/credential review, actual vendor/legal/retention facts, pinned reproducible signed artifacts, installed/store scope and real database/Auth/Storage/key/journal/off-site restore with measured objectives. Synthetic source screening and restore are scoped evidence only. |
| C35–C36: operations and capped pilot/release | The seven retained runbooks are preparation. Execute the outage/compromise/uncertainty/pause/rollback drills and a bounded independently reconciled pilot using actual configured authority, monitoring and stop criteria. Delegate business decisions through a dated decision record; require actual outcomes before a production GO. |

## Normal GitHub governance path

The three current standardCLI GETs show Actions is enabled, allowed-actions is
`all`, and the latest listed PR run36751716611 ended `startup_failure` at
2026-09-30T17:29:14Z. This does not identify the underlying billing/runner cause
or prove current workflow execution. An enabled setting is not a green job.
Two further minimal readbacks confirm this is an organization-owned private
repository and that the listed failed run created zero jobs. Billing or runner
eligibility was not inspected or changed. In total, this leaf retains seven
standardCLI GETs and the one explicitly authorized settings PUT.

The earlier seven-GET source06 leaf records private repository/admin access,
unprotected main, plan/capability403 for protection/rulesets and a code-scanning
entitlement403. GitHub documents private branch protection on eligible Pro,
Team or Enterprise plans, and private organization code scanning with Code
Security enabled. Use the normal account entitlement/settings path; neither
publishing the private repository nor bypassing entitlement is part of this
work. No purchase or security feature enablement occurred. After actual access
is available, configure required checks/reviews and protected publication,
prove enforcement and retain actual job evidence. The optional iOS upload path
still lacks a declared protected ref/environment gate; it was observed, not
silently redesigned in this narrow credential-persistence fix.

Primary source checks:

- [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).
- [GitHub code scanning availability](https://docs.github.com/en/code-security/concepts/code-scanning/code-scanning).
- [GitHub secure workflow use](https://docs.github.com/en/actions/reference/security/secure-use).

No raw credentials, provider response, customer number/body, collaborator list
or personal browser/Keychain contents are retained. Historical parent manifests
and master registers remain unchanged.
