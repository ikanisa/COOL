# Codex Dart/Flutter MCP Setup

## Verified Inputs

- Codex CLI: `codex-cli 0.130.0`
- Dart binary: `/Volumes/PRO-G40/flutter_3_44/bin/dart`
- Dart version: `3.12.0`
- Flutter version: `3.44.0`

## Configuration Command

```sh
codex mcp add dart -- /Volumes/PRO-G40/flutter_3_44/bin/dart mcp-server --force-roots-fallback
```

## Verification

`codex mcp list` reports a global MCP server named `dart` with:

- Command: `/Volumes/PRO-G40/flutter_3_44/bin/dart`
- Args: `mcp-server --force-roots-fallback`
- Status: `enabled`

The current Codex tool context did not expose new Dart MCP tools immediately after registration, so migration commands in this run use the verified Flutter/Dart binaries directly. Restart Codex if Dart MCP tools are needed in the interactive tool list for package search, pub dependency inspection, analyze, test, or docs queries.

## Config Location

The `codex mcp add` command writes to the user/global Codex MCP configuration. No repository-scoped `.codex/config.toml` was added because this repo does not need project-local MCP config and should not store secrets.

## Secret Policy

Do not put Supabase, OpenAI, WhatsApp, database, or service-role values in `.codex/` project files. Use ignored local shell profiles, OS keychain-backed tooling, or CI secret stores.
