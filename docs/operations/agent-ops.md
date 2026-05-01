# Agent Operations

No production agent runtime is active in this repo as of 2026-05-01. Agent operations are therefore fail-closed until runtime files, permissions, tools, memory, evaluations, and channel adapters exist.

## Current status

- `agents/README.md` documents the intended folder structure.
- No active prompts, tools, memory stores, MCP servers, workspaces, or channel routes were found as deployable production assets.
- Agent UAT remains blocked until a runtime exists.

## Operating requirements before activation

- Agent owner and on-call escalation path.
- Workspace manifest with allowed channels, tools, environments, and data classes.
- Tool permission matrix mapped to backend roles/RLS/RPCs.
- Structured output schema for every tool-driving response.
- Memory schema with tenant boundaries, retention, and deletion process.
- Audit log integration for privileged tool calls.
- Human escalation for payment, campaign, identity, destructive action, and abuse cases.
- Evaluation suite covering prompt injection, cross-tenant data requests, tool misuse, payment confirmation, and admin impersonation.

## Runtime kill switch

Before production activation, add a server-side kill switch that disables:

- All privileged tools.
- Outbound campaigns/messages.
- Payment or role mutation tools.
- Memory writes.
- Channel-specific ingestion if abuse is detected.

## Future verification

```bash
# Future examples once runtime-owned commands exist.
# agents/evals/run-all.sh
# agents/tools/test-permissions.sh
# agents/channels/smoke.sh
```
