# Agents

No production OpenClaw, MCP, prompt, memory, or agent workspace files were found
in this repository during the 2026-05-01 structure audit.

When agent surfaces are added, use this folder for agent-native assets only:

- `shared/` — reusable agent schemas, safety policies, and routing contracts.
- `workspaces/` — agent workspace definitions and environment manifests.
- `tools/` — tool adapters with explicit permission and audit boundaries.
- `channels/` — channel-specific agent routing for chat, voice, or operations.
- `memory/` — memory schemas and retention policies, not raw production data.
- `evals/` — agent regression and safety evaluations.
- `prompts/` — versioned prompts with owners and changelog entries.

Agent tools must authenticate callers, minimize privileges, emit audit events
for sensitive actions, and use structured outputs for downstream automation.
