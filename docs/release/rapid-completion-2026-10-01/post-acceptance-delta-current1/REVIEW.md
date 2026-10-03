# Admin/MCP delta review

**Review complete; two fixes verified in isolated copies. Shared-source integration is pending. Production remains NO-GO.**

The review compared the accepted source against a fixed 44-file delta (29 additions, 15 modifications), captured at 2026-10-01T15:25:51Z. Later changes are separately disclosed. The previous accepted delivery and task registers are preserved.

## Corrections

| Priority | Defect and consequence | Verified correction |
| --- | --- | --- |
| P1 | A scheduler tick could invoke its runner after a durable local disable completed during the new awaited storage scan. Identity could also expire during setup. | Recheck permission and identity after admission/diagnostic setup, before dispatch; record a terminal non-invoked outcome. Four disable/expiry regressions pass. [Patch](mcp-review/late-authority-fence.patch) · [Review](mcp-review/REVIEW.md) |
| P2 | Admin recovery classified arbitrary sessionStorage JSON before applying its byte limits. New parsers also encoded an entire oversized string before rejecting it. | Reject oversized code-unit/byte inputs before allocation or parsing; retain bounded sanitized recovery and block new actions across reload. Two regressions pass. [Runtime patch](admin-review/runtime-resource-admission.patch) · [Tests and review](admin-review/README.md) |

Both patches passed a read-only `git apply --check` against the shared checkout at 2026-10-01T15:42:13Z. They have **not** been applied to its actively owned runtime files. [Applicability receipt](patch-applicability.json).

## Verified results

- **Admin: 322 scoped cases**, including 12 decoders consuming observed successful SQL responses and both recovery regressions. Strict analysis and formatting passed in the private derivative. Original hygiene, preparation, fixture and source-drift failures remain preserved. [Accepted union](admin-review/accepted-union.json).
- **MCP: 66 affected cases**, typecheck and 12 Python preparation tests passed. The 347 unchanged cases have matching import/dependency bindings; composed private MCP coverage is 413 unique cases. This is local execution with synthetic seams, not real daemon/provider acceptance. [Review receipt](mcp-review/review.json).
- **Exception SQL: 100 checks** passed on the completed current implementation. Current ordering expression indexes and actual response evidence are retained separately from the original capture. The prior matching follow-up proof retains 83 checks in its declared scope. These counts overlap installation/control purposes and are not summed as unique cases. [Current SQL receipt](sql-current/readback.json) · [SQL review](SQL-REVIEW.md).
- **Ordinary database installation: 187 clean + 187 populated migrations = 374 applications**, 36 checks passed. Application execution used non-superuser authority; network dispatch was disabled and both owned containers were removed. [Installer acceptance](sql-ordinary187/validation.json).

No unrelated native build or whole Flutter suite was repeated. No production browser build/PWA acceptance for these new Admin changes is included in this review.

## Remaining integration

1. Coordinate ownership with **Connect Collect to Codex MCP**, then apply the two reviewed fixes and their focused tests. The cross-chat messaging tool requires explicit human authorization; the request is pending. No message has been sent.
2. Capture the combined source and refresh only later changed inputs/consumers. A passing private derivative does not accept a moving shared checkout.
3. Produce one current Admin production artifact and verify its affected browser/PWA states after the fixes are integrated.

The original 24 local criteria remain closed within their accepted snapshot. This report does not extend that acceptance to the later shared checkout or close the remaining production criteria. Source/build signing, hosted/provider/device checks and release approval retain their existing status.

[Machine-readable results and hashes](REVIEW.json). No owned process remains running.
