# Architecture Decision Log

| ID | Decision | Alternatives considered | Approver | Date | Consequences |
|---|---|---|---|---|---|
| ADR-001 | Preserve Riverpod, GoRouter, repository, and existing feature boundaries. | App-wide rewrite; new state package. | Product owner instruction and repo convention | 2026-07-24 | Lower migration risk and existing tests remain authoritative. |
| ADR-002 | Use bundled Inter as the exclusive substitute for the legacy proprietary reference family. | Proprietary-font redistribution; platform fonts; another substitute. | Product owner | 2026-07-24 | Legal distribution is straightforward and the app has one typographic system. |
| ADR-003 | Implement five mobile destinations: Home, Groups, Contribute, Activity, Profile. | Retain three destinations; copy Revolut product tabs. | Product owner through full-task goal | 2026-07-24 | Adds two Collect-native entry routes without introducing unsupported products. |
| ADR-004 | Global Activity reads existing confirmed contribution records and deep-links to existing ledgers. | Duplicate activity store or new financial record model. | Implemented and test-verified | 2026-07-24 | Avoids duplicate sources of truth and preserves privacy rules. |
| ADR-005 | Global Contribute selects a group, then reuses the existing group contribution flow. | Duplicate contribution flow. | Implemented and test-verified | 2026-07-24 | Keeps payment intent logic and MoMo confirmation behavior centralized. |
| ADR-006 | Consumer shell changes do not replace Admin PWA rail/table architecture. | Reuse the mobile five-tab shell in Admin. | Product Design standard | 2026-07-24 | Maintains operator density, keyboard access, and auditability. |
| ADR-007 | Visual parity requires side-by-side source/implementation evidence. | Screenshot-only review; prose-only audit. | Product Design contract | 2026-07-24 | Prevents unsupported parity claims. |
