# Collect working rules

## Critical release blocker: mobile design parity

Read `DESIGN.md` before changing any visible mobile surface. Its **MOBILE-DESIGN-100**
rule is mandatory. The Revolut reference and the owner's browser annotations
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
