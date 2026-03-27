---
name: Module & Partner UX
description: >
  Per-module UX rules (Home, MoMo, Groups, BioPay, Partners, Admin),
  partner sub-brand design (Rayon Sports, banks, generic), and screen
  catalog for the COOL Flutter super-app. Mobi × Rayon design system.
  Use when building module screens, partner flows, or planning screen work.
---

# Module & Partner UX

Use this skill when the task involves:

- Designing or redesigning any specific COOL module
- Partner sub-brand design (Rayon Sports, bank partners, generic partners)
- Planning which screens to build or rebuild
- Module-specific UX decisions beyond general screen composition

This skill is NOT for:

- Global color/typography/spacing tokens → use `design-foundations`
- Generic screen layout or copy budgets → use `screen-composition`
- Shared widget API or routing changes → use `component-navigation`
- Payment trust or accessibility → use `trust-accessibility`

## Product Truths

Non-negotiable constraints every module must respect:

- COOL is Flutter mobile, Android-first, dark-only, EN/FR.
- Bottom nav: 3 items — Home, BioPay, Profile.
- MoMo is accessed from Home or quick actions, not a nav tab.
- Groups accessed from Home, not a nav tab.
- Payments are payer-owned USSD handoff + Android SMS verification.
- All states (pending, draft, blocked, offline, disabled) shown honestly.
- Dark surface (#050505) with mobi-grid on all screens.

## Screen Catalog (79 Screens from React Reference)

### P0 — Core Consumer

| Screen | Route | Module |
|---|---|---|
| Home (CommandDeck) | `/home` | home |
| FanProfile | `/fan-profile` | profile |
| Splash | `/splash` | auth |
| Onboarding | `/onboarding` | auth |
| OTP | `/otp` | auth |
| OTP Verify | `/otp-verify` | auth |
| Register | `/register` | auth |
| Country Selector | `/country-selector` | auth |

### P0 — BioPay

| Screen | Route | Module |
|---|---|---|
| BioPayHub | `/biopay-hub` | biopay |
| BioPayRegister | `/biopay/register` | biopay |
| BioPayScan | `/biopay/scan` | biopay |

### P0 — MoMo

| Screen | Route | Module |
|---|---|---|
| MomoScreen | `/momo` | momo |
| MomoStatements | `/momo/statements` | momo |
| MomoQrScan | `/momo/qr-scan` | momo |
| MomoNfc | `/momo/nfc` | momo |

### P1 — Groups

| Screen | Route | Module |
|---|---|---|
| GroupsScreen | `/groups` | groups |
| GroupDetail | `/groups/:id` | groups |
| GroupLedger | `/groups/:id/ledger` | groups |
| GroupInvite | `/groups/:id/invite` | groups |
| CreateGroup | `/groups/create` | groups |

### P1 — Partners & Rayon Sports

| Screen | Route | Module |
|---|---|---|
| PartnersScreen | `/partners` | partners |
| RayonHome | `/rayon` | partners/rayon |
| FanClubs | `/rayon/clubs` | partners/rayon |
| FanClubDetail | `/rayon/clubs/:id` | partners/rayon |
| SupportClub | `/rayon/support` | partners/rayon |
| SupportDetail | `/rayon/support/:id` | partners/rayon |
| ClubShop | `/rayon/shop` | partners/rayon |
| ShopCheckout | `/rayon/shop/checkout` | partners/rayon |
| TicketsHub | `/rayon/tickets` | partners/rayon |
| MyTickets | `/rayon/my-tickets` | partners/rayon |
| TicketConfirmation | `/rayon/ticket-confirm` | partners/rayon |
| SeasonsActivities | `/rayon/seasons` | partners/rayon |
| BankPartner | `/partners/bank/:id` | partners/banks |
| BankOnboarding | `/partners/bank/:id/onboard` | partners/banks |
| PrismaPartner | `/partners/prisma` | partners |
| RadiantPartner | `/partners/radiant` | partners |
| ProductDetail | `/partners/:id/product/:pid` | partners |
| MembershipTiers | `/membership` | membership |
| MemberRegistry | `/members` | membership |
| CreditScore | `/credit` | credit |

### P2 — Admin

| Screen | Route | Module |
|---|---|---|
| AdminDashboard | `/admin` | admin |
| OperationalDashboard | `/admin/ops` | admin |
| SystemAnalytics | `/admin/analytics` | admin |
| AuditLog | `/admin/audit` | admin |
| ManageUsers | `/admin/users` | admin |
| ManagePartners | `/admin/partners` | admin |
| ManageServices | `/admin/services` | admin |
| ManageAppConfig | `/admin/config` | admin |
| ManageQuickActions | `/admin/quick-actions` | admin |
| ManageMissions | `/admin/missions` | admin |
| ManageSeasonsActivities | `/admin/seasons` | admin |
| ManageAiContent | `/admin/ai-content` | admin |
| ManageSpecialProducts | `/admin/special-products` | admin |
| ManageAdminRoles | `/admin/roles` | admin |
| AdminWorkspaces | `/admin/workspaces` | admin |

### P2 — RS Admin (Rayon Sports Admin)

| Screen | Route | Module |
|---|---|---|
| RsAdminDashboard | `/rs-admin` | partners/rayon/admin |
| RsAdminAnalytics | `/rs-admin/analytics` | partners/rayon/admin |
| RsAdminFinance | `/rs-admin/finance` | partners/rayon/admin |
| RsAdminMembers | `/rs-admin/members` | partners/rayon/admin |
| RsAdminOrders | `/rs-admin/orders` | partners/rayon/admin |
| RsAdminShop | `/rs-admin/shop` | partners/rayon/admin |
| RsAdminTickets | `/rs-admin/tickets` | partners/rayon/admin |
| RsAdminMatches | `/rs-admin/matches` | partners/rayon/admin |
| RsAdminPackages | `/rs-admin/packages` | partners/rayon/admin |
| RsAdminInitiatives | `/rs-admin/initiatives` | partners/rayon/admin |
| BankAdminWorkspace | `/admin/bank/:id` | partners/banks/admin |
| PartnerAdminWorkspace | `/admin/partner/:id` | partners/admin |

### Utility

| Screen | Route | Module |
|---|---|---|
| DesignSystem | `/design-system` | dev |

## Module UX Rules

### Home

- **CommandDeck** pattern: headline → quick actions (5-col grid) → recent activity.
- Quick actions: Send, Airtime, Pay, Join, Score.
- Recent activity: transaction rows with direction indicator.
- Header: avatar + name + search + bell (notification dot).
- Uses mobi-grid + atmospheric background.

### BioPay

- BioPay is the center nav item (replaces MoMo in nav).
- Hub shows biometric payment status and recent transactions.
- Register flow: progressive disclosure for biometric enrollment.
- Scan: camera interface for biometric verification.

### MoMo

- Accessed from Home quick actions or CommandDeck, not from nav.
- Statements are first-class, not buried.
- QR and NFC are secondary to USSD and ledger path.
- Payment state honest: pending means pending.
- Balances in JetBrains Mono at headlineMedium (24dp) minimum.

### Groups

- Accessed from Home or Profile, not from nav tab.
- Trust and recipient clarity > decorative community UI.
- Creation: progressive disclosure (name → members → rules).
- Ledger: clear, scannable, JetBrains Mono for amounts.
- Savings progress: CoolProgress bar with percentage.

### Partners & Rayon

- Rayon is the primary partner with dedicated screens.
- Brand expression: royal blue + gold on entry/discovery screens.
- Payment screens: trust-first, no heavy branding.
- All headings: Barlow Condensed, uppercase (same as system default).
- No green as primary CTA color on Rayon routes.

### Profile

- Avatar card with badges (Verified, tier level).
- Grouped setting rows — quiet, factual.
- Account actions at bottom.

### Admin

- Data-first: tables, rows, explicit states, action buttons.
- No consumer marketing chrome.
- Use Recharts-style data visualization patterns.
- Operational dashboard: key metrics → charts → action items.

## Partner Sub-Brand Rules

### Rayon Sports

The primary partner. Gets its own screen family but uses the **same design system**.

- Primary: `#0047AB` (royal blue) — already the system primary.
- Accent: `#FFD700` (gold) — already the system accent.
- No separate brand palette needed — system palette IS the Rayon palette.
- Headings: Barlow Condensed uppercase (same as system).
- Values: JetBrains Mono (same as system).

### Bank Partners

- 3 standard CTA cards per bank partner page maximum.
- Standard COOL design system — no custom component variants.
- Bank logo via `CoolAvatar`.

### Generic Partners

- Standard COOL design system.
- Brand expression through accent color only, not structural changes.

## Abolition of Legacy Patterns

All of the following are **abolished** and must be removed if found:

- `CoolPalette` / `AppColors` / warm earthy palette
- `CoolSemanticColors` (old green-tinted system)
- Domain-specific surface tokens (financialSurface, teamSurface, etc.)
- Claymorphism shadows (clay, glass recipes)
- Manrope / DM Mono fonts
- 5-item bottom navigation
- Light theme / dual theme support
- Oversized radii (sm=16, md=22, lg=28)
- `CoolGlassCard` (replaced by `CoolCard(variant: glass)`)

## Audit Commands

```sh
# Module screen counts
for mod in auth biopay credit groups home momo partners profile admin; do
  echo "$mod: $(find lib/features/$mod -name '*screen.dart' 2>/dev/null | wc -l | tr -d ' ')"
done

# Legacy pattern detection (must be zero)
rg "CoolPalette\|AppColors\.\|CoolSemanticColors\|Manrope\|DM.Mono" lib/ --count
rg "financialSurface\|teamSurface\|operationalSurface\|analyticsSurface" lib/ --count
rg "CoolShadows\.clay\|CoolShadows\.glass\|CoolGlassCard" lib/ --count
```

## Cross-References

- Visual tokens → `design-foundations` skill
- Screen composition rules → `screen-composition` skill
- Shared widgets → `component-navigation` skill
- Payment trust and accessibility → `trust-accessibility` skill
