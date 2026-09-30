> Historical local Increment 04 note. Increment 05 reconciles this branch with
> the separately filed Drive recovery-integrity branch. The guarded, data-only
> refresh behavior in RECOVERY_INTEGRITY_2026-09-26.md supersedes the earlier
> navigation-only recovery below. Lazy lists and the prefixed viewport fix are
> retained. See INTEGRATION_RECONCILIATION_2026-09-26.md for current status.

# Recovery screens and lazy group-selection lists — Increment 04

## Authority and scope

The installed revolut-design skill remains the sole design authority. This change reuses existing tokens and components and does not supply a competing visual standard. No design acceptance or frame-rate claim is made.

## Source changes

The contribution flow now imports its new form viewport as `forms`, resolving the collision with the legacy constructor exported by collect_components.dart. Both APIs remain available; legacy callers are not rewritten.

The contribution group-selection page uses GroupListSliver for its private and public sections. The existing shared lazy card gains optional padding and emphasis arguments with unchanged flat defaults. The new group adapter reuses the original normal-card tokens and private row implementation. It avoids eagerly constructing all row widgets. Filtering and sorting still process the supplied collection set; this is not server pagination. Read-only row keys follow group IDs. The eager GroupListPanel remains for callers outside this scope.

The lazy group container uses DecoratedSliver rather than the former AnimatedContainer/ClipRRect box panel. This intentionally avoids container animation; exact corner/ripple clipping and pixel parity still need visual review. No measured performance improvement is claimed. Activity already uses a lazy list and has not been edited. No backdrop blur was removed in this increment because the inspected card implementation already has none.

Recovery screens keep one existing MinimalStatePanel, group navigation and the privacy destination. Copy depends on the existing snapshot.hasReadableData state. Hardcoded protected-queue and masked-data badges are removed. The screens do not create a queue, probe connectivity, retry a network request, confirm a payment, or claim that a refresh succeeded. Review groups remains navigation, not a disguised retry operation.

## Verification required on the complete checkout

Run scripts/qa/run_recovery_list_checks.sh using the version pinned by .fvmrc and resolved locked dependencies. It runs whole-checkout Flutter analysis and the targeted widget tests, including the prior compact-layout cases. In a release/profile build, use 1,000 groups, normal and enlarged text, and rapid search/scroll to measure build and raster times and memory. Check first/last rows, private-group visibility, route targets, and both card themes. Capture real evidence before making performance or visual acceptance claims.

The source retains the prior missing-summary zero fallback; this increment does not establish repository-wide no-hardcoded-data compliance. Backend pagination integration, asset removal, production settings, and a full repository scan remain outstanding.

## Delivery boundary

All implementation deliverables must be filed under the existing COOL Google Drive delivery workspace and verified after upload. A local package is not filed merely because a destination is specified. At this increment's preparation stage the current connector exposes read actions only; upload has not occurred. Check the external filing receipt for the actual status. Never infer deployment from filing.

## Primary implementation references

- Dart import prefixes: https://dart.dev/language/libraries
- Flutter lazy-list guidance: https://docs.flutter.dev/perf/best-practices
- Flutter backdrop filter cost: https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html
