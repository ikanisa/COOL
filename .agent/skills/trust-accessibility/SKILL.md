---
name: Trust & Accessibility
description: >
  Trust design rules for payments, maps, and permissions, plus accessibility
  standards (touch targets, contrast, screen readers) and localization rules
  for the COOL Flutter super-app. Use when working on payment screens,
  permission flows, maps, accessibility audits, or localization.
  Source of truth: Mobi × Rayon design system.
---

# Trust & Accessibility

Use this skill when the task involves:

- Payment flows, confirmation screens, or financial data display
- Permission requests or sensitive operations
- Accessibility: touch targets, contrast, screen readers, focus order
- Localization decisions (EN/FR)

This skill is NOT for:

- Color tokens or typography → use `design-foundations`
- Screen layout or copy budgets → use `screen-composition`
- Module-specific UX decisions → use `module-partner-ux`

## Payment Trust

Payment screens are the highest-trust surfaces in the app. They must
feel stable, honest, and immediately comprehensible.

### Payment Screen Rules

1. **One CTA** — one confirm/pay button per payment screen.
2. **Amount prominent** — JetBrains Mono, headlineMedium (24dp) minimum.
3. **State honest** — pending means pending. Never say "complete" before confirmed.
4. **No marketing** — no branding, banners, or promotional noise on payment screens.
5. **Confirmation required** — all payments require explicit user confirmation step.
6. **Error states visible** — clear, actionable error messages with retry CTA.

### Financial Value Display

All amounts, balances, and IDs use JetBrains Mono:

```dart
Text(
  'RWF 25,000',
  style: TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 24,  // headlineMedium minimum for primary amounts
    fontWeight: FontWeight.w700,
    letterSpacing: -0.48,
    color: CoolColors.textPrimary,
  ),
)
```

Rules:
- Currency prefix always visible (RWF, EUR).
- No abbreviation of amounts.
- Thousand separators: comma for RWF, period for EUR.
- Negative amounts in `danger` color.
- Positive amounts in `success` color only in transaction lists.
- Neutral amounts in `textPrimary`.

### Payment States

| State | Indicator | Color |
|---|---|---|
| Pending | `CoolBadge(variant: warning)` + "PENDING" | `#FFA500` |
| Processing | Spinner + "PROCESSING" | `textSecondary` |
| Complete | `CoolBadge(variant: success)` + "COMPLETE" | `#00FF00` |
| Failed | `CoolBadge(variant: danger)` + "FAILED" | `#FF3B30` |
| Cancelled | `CoolBadge(variant: secondary)` + "CANCELLED" | `textSecondary` |

### MoMo USSD Handoff

MoMo payments use USSD handoff, not in-app processing:

1. Show amount + recipient confirmation screen.
2. User taps "PAY" CTA.
3. App launches USSD dial intent externally.
4. App shows "WAITING FOR CONFIRMATION" state with timer.
5. SMS listener (background) updates state when confirmation detected.
6. If timeout: show "UNCONFIRMED" with manual refresh option.

Never show fake success. Never hide the USSD handoff nature of the payment.

## Permission Flows

### Permission Request Rules

1. **Explain before requesting** — show why on a clear screen before system dialog.
2. **One permission at a time** — never batch-request multiple permissions.
3. **Graceful degradation** — if denied, explain what's unavailable and provide fallback.
4. **No repeated nagging** — if denied twice, stop asking until user initiates action.

### Biometric Permission

BioPay biometric enrollment:
1. Explain what biometric data is used for.
2. Request permission with system dialog.
3. If denied: show "BIOMETRIC UNAVAILABLE" with PIN fallback option.

## Accessibility Standards

### Touch Targets

| Element | Minimum Size | Comfortable Size |
|---|---|---|
| Buttons, list rows | 48dp × 48dp | 56dp × 56dp |
| Icon buttons | 44dp × 44dp | 48dp × 48dp |
| Bottom nav items | 48dp × 48dp | 64dp tall |
| Checkboxes, switches | 44dp × 44dp | 48dp × 48dp |

### Color Contrast

Dark-only system contrast requirements:

| Text Type | Foreground | Background | Ratio |
|---|---|---|---|
| Primary text | `#FFFFFF` | `#050505` | > 18:1 ✅ |
| Secondary text | `#888888` | `#050505` | > 4.5:1 ✅ |
| Primary accent | `#0047AB` | `#050505` | check > 3:1 |
| On primary | `#FFFFFF` | `#0047AB` | > 4.5:1 ✅ |
| Gold accent | `#FFD700` | `#050505` | check > 3:1 |
| Neon success | `#00FF00` | `#050505` | > 4.5:1 ✅ |
| Danger | `#FF3B30` | `#050505` | > 4.5:1 ✅ |

Rules:
- Never use color alone to convey meaning — always pair with icon, label, or shape.
- mobi-label (`textSecondary` at 10px) is acceptable because it's a supplementary descriptor, never primary.
- Blue and gold accents used on dark backgrounds must be checked for 3:1 minimum.

### Screen Reader Support

- All interactive elements: `Semantics` label required.
- Images: meaningful `semanticsLabel` or `excludeFromSemantics: true`.
- Custom widgets: implement `Semantics(button: true, label: ...)` for actions.
- Financial values: announce with currency and full number (no abbreviation).
- Status badges: announce variant + text (e.g., "success badge, verified").

### Focus Order

- Logical top-to-bottom, left-to-right reading order.
- Modals and sheets: trap focus within the overlay.
- On dismiss: return focus to trigger element.
- Skip navigation: not needed in mobile (3-item nav is compact enough).

### Reduced Motion

- `MediaQuery.disableAnimations` must be respected.
- Skip decorative animations (atmospheric blobs, mobi-grid pulse).
- Keep functional transitions (page push/pop) but reduce to instant.
- Never block user interaction behind animation completion.

## Localization

### Language Support

EN (primary) and FR (secondary). All user-facing strings must be localized.

### Localization Rules

1. All copy is externalized via ARB/l10n — no hardcoded strings.
2. Currency formatting: locale-aware (RWF uses comma separator, EUR uses period).
3. Date formatting: locale-aware via `intl`.
4. RTL: not required (EN/FR are LTR).
5. Uppercase transform on headings must work for both EN and FR.

### Copy Constraints

- Headlines: 2-4 words (applies in both languages).
- Labels: ≤ 12 characters where possible (fits mobi-label space).
- If French translation exceeds budget, abbreviate or restructure — don't break layout.

## Error State Design

Every error state must include:

1. **Clear title** — "PAYMENT FAILED", "CONNECTION ERROR" (uppercase, Barlow Condensed)
2. **Brief explanation** — one sentence max, Inter, textSecondary
3. **Action CTA** — "RETRY", "GO BACK", "CONTACT SUPPORT"
4. **No blame language** — no "you did X wrong"
5. **Never raw error codes** — translate to human language

### Error Card Pattern

```dart
CoolCard(
  variant: CoolCardVariant.outline,
  child: Column(
    children: [
      Icon(LucideIcons.alertTriangle, color: CoolColors.danger, size: 24),
      SizedBox(height: CoolSpace.m3),
      Text('CONNECTION ERROR', style: headlineSmall),
      SizedBox(height: CoolSpace.m2),
      Text('Unable to reach the server. Check your connection.', 
           style: bodySmall.copyWith(color: CoolColors.textSecondary)),
      SizedBox(height: CoolSpace.m4),
      CoolButton(variant: CoolButtonVariant.primary, child: Text('RETRY')),
    ],
  ),
)
```

## Audit Commands

```sh
# Missing Semantics labels
rg "GestureDetector\|InkWell\|TextButton" lib/ --files-without-match "Semantics\|semanticsLabel"

# Touch target violations (height < 48)
rg "SizedBox\(height: [0-3][0-9]\b" lib/shared/widgets/ --count

# Hardcoded strings
rg "Text\('[A-Z]" lib/features/ | grep -v "\.l10n\|AppLocalizations\|context\."
```

## Cross-References

- Color contrast values → `design-foundations` skill
- Touch target sizes in component specs → `component-navigation` skill
- Module-specific trust rules → `module-partner-ux` skill
- Screen error state composition → `screen-composition` skill
