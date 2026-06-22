# Collect Market Expansion And Stripe Diaspora Goal

Generated: 2026-06-21

## Objective

Implement the market-ready Collect pivot from a group-savings-only app into a real-feeling collection platform for ibimina, sports fan clubs, churches, weddings, and other contribution communities, while preserving Collect's core non-custodial MoMo/SMS evidence model for Rwanda and adding Stripe-powered diaspora contribution rails for Europe, the United Kingdom, and the United States.

This goal supersedes the earlier simplified-product rule that removed categories, targets, covers, and campaign-like context. It does not supersede the privacy, Collect ID, no-real-name, no-manual-SMS, no-contributor-reported-transaction-ID, and no-runtime-demo-data rules.

## Product Positioning

Collect should feel like a practical contribution app for real communities, not a generic group ledger. The first market niches are:

- Ikimina: group savings, rotating contributions, member obligations, recurring periods, arrears, and payout-readiness records.
- Sport: fan clubs and club-support collections such as Rayon Sports, including match-day drives, travel support, kit support, and supporter-led campaigns.
- Church: offerings, tithes, building funds, event support, choir/youth groups, and other donation streams.
- Wedding: contribution committees, gift pools, service-provider budgets, pledges, and family/friend contribution tracking.
- Other: a flexible fallback for funerals, schools, medical support, community events, creators, and custom collections without inventing public claims the app cannot verify.

## Core Product Rules To Preserve

- Users remain represented by Collect ID in product surfaces; no real-name requirement is introduced.
- Rwanda in-country payments remain non-custodial: the group receiver is paid through MoMo, and Collect records evidence through owner-side SMS capture and backend allocation.
- Runtime app state must not rely on demo, fixture, or seeded placeholder collections. Templates may guide creation, but created groups must be user-owned records.
- Categories must not become a public fundraising directory until moderation, abuse review, reporting, and release approval are implemented.
- External releases, Stripe go-live, compliance submissions, app-store submissions, provider outreach, and live financial activation require explicit recorded human approval.

## Stripe Architecture Decision

Use the Stripe integration as a diaspora rail, not as the default Rwanda MoMo flow.

- Europe: use domestic EUR Bank Transfer through Stripe `customer_balance` with `bank_transfer.type=eu_bank_transfer` and `currency=eur`.
- United Kingdom: use domestic GBP Bank Transfer through Stripe `customer_balance` with `bank_transfer.type=gb_bank_transfer` and `currency=gbp`.
- United States: use ACH Direct Debit through Stripe `us_bank_account` with standard settlement and microdeposit verification only.
- Canada: use domestic Canadian Pre-authorized Debit through Stripe `acss_debit`, `currency=cad`, sporadic personal PAD mandate terms, and microdeposit verification only. This is the Stripe-documented Canadian domestic bank rail; do not use cards, Interac, third-party gateways, instant verification, or FX for Canada in this scope.
- No instant bank account validation, Financial Connections instant verification, two-day ACH settlement, SEPA Direct Debit, cards, wallets, BNPL, cross-border bank transfer, or other Stripe methods are allowed in this fee-sensitive scope unless the owner explicitly approves a later change.
- Fees must be kept to the base domestic bank-rail pricing target only: ACH Direct Debit standard settlement at the 0.8% capped rail, Canadian Pre-authorized Debit at Stripe's transparent domestic CAD PAD rail, and bank-transfer rails at the 0.5% capped rail where Stripe pricing confirms that rate. Avoid currency conversion and international transaction add-ons by presenting/settling the matching domestic currency and region path.
- Use Checkout Sessions for on-session diaspora contribution checkout where hosted or embedded Stripe UX is acceptable.
- Use SetupIntents only for US ACH Direct Debit and Canadian Pre-authorized Debit saved bank accounts.
- Use PaymentIntents only when Collect must model payment state independently, for example off-session repeat pulls after a valid mandate.
- Use webhook-driven reconciliation as the source of truth for Stripe payment status; never trust only the client return URL.
- Do not use the Charges API, Sources API, Tokens API, or legacy Card Element.

## Stripe Source Map

- Stripe API version target from installed Stripe skill: `2026-02-25.clover`.
- PaymentIntents, customer balance bank transfers, SetupIntents for US ACH, and deprecated API guidance: Stripe payments best-practices skill and Stripe Payments docs.
- Connect platform design should use Accounts v2 and controller properties if Collect later routes funds to connected collection owners through Stripe instead of receiving platform-controlled diaspora funds.
- EUR and GBP Bank Transfer use Stripe customer balance bank-transfer funding and virtual account instructions.
- ACH Direct Debit is reusable and delayed-notification for US bank accounts; Collect forces microdeposit verification to avoid instant bank validation charges.

## Data Model Workstream

Create a forward-only Supabase migration that introduces a clean category model without resurrecting legacy unsafe fields.

1. Add a stable `collection_type` or enum-backed category field with values:
   - `ikimina`
   - `sport`
   - `church`
   - `wedding`
   - `other`
2. Add optional subtype/context fields that do not expose personal data:
   - `category_subtype`
   - `purpose_label`
   - `cadence`
   - `suggested_amount_rwf`
   - `diaspora_enabled`
   - `diaspora_regions`
   - `moderation_status`
3. Keep existing receiver records as the Rwanda MoMo source of truth.
4. Add diaspora payment tables without posting financial records from client callbacks:
   - `stripe_customers`
   - `stripe_payment_methods`
   - `diaspora_contribution_intents`
   - `stripe_webhook_events`
   - `stripe_contribution_allocations`
5. Store only Stripe IDs, statuses, method type, country/region, currency, mandate references, last4-style safe display metadata, and hashed/linking identifiers needed for reconciliation.
6. Add RLS policies so users can see their own saved methods and intents, collection owners can see safe contribution status for their groups, and admins can review operational events.
7. Preserve client-safe views: no full bank details, no raw webhook payloads in mobile views, no full phone numbers in normal group screens.

## Backend And Edge Function Workstream

Add Supabase Edge Functions with strict server-side Stripe handling.

1. `stripe-create-customer`
   - Creates or returns a Stripe Customer for the authenticated Collect profile.
   - Requires authenticated user and stores only the Stripe customer ID and safe metadata.
2. `stripe-create-setup-intent`
   - Creates SetupIntents only for US ACH Direct Debit saved-bank flows.
   - Forces `payment_method_options[us_bank_account][verification_method]=microdeposits`.
   - Returns only the client secret required by the Stripe client SDK.
3. `stripe-create-diaspora-contribution`
   - Creates a Checkout Session or PaymentIntent for a specific collection and amount.
   - Enforces allowed region, currency, category, collection status, and diaspora enablement.
   - Creates a local pending diaspora contribution intent before returning client-side continuation data.
4. `stripe-webhook`
   - Verifies the Stripe signature.
   - Idempotently stores event IDs.
   - Updates local contribution intent status from Stripe events.
   - Posts Collect contribution records only after terminal/sufficient Stripe confirmation for the relevant delayed-notification method.
   - Routes failed, disputed, returned, or mandate-revoked events to admin review.
5. `stripe-admin-review`
   - Lets authorized admins resolve edge cases without exposing secrets or raw bank details.

## Mobile UX Workstream

Make category selection first-class while keeping group creation efficient.

1. Add a category step before the receiver step:
   - Ikimina
   - Sport
   - Church
   - Wedding
   - Other
2. Use category-aware labels and defaults:
   - Ikimina: contribution cycle, expected amount, member obligation language.
   - Sport: fan club, club support, match-day or campaign purpose. Include Rayon Sports as an example template, not a hard-coded public claim.
   - Church: offering, tithe, building fund, mission/event support.
   - Wedding: committee contribution, gift pool, budget support.
   - Other: neutral custom purpose.
3. Add category-aware empty states, group cards, group detail headers, share text, and contribution prompts.
4. Add diaspora contribution entry only when the collection owner enables diaspora support and a valid region/currency path exists.
5. Add a saved bank-account management screen under Settings:
   - saved method display with region, bank type, last4-safe metadata, mandate status, and remove action;
   - clear pending/processing wording for delayed bank-debit methods;
   - no raw bank-account collection in custom Flutter fields unless Stripe SDK/Elements handles it.
6. Keep Rwanda MoMo and diaspora Stripe as separate payment tabs or segmented controls on the contribution screen.
7. Do not create a public landing or marketing-only page inside the app; the first screen remains a usable product surface.

## Admin PWA Workstream

Extend admin controls for category and Stripe operations.

1. Add category filters to groups and contribution views.
2. Add moderation status for categories that can imply public fundraising or sensitive community claims.
3. Add diaspora contribution monitoring:
   - pending setup;
   - processing bank debit;
   - succeeded;
   - failed;
   - returned/disputed;
   - mandate revoked;
   - needs review.
4. Add webhook event idempotency and replay visibility.
5. Add export-safe evidence views that show Collect IDs, group IDs, Stripe object IDs, statuses, timestamps, and amounts without raw bank details.
6. Add admin-only controls for enabling diaspora per collection and region allowlists for the approved ACH Direct Debit and EUR Bank Transfer rails only.

## Compliance And Risk Workstream

Before enabling live Stripe payments, complete a documented review covering:

- whether Collect is merchant of record, a platform, or a technical processor for each diaspora rail;
- whether Stripe Connect Accounts v2 is required for routing funds to collection owners;
- whether funds flow creates custody, money-transmission, charitable fundraising, or donation-platform obligations in target markets;
- category-specific risks for churches, sports clubs, weddings, public figures, medical support, funerals, and schools;
- refund, dispute, return, mandate revocation, and failed debit handling;
   - user consent and mandate language for ACH, plus EUR Bank Transfer instruction and reconciliation language;
- privacy policy, data deletion, account deletion, and financial-data disclosures;
- Play Console Data safety updates for Stripe/payment-method data;
- support and escalation runbooks.

## Test And Evidence Workstream

Add or update tests before marking this goal complete.

1. Supabase contract tests
   - Category enum/constraint and client-safe view exposure.
   - RLS coverage for category, diaspora payment methods, contribution intents, webhook events, and admin views.
   - No raw bank details in client-safe views.
   - Stripe webhook idempotency.
2. Flutter model/repository tests
   - Category parse/copy/create/update paths.
   - Category-aware fixture tests only under explicit fixture constructors.
   - Stripe setup/contribution intent state mapping.
3. Widget and route tests
   - Create group category step.
   - Category-specific group cards and details.
   - MoMo versus diaspora contribution rail selection.
   - Saved bank-account settings states.
4. Admin PWA tests
   - Category filters.
   - Diaspora payment review queues.
   - Permission gates for sensitive payment controls.
5. Release gates
   - Update `scripts/collect_product_boundary_scan.sh` so category reintroduction is allowed only in the approved market-expansion surfaces.
   - Update `test/supabase_contract_test.dart` expectations that currently reject category exposure.
   - Run focused tests first, then `scripts/repo_wide_qa_uat.sh --json`.
   - Archive `summary.json`, `evidence_index.json`, and relevant logs under the existing evidence structure.

## Implementation Phases

### Phase 1: Product And Schema Foundation

- Update product docs to mark the category pivot as owner-approved.
- Add category domain model and forward-only migration.
- Update client-safe views and repository mapping.
- Add category UI in group creation, cards, detail, and share surfaces.
- Update tests and boundary scan for the new approved category surface.

### Phase 2: Real Niche Experience

- Add category-specific templates, copy, empty states, and group lifecycle states.
- Add ikimina recurring/obligation refinements where current recurring periods already exist.
- Add sport/church/wedding purpose presets without requiring real names or public directory claims.
- Verify mobile route render and persona UAT across all five categories.

### Phase 3: Stripe Sandbox Diaspora Rails

- Add Stripe dependency and server-side Edge Functions.
- Add local environment documentation without committing secrets.
- Implement SetupIntent saved-bank-account flows only for US ACH Direct Debit.
- Implement EUR Bank Transfer contribution flows through Stripe customer balance and EU bank-transfer instructions.
- Implement sandbox contribution creation and webhook reconciliation.
- Add admin monitoring for pending/processing/succeeded/failed/returned events.

### Phase 4: Compliance, Go-Live, And Release

- Complete Stripe go-live checklist and compliance review.
- Decide whether Connect Accounts v2 is required before any owner payout or marketplace routing.
- Update privacy/Data safety/release docs for Stripe financial data.
- Run full repo QA/UAT and release gates.
- Obtain explicit human approval before enabling live Stripe keys, submitting app updates, or making external provider/compliance submissions.

## Done Criteria

- Active Codex goal is complete only when the product, schema, backend, mobile, admin, test, and release evidence above are implemented and verified.
- App users can create and interact with real category-specific collections for ikimina, sport, church, wedding, and other.
- Rwanda MoMo flows still pass existing SMS/payment-intent allocation tests.
- US diaspora users can save ACH bank accounts, Europe diaspora users can initiate EUR Bank Transfer sandbox contributions, and UK diaspora users can initiate GBP Bank Transfer sandbox contributions through Stripe without raw bank data touching Collect servers or triggering currency conversion.
- Stripe webhook reconciliation is idempotent and drives local contribution status.
- Admin operators can review category and Stripe payment states safely.
- `scripts/repo_wide_qa_uat.sh --json` produces a current evidence bundle, and focused category/Stripe tests pass.
- Human approval gates are recorded for Stripe live mode, compliance/provider submissions, release submission, and any public fundraising/donation expansion.

## Explicit Non-Goals For This Goal

- Do not launch a public fundraising directory by default.
- Do not make Collect custody Rwanda MoMo funds.
- Do not route live Stripe money to collection owners until the platform/Connect/legal model is approved.
- Do not store raw bank-account details in Supabase.
- Do not submit Stripe, Play Console, regulatory, church, sports-club, or other external approvals without explicit recorded human approval.
