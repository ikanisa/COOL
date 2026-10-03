# MCP and scheduler delta review

One P1 defect was reproduced: a tick resumed after a durable local disable during the new storage-admission await. The private correction rechecks local authority and current identity after admission/diagnostic setup, immediately before invocation. A blocked tick records a terminal, known non-invoked outcome.

- Private current scheduler tests: **66 passed**, zero failures/skips.
- Pinned Node 24.19.0 typecheck: **passed**.
- Current Python preparation tests: **12 passed**.
- 28 unchanged module closures preserve 347 accepted cases; the current affected 66 compose 413 unique cases, bound in review.json.

[Reviewable patch](late-authority-fence.patch) and exact before/after hashes are retained. The original race failure and a test-only optional-property typing failure remain preserved. Live peer source is unchanged; integration remains pending.

The four new regressions cover admission and diagnostic-setup windows for durable disable and identity expiry. They prove zero runner calls, `business_handled: false` and terminal diagnostics. They do not claim atomic cross-process execution or actual daemon/Keychain/Auth/provider/retention/restore acceptance.
