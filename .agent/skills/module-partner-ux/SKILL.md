---
name: Module & Partner UX
description: >
  Per-module UX rules (Home, MoMo, Groups, Mobility, Partners, Basket, Auth,
  Profile, Admin), partner sub-brand design (Rayon Sports, banks, generic),
  and redesign migration/rollout planning for the COOL Flutter super-app.
  Replaces the legacy cool-superapp-design skill.
  Source of truth: DESIGN_SYSTEM.md §15–16, §19.
---

# Module & Partner UX

Use this skill when the task involves:

- Designing or redesigning any specific COOL module (Home, MoMo, Groups, etc.)
- Partner sub-brand design (Rayon Sports, bank partners, generic partners)
- Rayon Sports brand shell components, tokens, or typography
- Planning migration phases or PR sequencing for the redesign
- Module-specific UX decisions that go beyond general screen composition
- Reviewing whether a feature belongs in a module or should be extracted

This skill is NOT for:

- Global color/typography/spacing tokens → use `design-foundations`
- Generic screen layout or copy budgets → use `screen-composition`
- Shared widget API or routing changes → use `component-navigation`
- Payment trust or accessibility → use `trust-accessibility`

## Product Truths

Non-negotiable constraints every module must respect:

- COOL is Flutter mobile, Android-first, dark-first, EN/FR.
- Primary shell: `Home`, `Groups`, center `MoMo`, `Mobility`, `Profile`.
- `MoMo` is a pushed standalone route, not a shell branch.
- Payments are payer-owned USSD handoff + Android SMS verification.
- WhatsApp OTP is the auth path.
- Maps are conditional. Fallbacks are mandatory.
- All states (pending, draft, blocked, offline, disabled) shown honestly.

## Module UX Rules

### Home

- Quick actions: compact and obvious.
- Recent activity: must be real data, not placeholder.
- Do not make Home a second dashboard for every module.
- Home is the only screen that may have multiple visually competing sections.
- Home uses the shell gradient (`shellGradient`) for subtle background atmosphere.

### MoMo

- Statements are first-class, not buried diagnostics.
- Back and Home affordances must exist on standalone routes.
- QR and NFC are secondary to the USSD and ledger truth path.
- Payment state must be honest: pending means pending, not "complete."
- Use `financialSurface` token for all wallet/statement containers.
- Balances displayed in `DM Mono` at `headlineMedium` (30dp) minimum.

### Groups

- Group trust and recipient clarity > decorative community UI.
- Invite and contribution actions: easy to discover.
- Creation: progressive disclosure (name → members → rules).
- Ledger: clear, scannable, mono font for amounts.

### Mobility

- Trip scheduling uses steps, not a single dense form.
- Separate rider and driver concern density.
- Do not bury the trip board under filters and map chrome.
- Driver profile: factual, not marketing.
- Use `routeSurface` for trip containers, `proximitySurface` for nearby indicators.
- Use `demandHigh/Medium/Low` tokens for demand/surge visuals.

### Partners & Rayon

- Brand expression is allowed but system trust and clarity win.
- Ticket, checkout, and support flows reflect payment state plainly.
- Discovery routes can feel branded; payment routes feel like trust.
- Generic partner discovery and dedicated partner flows have different visual weight.

### Basket

- Checkout = final review, not second browsing screen.
- Totals, quantities, pending-state language: explicit.
- MoMo handoff = deliberate next step, not a surprise.

### Auth

- Reduce copy and friction.
- OTP screens must explain what channel is used.
- Avoid forcing profile completion after successful verification.
- One flow: phone → OTP → verified. Keep it simple.

### Profile

- One travel-role control, not duplicate role cards.
- Access settings: grouped and factual.
- Account setup in sheets or focused subsections.
- Do not make Profile a second Home screen.

### Admin

- Reduce storytelling, increase consequence clarity.
- Use tables, rows, explicit states, and repair actions.
- Admin surfaces are flatter, simpler, and data-first.
- No consumer marketing chrome on admin screens.
- Use `operationalSurface` for dashboard containers, `analyticsSurface` for data panels.

## Domain Surface Token Map

Each module maps to specific `CoolSemanticColors` surface tokens:

| Module | Primary Surface Token | Secondary Tokens |
|---|---|---|
| Home | `cardSurface` | `shellGradient` |
| MoMo | `financialSurface` | `cardSurface`, `operationalSurface` |
| Groups | `cardSurface` | `financialSurface` (ledger) |
| Mobility | `routeSurface` | `proximitySurface`, `contactSurface` |
| Partners | `commerceSurface` | `teamSurface` (sports), `contactSurface` |
| Basket | `cardSurface` | `financialSurface` (totals) |
| Profile | `cardSurface` | `operationalSurface` (settings) |
| Admin | `operationalSurface` | `analyticsSurface`, `financialSurface` |

## Partner Sub-Brand Rules

### Rayon Sports

Rayon is the most identity-sensitive partner. It gets a dedicated brand shell.

**Brand palette:**
- Deep royal blue as dominant color
- White as main neutral
- Gold/yellow as supporting accent (not base surface)

**Required shell components:**
- `RayonShellBackground` — subtle branded atmosphere on entry/discovery
- `RayonBrandMark` — crest with dark/light/compact variants
- `RayonSectionHeader` — branded section headers

**Semantic tokens (Rayon-only):**

| Token | Role |
|---|---|
| `rayonPrimary` | Primary blue |
| `rayonPrimarySoft` | Light blue tint |
| `rayonSurface` | Card surface |
| `rayonSurfaceAlt` | Alternate surface |
| `rayonTextPrimary` | White on blue |
| `rayonTextSecondary` | Muted on blue |
| `rayonAccentGold` | Gold accent |
| `rayonSuccess` | Status: success |
| `rayonWarning` | Status: warning |

**Rules:**
- Gold is accent, not layout chrome.
- Green must not appear as the main Rayon CTA color.
- Purple should disappear from Rayon routes entirely.
- Entry pages feel like Rayon; payment pages feel like trust.

**Typography override:**
- Barlow Condensed for hero headlines
- Barlow for body copy
- DM Mono only for IDs, counters, payment values

### Bank Partners

- Exactly 3 standard CTA cards per bank partner page.
- No additional services added without guardrail review.
- Bank logo assets use `PartnerBrandMark`.
- Standard COOL design system except for brand logo.

### Generic Partners

- Use the standard COOL design system.
- Brand expression through color accent only, not structural changes.
- No custom component variants for generic partners.

## Migration & Rollout

### Phased Approach

| Phase | Scope | Focus |
|---|---|---|
| 0 | Baseline | Fix compile blockers, pass `flutter analyze`, stabilize tests |
| 1 | Core shell | Bottom nav, shared primitives, theme tokens, `CoolScreenBackground` |
| 2 | Auth & Home | Onboarding, OTP, Home screen |
| 3 | MoMo & Groups | Payment flows, group flows |
| 4 | Mobility | Trip scheduling, driver state, trip board |
| 5 | Partners | Rayon brand shell, bank partners, partner discovery |
| 6 | Admin | Admin dashboard, CRUD surfaces |
| 7 | Polish | Cross-cutting motion, accessibility audit, performance |

### PR Sequencing Rules

- Small, reviewable PRs. No mega-commits.
- Each PR: either simplify structure OR apply visual tokens, not both.
- Theme token PRs land first — mechanical, low-risk.
- Route responsibility PRs next — structural, medium-risk.
- Visual polish PRs last — highest visible impact, lowest structural risk.

### Safety Rules

- **No big bang.** Never redesign more than one screen family per sprint.
- **Test before AND after.** Run `flutter analyze` + `flutter test` per PR.
- **Preserve behavior.** No feature removals during redesign unless approved.
- **Rollback plan.** Every PR must be individually revertable.

### Redesign Success Criteria

A screen is redesigned when:

- [ ] Route purpose obvious in under 3 seconds.
- [ ] Above the fold presents one clear decision.
- [ ] Secondary sections don't compete with primary action.
- [ ] Copy is shorter than before.
- [ ] Visible blocks/controls materially reduced.
- [ ] No new style system introduced without system reason.
- [ ] No capability removed without an alternate path.
- [ ] Calmer on a small phone, not just prettier on a simulator.
- [ ] Both light and dark themes work.
- [ ] All state matrix states handled.
- [ ] Screen LOC within budget thresholds.

## Audit Commands

```sh
# Module screen counts
for mod in auth basket credit groups home momo partners profile; do
  echo "$mod: $(find lib/features/$mod -name '*screen.dart' 2>/dev/null | wc -l | tr -d ' ')"
done

# Admin screen count
find lib/features/admin -name '*screen.dart' | wc -l

# Rayon-specific files
find lib/features/partners/rayon -type f -name '*.dart' | wc -l

# Partner routes
rg "GoRoute" lib/core/router/app_router.dart | grep -i "partner\|rayon"

# Rayon color usage (should use rayonPrimary, not AppColors.accent)
rg "AppColors\.(accent\|blue\|purple)" lib/features/partners/rayon/ --count
```

## Cross-References

- Visual tokens used by all modules → `design-foundations` skill
- Screen composition rules applied to module screens → `screen-composition` skill
- Shared widgets used across modules → `component-navigation` skill
- Payment trust and accessibility → `trust-accessibility` skill
- Full human-readable reference → `DESIGN_SYSTEM.md`
