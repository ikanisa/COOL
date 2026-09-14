# Source reconciliation — 14 September 2026

The initial QA checkout was based on `caafcef15f83de9baae84c377e1a99bb49ed6920`.
Live GitHub inspection found `main` two commits ahead at
`7be122328d50e9b635b7fabc0513b82b10a0ea62`. The current work was saved in local
commit `2dd34026`, excluding the user's `.vscode/settings.json` modification,
before fetching and reconciling that exact upstream revision. The local merge
commit is `dfc2a526`. The user settings file was verified unchanged by hash.

Upstream fixes include group-profile photo fallback, recovery-page navigation,
an isolated browser review target, stronger profile-save assertions and
overlapping repairs to asset inventories, goldens and tests. Three test-file
conflicts were resolved to retain exact asset/hash checks, lazy form traversal,
actual profile-save assertions and this task's stronger QA gates.

The design-instruction changes in those older commits conflict with the
instructions explicitly supplied by the user in this task. The current
`AGENTS.md`, mobile contract's `references/mobile-design-100.md` binding and
the corresponding gate constant are retained from this task. The installed
rule continues to validate against the recorded SHA-256. The repaired current
evidence-consistency CI check also remains enabled. The historical September
10 report is retained as history and cannot supersede current authority.

The recovery change was reviewed at original 390 × 844 resolution against
its preceding golden and the registered `native-settings` component reference
at `/Users/jeanbosco/Documents/ChatGPT/Revolut/private/native-current-20260905/007-settings-overview.jpg`.
That source hash matches
`0e9a62b71f436b84b45f45bd929cd436517c2a3c51d86a8b344a5009238aa0bb`.
It supports the neutral settings hierarchy only: it is not a direct offline
state comparator or evidence of unseen interaction states.

The current target adds a reachable Back control and route title above the
existing recovery content. The primary recovery action remains visible and
the content stays within the viewport. Only the inspected offline golden is
refreshed, with its predecessor retained under this run's ignored
`goldens-before/` directory. Its tolerance, other criteria and other baseline
bytes are unchanged. The app-shell test now checks both route headings and
the Back action's return to Home. This records an implementing-agent
regression review; complete state-matched/native acceptance remains unverified.

Pre-reconciliation results remain historical checkpoints. The reconciled
source needs its own relevant regression and source hashes; no earlier pass
count is silently relabelled as current. Nothing has been pushed or deployed.
