# Web Surface Activation Contracts

Missing web surfaces must not be implemented as shell apps. A surface can move
from `not-implemented` or `retired-fail-closed` to `active` in
[`web-surface-registry.json`](./web-surface-registry.json) only when the owning
team lands the backend and release contract in the same change.

## Venue Manager Dashboard

Required before activation:

- venue/team tenant model documented with RLS policy coverage;
- manager role capabilities mapped to backend enforcement;
- venue dashboard routes, tables, and actions sourced from real database state;
- audit logs for manager actions such as menu edits, order overrides, refunds,
  payout changes, and staff permission changes;
- build, lint, browser smoke, and permission-denied tests.

## Agent Admin Console

Required before activation:

- agent identity model, tool scopes, and escalation boundaries;
- MCP/tool allowlist, structured outputs, and memory isolation rules;
- audit logs for tool execution, handoff, prompt/config changes, and manual
  overrides;
- backend checks for every privileged agent action;
- eval or smoke coverage for routing, permission denial, and human handoff.

## Promotions Approval Console

Required before activation:

- promotion/campaign schema with lifecycle states and approver roles;
- backend approval/rejection RPCs with audit logs;
- destructive or irreversible actions guarded by confirmation;
- table search, filters, sort, pagination, empty/error states, and export rules;
- tests for unauthorized approval attempts and approval history rendering.

## User PWA

Required before revival:

- explicit product decision that web PWA is a supported user surface alongside
  the Flutter mobile app;
- authentication/session strategy, offline policy, and push-notification scope;
- real user journeys backed by Supabase state and RLS;
- production headers, installability checks, and cache invalidation strategy;
- route smoke tests and release ownership.
