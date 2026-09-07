# Collect working rules

## Revolut design on every surface

The mobile app, Admin panel and public website must follow the owner-selected
`revolut-design` skill. That skill is the sole design authority. Repository
contracts, cohort registries, screenshots and reports are product evidence only.
Apply it through shared tokens and components, including loading, empty,
failure, geographic, membership, responsive and accessibility states.
Preserve Collect's real terminology, capabilities and access controls.
Do not report any surface as 100% matched while a material difference or
required comparator, interaction or route/state evidence remains unverified.
Web marketing and Business/operator references are distinct from native UI.

## Critical release blocker: mobile design parity

Read `/Users/jeanbosco/.codex/skills/revolut-design/SKILL.md` and its bundled
`references/mobile-design-100.md` before changing any visible mobile surface.
The **MOBILE-DESIGN-100** rule is mandatory. The selected reference and the owner's browser annotations
apply to all corresponding signed-in, membership, geographic, loading, error,
and accessibility states, not just the screenshot used during implementation.

Do not mark mobile work complete or an APK production GO while
`make mobile-design-gate` fails. A successful build, source check, test count,
Admin review, or old screenshot is not mobile design acceptance. Never lower
the score, delete a required case, regenerate a baseline without visual review,
or invent approval to make this gate pass. Keep building local QA candidates to
fix the blockers; do not distribute them as approved production releases.

Preserve existing user changes, signed-in device data, payment behaviour, and
production access controls. Use isolated fixture builds for destructive UAT.
