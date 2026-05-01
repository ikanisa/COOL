# Agents

No production OpenClaw, MCP, prompt, memory, or agent workspace runtime is active in this repository as of 2026-05-01. The `agents/` folder is an operating contract area, not a deployable surface.

## Required structure before activation

```text
agents/
  shared/       Schemas, structured outputs, safety policies, routing contracts.
  workspaces/   Workspace manifests, owners, environments, allowed tools.
  tools/        Tool adapters with backend permission checks and audit events.
  channels/     WhatsApp, web chat, voice, email, or operations routing.
  memory/       Memory schema, retention, tenant boundaries, erasure process.
  evals/        Regression, safety, and permission-boundary evaluations.
  prompts/      Versioned prompts with owners, changelog, and review date.
```

## Activation requirements

- Every agent must have an owner, purpose, data classification, allowed channels, allowed tools, and emergency disable switch.
- Agents may not perform privileged actions from conversation text alone. They must call backend-enforced tools that check identity, tenant, role, and permission.
- Tool calls that affect users, money, roles, campaigns, files, or settings must emit audit logs with actor, agent identity, workspace, tool, target, and result.
- Memory must be tenant-scoped, minimised, redactable, and excluded from prompts unless explicitly needed.
- Structured outputs are required for tool-routing decisions and downstream automation.
- Human escalation must exist for payment disputes, destructive actions, campaign approvals, abuse reports, and ambiguous identity.

## Verification before launch

```bash
# Future examples once agent runtime exists.
# agents/evals/run-all.sh
# agents/tools/test-permissions.sh
# agents/channels/smoke.sh
```

Until those tests and runtime files exist, agent features remain blocked for production launch.
