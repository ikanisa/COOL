# Canonical entity-history links — additive Admin evidence

The Gateway device row, operational exception row, confirmed receipt cancellation
result and fresh receipt investigation now link to their canonical entity action
history. Each link uses the current device ID, exception ID or receipt outbox ID.
A request UUID remains correlation evidence and is never substituted for the
entity ID. The existing manual-shadow link remains in the earlier audit packet;
no supervisor directory is invented.

Navigation independently requires a resolved current platform owner, matching
session actor, audit.read, system_health.read and notifications.read. Receipt
and exception links additionally require payments.read. Identity loading/error,
role/permission/session departure and invalid IDs hide the link before any read.
Opening history preserves the previous route using push/pop. The destination
retains its existing session, TTL, source, strict DTO and backend authority
checks. No cancellation, enrollment, exception-review, reveal, financial or send
handler is changed or called by navigation.

The initial 33 focused navigation/gate cases and 122 existing page regressions
passed. After adding only the synthetic capture harness and exact source-fixture
bindings, a single five-file run completed 156 log cases: those 155 cases plus
one environment-disabled capture case. Counts are separate scopes and are not
added to earlier stages. The actual enabled capture ran separately 1/1 and
rendered eight 1440×2200 dark/light views. All eight were visually inspected;
the final copies hash-match those inspected. Gateway and exception use actual
registered routes/shells. Receipt and investigation use their actual public
widgets in an isolated test route. Some captures show a scrolled viewport that
brings the link into view; they do not attest full-page browser scrolling.

Tests use injected synthetic identities, sessions, derived fixture read windows
and local repositories. Cancellation lookup is read-only, with the preserved
synthetic original request. Repository mutation overrides throw if called and
navigation asserts zero mutations. No live authentication, hosted RPC, SMS,
financial action or provider call was requested.

The final seven-file analysis is clean. Its first broad binding detected an
unrelated, nonexecuted cancellation SDK test edit; that receipt is retained.
The final analysis binds executed affected tests and transitive local imports,
parts, actual fixture files, locks, installed dependency configuration and
runtime inputs. verification.json lists exact per-run evidence and any changes
between scopes. Copies passed SHA-256 readback. Existing historical packets are
unchanged; this is implementation evidence and not a reviewed production freeze.

The only design authority remains revolut-design. The shared OutlinedButton and
Collect components are adapters of that authority; the sole-authority hygiene
gate passed. Local captures and scoped widget checks do not certify exact
current Business-comparator fidelity, real browser keyboard/focus/return,
spoken assistive technology or hosted deployed acceptance. No 100% match is
claimed. No global MCP enabled-tool list or dependency pins changed.
