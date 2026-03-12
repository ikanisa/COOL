# Frontend UI Simplification Audit

Date: March 12, 2026
Scope: Flutter mobile frontend in `lib/`
Method: code-grounded screen audit plus external research on current minimalist mobile UI principles and world-class product patterns.

This is not a pixel-perfect screenshot review. It is a screen architecture, content density, and interaction audit based on the implemented routes, widgets, copy, and layout structure.

## Research Base

Primary design guidance used:

- Apple Design, "UI Design Dos and Don'ts": prioritize hierarchy, make touch targets easy to identify, and remove visual confusion.
- Apple Human Interface Guidelines, "Tab views" and "Sidebars": top-level navigation should stay stable and low-friction.
- Samsung One UI, "Design principles": create delight, make it easy to use, and keep layouts visually comfortable.
- Samsung One UI, "Writing guidelines": keep labels short, informative, and easy to scan.

Official product surfaces used as exemplars:

- Uber app product pages: one dominant task, map-led context, secondary actions deferred.
- Notion mobile product pages: low-chrome, content-first, restrained visual language.
- Monzo product pages: clear account snapshot first, quick actions second, detail later.
- Cash App product pages: direct task framing, few competing choices, concise labels.
- Airbnb app product pages: high whitespace, pacing, and progressive disclosure.

Research links:

- Apple Design Tips: https://developer.apple.com/design/tips/
- Apple HIG Tab Views: https://developer.apple.com/design/human-interface-guidelines/tab-views
- Apple HIG Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Samsung One UI Design Principles: https://developer.samsung.com/one-ui/design/design-principles.html
- Samsung One UI Writing Guidelines: https://developer.samsung.com/one-ui/design/writing-guidelines/labels-and-text.html
- Uber App: https://www.uber.com/us/en/ride/app/
- Notion Mobile: https://www.notion.com/product/notion-mobile
- Monzo Bank Account: https://monzo.com/our-products/bank-account/
- Cash App: https://cash.app/

Inference from those sources:

- The best mobile apps do not win by adding more modules to the same screen.
- They win by making the first action obvious, reducing visible decisions, and letting detail appear only after intent is clear.

## Executive Summary

The current app is visually busy, verbally dense, and structurally overloaded.

The main causes are systemic:

- Heavy chrome everywhere: glow orbs, gradients, borders, shadows, emoji, accent chips, and dense cards appear on nearly every surface.
- Too much explanatory copy: many screens explain the product, the backend state, and the policy model at the same time.
- Too many equal-weight sections: users often see 4 to 8 cards with similar emphasis before they know what to do.
- Too many navigation layers: bottom nav, segmented tabs, filter chips, cards, and inline actions often compete on the same screen.
- Large monolithic screen files correlate with cluttered screen responsibilities.

Top code-based complexity hotspots:

- `schedule_trip_screen.dart`: 2141 lines
- `profile_screen.dart`: 1749 lines
- `trip_board_screen.dart`: 1532 lines
- `credit_readiness_screen.dart`: 1478 lines
- `driver_profile_screen.dart`: 1434 lines
- `mobility_home_screen.dart`: 1347 lines
- `bank_partner_screen.dart`: 1347 lines
- `credit_score_screen.dart`: 1328 lines
- `prisma_partner_screen.dart`: 1230 lines
- `support_detail_screen.dart`: 1137 lines
- `momo_screen.dart`: 1131 lines
- `fan_profile_screen.dart`: 1018 lines

These screens should be treated as redesign targets, not incremental tidy-up targets.

## Design Direction

Target state for this app:

- One clear primary task per screen.
- One primary CTA above the fold.
- Short labels, short helper text, and no policy explanations in the main flow.
- Fewer cards, larger content blocks, quieter surfaces.
- Details move into drill-down, sheets, tabs, or secondary routes.
- Decorative color is used to signal priority, not everywhere.
- Partner and admin surfaces become structurally simpler instead of inheriting the same consumer chrome.

## Review Checklist

Use this checklist for every screen review. A screen should fail if more than 4 items fail.

### 1. Goal And Hierarchy

- Can a first-time user explain the screen's purpose in 3 seconds?
- Is there exactly one primary task above the fold?
- Is the most important information visually dominant by size, contrast, and placement?
- Are secondary tasks visually demoted?
- Does the screen avoid two hero areas competing at once?

### 2. Copy And Labeling

- Is the headline 2 to 6 words?
- Is the supporting copy 1 short sentence max above the fold?
- Are labels broad and scan-friendly instead of technical or internal?
- Are disclaimers, caveats, and backend explanations moved out of the main path?
- Are CTA labels action-first and specific?

### 3. Layout Density

- Are there no more than 3 visually separate blocks above the fold?
- Are there no more than 5 primary actions on the full screen?
- Are stacked cards reduced where a list or grouped section would work better?
- Is whitespace used to separate meaning, not just decorate?
- Does the screen avoid combining map, tabs, chips, cards, and large CTAs in one viewport?

### 4. Visual Language

- Are gradients, glows, shadows, borders, and accents restrained?
- Are emojis removed unless they materially aid recognition?
- Is the accent color reserved for interactive priority, not repeated on every element?
- Are surfaces flatter and quieter than they are now?
- Is the screen still legible with fewer decorative effects?

### 5. Navigation And Actions

- Is the top navigation model obvious and stable?
- Does the screen avoid mixing primary navigation and local filters without hierarchy?
- Are destructive or administrative actions moved away from everyday actions?
- Are extra actions moved into overflow, bottom sheets, or detail screens?
- Can users complete the main task without reading everything?

### 6. Forms

- Are only essential fields shown at first?
- Are optional fields hidden behind "Add details" or secondary disclosure?
- Are defaults and autofill used aggressively?
- Are helper texts short and near the field, not paragraph-length?
- Are complex setup choices split into steps when the form exceeds 6 inputs?

### 7. Lists And Data

- Does each row show only the minimum needed to choose or act?
- Are large stat clusters reduced to 2 or 3 headline metrics?
- Are status chips used sparingly?
- Is historical data moved below the main decision area or into a dedicated screen?
- Is filtering simplified to the few dimensions users actually use?

### 8. Empty, Error, And Placeholder States

- Is the empty state one headline, one sentence, one CTA?
- Does the error state avoid dumping raw system messages into the main UI?
- Are not-live-yet routes hidden, collapsed, or converted into thin compatibility states?
- Do loading states preserve structure without adding noise?
- Is there no fake or placeholder data competing with live data?

## System-Wide Changes Required First

These changes should happen before or alongside screen redesigns.

### Visual System

- Flatten `CoolCard`: reduce shadow depth, remove default gradient, use a quiet single-tone surface by default.
- Simplify `CoolButton`: remove heavy glow and gradient from the default primary button; keep one strong fill and one subtle secondary style.
- Reduce `CoolScreenBackground`: keep one subtle background treatment app-wide instead of three glow orbs on every screen.
- Reserve accent green for primary CTA, active state, and success only.
- Remove emoji-first UI unless the emoji is part of a partner brand or an explicit empty-state illustration.

### Content System

- Cap above-the-fold helper copy to one sentence.
- Replace internal wording like "backed by Supabase," "internal preparation check," and route compatibility explanations on user screens.
- Standardize CTA verbs: `Continue`, `Verify`, `Create group`, `Join group`, `Pay`, `View details`, `Open support`.
- Replace long status explanations with short labels plus an optional `Learn more` affordance.

### Navigation System

- Keep bottom nav limited to stable top-level destinations only.
- Use local segmented controls or chips only when they directly alter the visible list.
- If a screen already has tabs, avoid also making the body card-based navigation.
- Move partner discovery, partner detail, and partner transactions into cleaner step-down flows.

## Screen-By-Screen Audit

Priority key:

- P0: must simplify first
- P1: core user journey
- P2: important but after core
- P3: internal or secondary

### Auth

#### Splash

- File: `lib/features/auth/screens/splash_screen.dart`
- Priority: P1
- Problems:
  - Brand, tagline, and restore-failure card all compete on a screen that should only reassure and route.
  - Restore failure appears inside the splash experience instead of a dedicated recovery state.
- Needed changes:
  - Keep logo, app name, and one quiet loading indicator.
  - Move restore failure to a separate blocking state with one recovery CTA.
  - Remove tagline from splash.

#### Onboarding

- File: `lib/features/auth/screens/onboarding_screen.dart`
- Priority: P1
- Problems:
  - Two similar CTAs compete.
  - Footer trust copy is decorative noise.
  - Language selector is visually equal to starting the app.
- Needed changes:
  - Keep one headline, one subline, one primary CTA.
  - Demote language switch to text buttons or a tertiary control.
  - Replace secondary button with a text link for existing users.
  - Remove trust-footer sentence from the main hero.

#### OTP Entry

- File: `lib/features/auth/screens/otp_screen.dart`
- Priority: P1
- Problems:
  - The screen repeats "WhatsApp number" in title and helper copy.
  - Terms and privacy content risks adding pre-submit clutter.
  - Country selection and phone entry are still visually dense.
- Needed changes:
  - Use one short header: `Enter your WhatsApp number`.
  - Keep a single helper sentence or none.
  - Shorten legal copy and push it below the primary CTA.
  - Tighten the input block into one calm form section.

#### OTP Verify

- File: `lib/features/auth/screens/otp_verify_screen.dart`
- Priority: P1
- Problems:
  - Mostly clean already, but still more vertical space and copy than needed.
- Needed changes:
  - Keep title, phone, code entry, resend, and CTA only.
  - Shorten resend copy.
  - Ensure error text is short and human-readable.

#### Register / Setup Profile

- File: `lib/features/auth/screens/register_screen.dart`
- Priority: P1
- Problems:
  - Too many inputs and setup choices on one screen.
  - Avatar preview is decorative at this step.
  - Country and MoMo setup details are more detailed than needed for first completion.
- Needed changes:
  - Split into 2 steps: identity first, MoMo details second.
  - Remove avatar preview from initial completion.
  - Hide optional merchant code and driver setup behind `Add details`.
  - Keep only essential fields required to finish account creation.

### Shell And Core

#### App Shell / Bottom Navigation

- File: `lib/core/router/shell_route.dart`
- Priority: P1
- Problems:
  - The center FAB plus 5-slot nav makes the bar feel busier than needed.
  - A hidden navigation slot for the FAB increases conceptual noise.
- Needed changes:
  - Consider 4 clean destinations and move MoMo into Home quick action or a persistent top action.
  - If keeping the center CTA, visually separate it as a task action, not a fake nav tab.
  - Reduce label styling and chrome.

#### Home

- File: `lib/features/home/screens/home_screen.dart`
- Priority: P0
- Problems:
  - Banner, overview card, quick access grid, quests, and recent activity compete.
  - Hero copy is too descriptive for a home dashboard.
  - Quick actions and quests can overwhelm the real account state.
- Needed changes:
  - Make the first viewport: greeting or `Home`, balance snapshot, 2 to 4 quick actions, activity preview.
  - Move quests below activity or into a separate missions area.
  - Collapse seasonal banner unless it is time-sensitive and actionable.
  - Reduce quick action titles to short verbs or nouns.

#### Profile

- File: `lib/features/profile/screens/profile_screen.dart`
- Priority: P0
- Problems:
  - The profile tries to be identity hub, settings app, MoMo setup, status view, credit launcher, admin launcher, and security center at once.
  - Too many grouped rows with equal weight.
  - Destructive actions live too close to normal account actions.
- Needed changes:
  - Reframe into 4 sections only: Profile, Payments, Preferences, Support.
  - Move admin entry into a hidden/internal area.
  - Move Delete Account and Sign Out into a final footer danger zone.
  - Show only key account rows by default; use nested detail screens for language, notifications, MoMo edit, credit.
  - Keep QR and status as optional secondary modules, not mandatory blocks.

### Groups

#### Groups List

- File: `lib/features/groups/screens/groups_screen.dart`
- Priority: P1
- Problems:
  - Tabs use emoji and too many filter modes.
  - The create-group banner takes strong hero weight even when users want to browse.
  - Group cards likely expose too many badges and metadata at once.
- Needed changes:
  - Reduce filters to `Mine`, `Public`, and one optional type filter.
  - Turn create-group into a compact top action instead of a hero banner.
  - Simplify list cards to name, amount, progress, member count, and one secondary label.

#### Create Group

- File: `lib/features/groups/screens/create_group_screen.dart`
- Priority: P0
- Problems:
  - Too many decisions up front: type, visibility, frequency, bank partner, route type, target, contribution, description.
  - Info banners and selection cards compete with the form itself.
- Needed changes:
  - Split into steps: group basics, money setup, sharing/visibility.
  - Replace large type cards with a simpler segmented choice.
  - Hide community route type unless the selected country actually needs it.
  - Keep description optional and collapsed.

#### Group Detail

- File: `lib/features/groups/screens/group_detail_screen.dart`
- Priority: P1
- Problems:
  - Hero card contains identity, status, target, progress, custodian, cadence, and description before the main action.
  - Too many top-level actions: contribute, join, share, invite, plus amount chips.
  - Members and contribution history on the same page increase length and noise.
- Needed changes:
  - Reduce hero to name, balance/progress, and one primary CTA.
  - Put sharing and invite into overflow or a bottom sheet.
  - Move contribution presets into the payment sheet.
  - Make members and history separate tabs or subroutes.

#### Group Invite

- File: `lib/features/groups/screens/group_invite_screen.dart`
- Priority: P2
- Problems:
  - Invite code, hero, join explanation, and membership logic can read as procedural rather than welcoming.
- Needed changes:
  - Show inviter/group identity first, one sentence of context, one CTA.
  - Hide technical invite-code framing except as a small secondary detail.
  - Keep membership consequence copy shorter.

### Mobile Money

#### MoMo Hub

- File: `lib/features/momo/screens/momo_screen.dart`
- Priority: P0
- Problems:
  - Four strong cards stack before a user chooses a path.
  - Statements, USSD, QR, and NFC all fight for top-level priority.
  - Copy is too explanatory and operational.
- Needed changes:
  - Convert to a mode selector with 3 primary tasks: `Pay`, `Receive`, `Statements`.
  - Put NFC behind `More ways to pay`.
  - Turn QR and USSD into content of the selected mode, not separate equal hero cards.
  - Remove long descriptive paragraphs and sample USSD detail from the default view.

#### MoMo Statements

- File: `lib/features/momo/screens/momo_statements_screen.dart`
- Priority: P2
- Problems:
  - App bar tabs plus date chips plus overview card create heavy top chrome.
  - The overview card and filters may be too large relative to the actual ledger rows.
- Needed changes:
  - Keep one segmented choice at a time: account type or time window, not both at equal emphasis.
  - Shrink overview into a thin summary strip.
  - Make rows cleaner and drill into detail on tap.

### Mobility

#### Mobility Home

- File: `lib/features/mobility/screens/mobility_home_screen.dart`
- Priority: P0
- Problems:
  - Discovery feedback, driver mode, map, filters, tabs, content slivers, and a large CTA all appear in one scroll.
  - This is too many navigation and state systems for one screen.
- Needed changes:
  - Separate rider and driver mode at the top level.
  - Keep the consumer view to: current location, search/destination CTA, nearby options.
  - Move map into an expandable region or dedicated exploration view.
  - Reduce filters to the few vehicle types used most often.
  - Make schedule trip a top action, not a giant footer CTA after multiple sections.

#### Schedule Trip

- File: `lib/features/mobility/screens/schedule_trip_screen.dart`
- Priority: P0
- Problems:
  - The screen is extremely large and likely mixes search, route preview, timing, recurrence, vehicle preference, seats, return trip, and notes in one form.
  - This is a multi-step flow implemented as one page.
- Needed changes:
  - Break into steps: route, time, ride options, review.
  - Hide recurrence and return trip behind optional toggles that reveal secondary steps.
  - Keep route preview lightweight.
  - Move price note and advanced options into `Add details`.

#### Trip Board

- File: `lib/features/mobility/screens/trip_board_screen.dart`
- Priority: P1
- Problems:
  - Public marketplace and `My Posted Trips` both compete within the same screen.
  - Status, actions, filters, and WhatsApp operations likely create dense cards.
- Needed changes:
  - Split into two tabs: `Explore trips` and `My trips`.
  - Keep each trip row to route, time, price/vehicle, and one CTA.
  - Move cancel, pause, repost, delete into row overflow.

#### Driver Profile

- File: `lib/features/mobility/screens/driver_profile_screen.dart`
- Priority: P1
- Problems:
  - The screen merges stats, subscription sales, vehicle info, availability, and scheduled trips.
  - Subscription banners and vehicle editing compete with operational status.
- Needed changes:
  - First screen: online status, today's trips, subscription status.
  - Move vehicle details into a dedicated `Vehicle` screen.
  - Move plan comparison and purchase into a separate `Subscription` screen.
  - Keep stats to 2 or 3 headline numbers.

### Credit

#### Credit Score

- File: `lib/features/credit/screens/credit_score_screen.dart`
- Priority: P1
- Problems:
  - Hero ring, banners, factors, explanations, improvement advice, applications, and history all appear in one long surface.
  - The screen explains the score too many different ways.
- Needed changes:
  - Keep hero score, 3 key factors, and one next-best action.
  - Move full explanation and history into secondary tabs or drawers.
  - Replace multiple interpretation blocks with one simple `What to do next` module.

#### Credit Readiness

- File: `lib/features/credit/screens/credit_readiness_screen.dart`
- Priority: P1
- Problems:
  - The screen mixes internal preparation logic, profile completeness, applications, and partner handoff.
  - It reads like an operator console more than a user product screen.
- Needed changes:
  - Turn into a simple readiness checklist plus one recommended next step.
  - Move application pipeline history to its own route.
  - Move partner handoff to a separate bank selection flow.
  - Remove internal framing from user-facing copy.

### Partners

#### Partners Hub

- File: `lib/features/partners/screens/partners_screen.dart`
- Priority: P1
- Problems:
  - Tabs, hero cards, feature tiles, welcome sheet, and multiple partner categories create discovery overload.
  - The current design favors feature count over decision clarity.
- Needed changes:
  - Make this a simple category list or search-first directory.
  - Show one hero partner max, then compact list rows.
  - Move feature enumeration into partner detail pages.

#### Bank Partner Detail

- File: `lib/features/partners/screens/bank_partner_screen.dart`
- Priority: P1
- Problems:
  - Heavy information architecture: hero tags, quick actions, category sections, service inventories, support blocks.
  - Reads like a brochure, not a mobile decision screen.
- Needed changes:
  - First view should answer: what is this bank good for, how do I contact them, what can I do next.
  - Collapse service catalogs into accordion categories or separate screens.
  - Reduce hero tags to 2 or 3.
  - Keep one primary contact CTA and one secondary browse CTA.

#### Prisma Partner Detail

- File: `lib/features/partners/screens/prisma_partner_screen.dart`
- Priority: P2
- Problems:
  - Similar brochure problem, amplified by many cards and stats.
- Needed changes:
  - Reduce to hero, core services, credibility proof, and contact.
  - Move values, stats, and long service lists behind drill-down.

#### Radiant Partner Detail

- File: `lib/features/partners/screens/radiant_partner_screen.dart`
- Priority: P2
- Problems:
  - Smaller than Prisma, but still card-heavy for a simple quote/contact journey.
- Needed changes:
  - Lead with what is insured, who it is for, and one `Request a quote` CTA.
  - Collapse supporting info into a single details section.

#### Generic Fans Placeholder

- File: `lib/features/partners/screens/fans_screen.dart`
- Priority: P3
- Problems:
  - Placeholder route is too verbose for a non-live feature.
- Needed changes:
  - Replace with one lightweight compatibility state.
  - Remove explanation bullets.
  - If possible, hide unfinished routes from regular discovery.

### Rayon Sports Module

#### Rayon Home

- File: `lib/features/partners/rayon/screens/rayon_home_screen.dart`
- Priority: P1
- Problems:
  - Hero banner, membership card, recovery card, service grid, and next match stack with equal weight.
  - Too many first-view entry points.
- Needed changes:
  - Keep one hero: membership or club identity, not both equally.
  - Reduce services to the 3 most-used actions.
  - Push next match lower or into a dedicated match section.

#### Fan Profile

- File: `lib/features/partners/rayon/screens/fan_profile_screen.dart`
- Priority: P2
- Problems:
  - Profile hero, stats, benefits, QR, pending cards, and recent orders create a long dense dashboard.
- Needed changes:
  - Keep profile identity, tier progress, QR access, and one supporting list.
  - Move benefits and orders into tabs.
  - Reduce stat count above the fold.

#### Membership Tiers

- File: `lib/features/partners/rayon/screens/membership_tiers_screen.dart`
- Priority: P2
- Problems:
  - Intro, progress, and full tier catalog likely create too much vertical explanation.
- Needed changes:
  - Keep current tier and next tier only.
  - Collapse lower tiers.
  - Use a compact comparison list instead of repeated large cards.

#### Support List

- File: `lib/features/partners/rayon/screens/support_screen.dart`
- Priority: P2
- Problems:
  - Cause discovery and summary stats likely compete.
- Needed changes:
  - Make it a clean list of causes with one compact summary row.
  - Remove non-essential overview metrics from the top.

#### Support Detail

- File: `lib/features/partners/rayon/screens/support_detail_screen.dart`
- Priority: P1
- Problems:
  - Progress, perks, MoMo info, contribution state, supporters, and share tools all appear in one screen.
- Needed changes:
  - First view: cause title, progress, amount selector, pay CTA.
  - Move supporters and share lower or into tabs.
  - Reduce status/detail cards shown at the same time.

#### Fan Clubs List

- File: `lib/features/partners/screens/rayon/fan_clubs_screen.dart`
- Priority: P2
- Problems:
  - Filters, cards, and club creation are likely all visible at once.
- Needed changes:
  - Start with searchable list.
  - Hide create-club under a clear secondary action.
  - Simplify club cards to name, chapter, members, and join state.

#### Fan Club Detail

- File: `lib/features/partners/screens/rayon/fan_club_detail_screen.dart`
- Priority: P2
- Problems:
  - Achievements, stats, members, sharing, and join state create too many equal sections.
- Needed changes:
  - Keep hero, join button, brief stats, and member preview.
  - Move achievements and share into secondary sections.

#### Member Registry

- File: `lib/features/partners/screens/rayon/member_registry_screen.dart`
- Priority: P2
- Problems:
  - Search, filters, spotlight, list, tier legend, and pagination create admin-like density in a consumer module.
- Needed changes:
  - Decide if this is consumer-facing or operational.
  - If consumer-facing, keep search + simple list only.
  - If operational, move to an internal tool surface.

#### Club Shop

- File: `lib/features/partners/screens/rayon/club_shop_screen.dart`
- Priority: P2
- Problems:
  - Product details, category browsing, and merchandising likely compete on one surface.
- Needed changes:
  - Use a simpler commerce pattern: category chips, product cards, product detail.
  - Keep product cards visual and short.
  - Remove long text blocks from the catalog itself.

#### Shop Checkout

- File: `lib/features/partners/screens/rayon/shop_checkout_screen.dart`
- Priority: P1
- Problems:
  - Checkout, status, detail, and retry states appear heavy and text-driven.
- Needed changes:
  - Keep checkout to address, payment, order summary, confirm.
  - Move order status detail to post-purchase.
  - Reduce support/error copy inside the main transaction path.

#### Tickets

- File: `lib/features/partners/screens/rayon/tickets_screen.dart`
- Priority: P1
- Problems:
  - Tickets likely mix event discovery, summaries, and purchase flow too tightly.
- Needed changes:
  - Make it list-first: match, date, venue, price, buy.
  - Move purchase options into a clean bottom sheet.
  - Reduce promotional or explanatory top sections.

#### My Tickets

- File: `lib/features/partners/screens/rayon/my_tickets_screen.dart`
- Priority: P2
- Problems:
  - Multiple sections and league-side context risk cluttering a utility screen.
- Needed changes:
  - Separate upcoming and past tickets with a simple segmented control.
  - Keep standings or unrelated sports context off this screen.

#### Ticket Confirmation

- File: `lib/features/partners/screens/rayon/ticket_confirmation_screen.dart`
- Priority: P2
- Problems:
  - Confirmation screens often carry too much status explanation.
- Needed changes:
  - Keep success state, ticket summary, and next action.
  - Remove secondary explanatory cards.

### Placeholder And Compatibility Surfaces

#### Basket

- File: `lib/features/basket/screens/basket_screen.dart`
- Priority: P3
- Problems:
  - The placeholder is too long and too polished for a route that is not live.
- Needed changes:
  - Replace with one compact message and one CTA.
  - Avoid listing internal reasons the route is incomplete.

### Admin

Admin screens are internal and can tolerate denser data, but they still need cleaner structure.

#### Admin Dashboard

- File: `lib/features/admin/screens/admin_dashboard_screen.dart`
- Priority: P3
- Needed changes:
  - Reduce subtitles.
  - Use a simpler list or larger 2-column tiles with stronger grouping.

#### Manage Users

- File: `lib/features/admin/screens/manage_users_screen.dart`
- Priority: P3
- Needed changes:
  - Move summary chips into a thin header.
  - Simplify user rows and move markers/actions into overflow.

#### Manage Partners

- File: `lib/features/admin/screens/manage_partners_screen.dart`
- Priority: P3
- Needed changes:
  - Reduce visible metadata per partner row.
  - Keep edit/create flows off the main list.

#### Manage Services

- File: `lib/features/admin/screens/manage_services_screen.dart`
- Priority: P3
- Needed changes:
  - Simplify rows to partner, service name, state, and edit affordance.

#### Manage Quick Actions

- File: `lib/features/admin/screens/manage_quick_actions_screen.dart`
- Priority: P3
- Needed changes:
  - Keep reorder mode separate from edit mode.

#### Manage Vehicle Types

- File: `lib/features/admin/screens/manage_vehicle_types_screen.dart`
- Priority: P3
- Needed changes:
  - Use short rows and cleaner empty states.

#### Manage Countries

- File: `lib/features/admin/screens/manage_countries_screen.dart`
- Priority: P3
- Problems:
  - Summary, issues, chips, route metadata, and validation details likely create console-level density.
- Needed changes:
  - Split `Catalog` and `Validation issues` into separate tabs.
  - Reduce chip noise and keep issue severity visually simpler.

#### Manage App Config

- File: `lib/features/admin/screens/manage_app_config_screen.dart`
- Priority: P3
- Needed changes:
  - Keep as a simple searchable key-value list.

## Implementation Plan

### Phase 0: Reduce Global Noise

Target: 3 to 5 days

- Flatten `CoolCard`, `CoolButton`, and `CoolScreenBackground`.
- Remove non-essential emoji from shared UI patterns.
- Set copy rules for headings, helper text, CTA labels, empty states, and errors.
- Audit accent usage and reduce green/purple/orange competition.

Exit criteria:

- Every screen becomes visually quieter before local redesign starts.
- Designers and engineers share one simplification rubric.

### Phase 1: Fix The Core Journeys

Target: 1 to 2 weeks

Screens:

- Splash
- Onboarding
- OTP
- OTP Verify
- Register
- Home
- Profile
- App shell

Work:

- Make entry clean and fast.
- Reduce first-session cognitive load.
- Make Home and Profile feel calm and navigable.

### Phase 2: Simplify Money And Groups

Target: 1 to 2 weeks

Screens:

- MoMo
- MoMo Statements
- Groups
- Create Group
- Group Detail
- Group Invite

Work:

- Convert large dashboards into task-first flows.
- Split long forms.
- Reduce top-level action count and card count.

### Phase 3: Rebuild Mobility As Two Clear Modes

Target: 2 weeks

Screens:

- Mobility Home
- Schedule Trip
- Trip Board
- Driver Profile

Work:

- Separate rider and driver concerns.
- Turn giant single-page forms into steps.
- Reduce local filters and operational controls on discovery screens.

### Phase 4: Reframe Credit As Decision Support

Target: 1 week

Screens:

- Credit Score
- Credit Readiness

Work:

- Reduce explanation density.
- Surface one recommended action at a time.
- Move history and partner handoff into drill-down flows.

### Phase 5: Simplify Partners And Rayon

Target: 2 to 3 weeks

Screens:

- Partners hub
- Bank partner
- Prisma
- Radiant
- Rayon home
- Fan profile
- Membership tiers
- Support
- Support detail
- Fan clubs
- Fan club detail
- Member registry
- Club shop
- Shop checkout
- Tickets
- My tickets
- Ticket confirmation
- Fans placeholder

Work:

- Convert brochure-style pages into mobile task flows.
- Reduce service cards and explanatory sections.
- Separate discovery, detail, and transaction steps.

### Phase 6: Clean Placeholders And Internal Surfaces

Target: 3 to 5 days

Screens:

- Basket
- Admin dashboard
- Manage users
- Manage partners
- Manage services
- Manage quick actions
- Manage vehicle types
- Manage countries
- Manage app config

Work:

- Thin out placeholders.
- Separate admin summaries from record management.
- Remove chip overload and repeated explanations.

## Acceptance Criteria

The redesign should be considered successful only if these are true:

- Every primary screen has one dominant task.
- Above-the-fold copy is short and task-focused.
- Decorative treatments no longer dominate attention.
- Average top-level card count per major screen is materially lower.
- Advanced detail is moved into drill-down.
- Placeholder routes are thin or hidden.
- Users can scan, decide, and act without reading paragraphs.

## Suggested Next Move

Start with Phase 0 plus Phase 1 and do not redesign isolated screens before the shared chrome is simplified.

If implementation begins immediately, the first files to refactor should be:

- `lib/shared/widgets/cool_card.dart`
- `lib/shared/widgets/cool_button.dart`
- `lib/shared/widgets/cool_screen_background.dart`
- `lib/core/router/shell_route.dart`
- `lib/features/home/screens/home_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/momo/screens/momo_screen.dart`
- `lib/features/mobility/screens/mobility_home_screen.dart`
- `lib/features/mobility/screens/schedule_trip_screen.dart`
- `lib/features/credit/screens/credit_score_screen.dart`
