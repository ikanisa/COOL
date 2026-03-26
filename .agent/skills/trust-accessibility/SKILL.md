---
name: Trust & Accessibility
description: >
  Trust design rules for payments, maps, and permissions, plus accessibility
  standards (touch targets, contrast, screen readers) and localization rules
  for the COOL Flutter super-app. Use when working on payment screens,
  permission flows, maps, accessibility audits, or localization.
  Source of truth: DESIGN_SYSTEM.md §12–13.
---

# Trust & Accessibility

Use this skill when the task involves:

- Payment display screens (MoMo, tickets, checkout)
- Permission request UX (location, camera, contacts, SMS)
- Maps integration and fallback design
- Accessibility audit or remediation
- Screen reader support and semantic labels
- Touch target sizing
- Contrast ratio verification
- Localization (EN/FR) and text expansion handling

This skill is NOT for:

- Color tokens or typography → use `design-foundations`
- Screen layout or copy budgets → use `screen-composition`
- Shared widgets or routing → use `component-navigation`
- Module-specific UX → use `module-partner-ux`

## Trust Design

### Payment Displays

**Always show:**
- Recipient identity
- Route type (phone number vs. merchant code)
- Amount
- Pending vs. confirmed state
- Reference where available
- What happens next

**Never hide:**
- The receiving identity
- Whether confirmation is still pending
- Draft or manual-review state when it affects ledger meaning

### Financial Surface Tokens

Payment and financial screens must use the dedicated domain surface tokens
from `CoolSemanticColors` (see `design-foundations` skill):

| Token | Use |
|---|---|
| `financialSurface` | Wallet, balance, statement containers |
| `operationalSurface` | Payout dashboards, admin reconciliation |
| `routeSurface` | Route cost breakdowns and journey-related payments |
| `contactSurface` | WhatsApp handoff, support CTAs |

All financial amounts must use `DM Mono` font at `bodyLarge` (18dp) minimum.
Balances and totals use `headlineMedium` (30dp) or larger.

### Payment UX Rules

- MoMo payments are payer-owned USSD handoff. No API, no webhooks.
- SMS verification confirms the transaction on the device.
- "Completed" state must not display before SMS or backend confirmation.
- Payment screens feel like trust, not decoration — even on partner routes.
- Checkout reads like a final review, not a second browsing screen.
- Totals, quantities, and pending-state language must be explicit.
- MoMo handoff feels like a deliberate next step, not a surprise.

### Maps & Location

Maps are useful only when they genuinely improve trip selection. Design rules:

- List-first discovery is the default.
- Route summary as a text fallback.
- Manual place search available.
- Explicit "unavailable" copy when maps cannot load.
- Never assume maps will work. Always build the non-map path first.
- No geolocation prompts without user-initiated context.

### Permissions

Permission design must be truthful:

- **Explain why** access is needed before requesting.
- **Show current status** of the permission.
- **Offer a fallback** when the product supports one.
- **Send to system settings** only when necessary.
- **Graceful degradation** on every denial — never a dead end.
- **Contextual requests** — request location only in user-initiated map flows, camera only on QR.
- **Data minimization** — only access contacts when user explicitly triggers social features.

### Permission Audit Checklist

```
[ ] Every permission request has a pre-prompt explanation
[ ] Every permission denial has graceful degradation UX
[ ] No permissions are requested on app launch (all contextual)
[ ] Contacts access is scoped to minimum fields needed
[ ] Camera access is only for QR scanning, not profile photos without consent
[ ] Location access is only on map-related flows the user explicitly opened
```

## Accessibility

### Touch Targets — Use `CoolTapTargets`

| Token | Value | Use |
|---|---|---|
| `minimum` | 48dp | Absolute minimum for any interactive element |
| `comfortable` | 56dp | Standard payment buttons, list rows |
| `navigation` | 64dp | Primary CTA (Pay, Send, Confirm) |

- One-hand use matters for MoMo and other high-frequency transactional flows.
- Avoid tiny chips as critical controls.
- Ensure spacing between adjacent tap targets prevents mis-taps.

### Text & Contrast

- Minimum contrast ratio: **4.5:1** for body text, **3:1** for large text (WCAG 2.1 AA).
- Support dynamic type and text wrapping.
- Ensure readable contrast in both light and dark themes.
- All interactive elements must have visible focus states.
- Test text scaling at 1.0x, 1.5x, and 2.0x — screens must not overflow.

### Screen Reader

- Give amounts meaningful phrasing: "1,500 Rwandan francs" not "1500".
- Use explicit button labels (no icon-only buttons without semantic label).
- Do not rely on placeholder-only fields.
- Make error copy actionable: "Retry" not just "Error."
- Add focus traversal order to critical flows: auth, MoMo, trip booking, tickets.

### Accessibility Implementation

```dart
// Every IconButton needs a semantic label
IconButton(
  icon: const Icon(Icons.send),
  tooltip: 'Send payment',  // Serves as semantic label
  onPressed: _send,
)

// Custom gesture areas need Semantics wrapper
Semantics(
  label: 'Open group details',
  button: true,
  child: GestureDetector(
    onTap: _openGroup,
    child: _buildGroupRow(),
  ),
)

// Amount formatting for screen readers
Semantics(
  label: '${amount.toStringAsFixed(0)} Rwandan francs',
  child: Text(
    'RWF ${NumberFormat('#,##0').format(amount)}',
    style: AppTypography.mono,
  ),
)
```

### Accessibility Audit Commands

```sh
# Find interactive widgets missing semantic labels
rg "IconButton\(" lib/ -l | xargs rg -L "tooltip\|semanticsLabel"

# Find GestureDetector without Semantics
rg "GestureDetector\(" lib/ --count

# Find InkWell without semantic context
rg "InkWell\(" lib/ --count

# Count explicit Semantics usage
rg "Semantics\(" lib/ --count

# Find images missing semanticLabel
rg "Image\.\|Image(" lib/ -l | xargs rg -L "semanticLabel\|Semantics"
```

## Localization

### Language Rules

- English and French are first-order requirements.
- Account for text expansion: French is typically **15–30% longer**.
- Keep short labels short enough for French expansion.
- Format money, dates, and phone numbers by locale and country rules.
- Use ARB files for all user-facing strings — no hardcoded text.

### Money Formatting

```dart
// Rwanda
'RWF 1,500'  // No decimals for RWF

// Format by country context
String formatAmount(int amount, String country) {
  final format = NumberFormat('#,##0', country == 'RW' ? 'en_RW' : 'fr_FR');
  return '${country == 'RW' ? 'RWF' : 'EUR'} ${format.format(amount)}';
}
```

### Date & Phone Formatting

- Dates: locale-aware via `intl` package.
- Phone numbers: display in national format for the user's country.
- Always show country code prefix for cross-border displays.

## Cross-References

- Color contrast and theme tokens → `design-foundations` skill
- Screen layout for payment/permission screens → `screen-composition` skill
- Payment and permission widgets → `component-navigation` skill
- Module-specific trust rules (MoMo, Mobility) → `module-partner-ux` skill
- Full human-readable reference → `DESIGN_SYSTEM.md`
