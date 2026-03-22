# COOL Production Redesign System

Date: 2026-03-20

Scope:
- existing live Flutter app
- phased modernization, not a concept reboot
- one unified system across consumer, operator, admin, wallet, mobility, marketplace, and club/fan surfaces

Primary objective:
- maximize authority without breaking proven product logic

## 1. Executive Position

COOL should feel like a premium digital infrastructure platform, not a startup-style super-app. The redesign keeps the current shell, working flows, and useful feature depth, but replaces weak presentation with a disciplined system that is:

- premium
- executive
- high-trust
- calm
- bold
- institutionally credible
- operationally clear

This system is designed for safe rollout in a production Flutter app. It assumes migration happens family by family, widget by widget, not as a single risky visual rewrite.

## 2. Audit Framing

The current app already has strong product breadth. The weakness is not missing functionality. The weakness is how that functionality is presented.

Confirmed repo signals:
- route responsibility is broad on major hubs such as `home`, `profile`, `mobility`, group detail, and several partner routes
- the current shared theme is directionally restrained, but its semantic token set is too shallow for a full redesign
- typography is inconsistent across the codebase with `Manrope`, `DM Sans`, `Barlow`, and local font overrides
- several widgets still use small chips, small metadata, and lightweight support text
- cards, chips, and secondary tools often receive equal emphasis, which weakens hierarchy and trust
- partner and club surfaces sometimes over-index on branding at the cost of transaction clarity
- admin surfaces need flatter information density with stronger structure, not more decoration

Current hotspot routes and families:
- `lib/features/home/screens/home_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/mobility/screens/mobility_home_screen.dart`
- `lib/features/groups/screens/group_detail_screen.dart`
- `lib/features/groups/screens/create_group_screen.dart`
- `lib/features/partners/rayon/screens/support_detail_screen.dart`
- `lib/features/partners/rayon/screens/tickets_screen.dart`
- `lib/features/partners/rayon/screens/shop_checkout_screen.dart`
- `lib/features/admin/screens/*`

Current weakness patterns to solve systematically:
- inconsistent typography and font-family drift
- weak screen hierarchy
- too many cards before scroll
- too many chips and helper rows competing with primary actions
- weak CTA prominence
- low-trust color behavior
- cluttered dashboard composition
- dense or over-branded transactional screens
- small metadata and faint placeholders
- inconsistent list row density and settings structure
- admin views that are too card-heavy instead of operationally flat

## 3. Non-Negotiables

The redesign must:
- preserve working product logic
- preserve user familiarity where it still helps task completion
- strengthen clarity before adding novelty
- increase trust and scanability on every important screen
- keep implementation realistic for Flutter
- keep both light and dark themes first-class

The redesign must not:
- behave like a Dribbble concept
- introduce decorative complexity
- require a risky navigation rewrite
- use tiny text to fit more content
- rely on faint metadata to create hierarchy
- overuse blur, glow, or saturated gradients
- create one-off branded widgets that do not scale across modules

## 4. Redesign Strategy

### Preserve
- core route shell and mental model
- proven flows for send, pay, schedule, join, buy, contribute, manage
- existing feature breadth across mobility, wallet, groups, admin, and partner modules

### Remove
- duplicate summaries above the fold
- secondary actions sitting beside the main CTA when not essential
- overly small chips, badges, and metadata
- weak placeholder and helper styling
- decorative separators and noisy card stacking
- brand-first chrome on transactional screens

### Simplify
- dashboards into one dominant task plus one supporting summary
- filter systems into segmented controls plus overflow sheets
- form surfaces into larger grouped sections
- settings pages into clearer row clusters
- admin screens into flatter analytical blocks with obvious actions

### Merge
- overlapping chip sets into one controlled filter surface
- summary cards that restate the same data
- share and invite patterns into a single overflow or contextual action family
- route facts, proximity, timing, and trust into one compact header module

### Standardize
- typography
- spacing
- surface depth
- card proportions
- button heights
- list row anatomy
- sheet structure
- status language
- CTA placement

### Differentiate by role without fragmenting the system
- consumer: more premium and emotionally strong
- operator/provider: more immediate and action-first
- admin: flatter, denser, stricter, clearer
- club/fan: more official and identity-led, but still disciplined

## 5. Brand Character

The base visual language is:
- oversized
- heavy
- calm
- minimal
- expensive
- tactile
- disciplined

The emotional read should be:
- "trusted institution"
- "serious operator"
- "premium platform"
- "official system"

## 6. Foundation Tokens

## 6.1 Color System Principles

- one restrained evergreen accent family
- warm premium neutrals in light mode
- rich mineral darks in dark mode
- fewer colors, stronger meaning
- no neon
- no playful oversaturation
- no rainbow dashboards
- semantic states stay muted but decisive

### Light Theme Tokens

| Token | Value | Use |
| --- | --- | --- |
| `app.background` | `#F3F0EA` | app field |
| `app.background.elevated` | `#FCFAF6` | top-level elevated canvas |
| `surface.card` | `#F7F2EA` | default large cards |
| `surface.card.strong` | `#FFFDF9` | high-trust primary cards |
| `surface.glass` | `rgba(255, 252, 247, 0.84)` | overlays, floating bars, filter trays |
| `surface.overlay` | `#FBF8F2` | sheets and modal bodies |
| `text.primary` | `#0B0F0D` | all primary text |
| `text.secondary` | `#465147` | secondary text |
| `text.tertiary` | `#6D776E` | metadata only |
| `accent.primary` | `#2F7252` | primary actions |
| `accent.strong` | `#103322` | pressed and premium emphasis |
| `divider` | `rgba(11, 15, 13, 0.08)` | separators |
| `border.default` | `rgba(11, 15, 13, 0.12)` | quiet border |
| `border.strong` | `rgba(11, 15, 13, 0.18)` | active border |
| `state.success` | `#2F7252` | success |
| `state.warning` | `#A86F26` | warning |
| `state.danger` | `#A24C54` | destructive |
| `state.info` | `#4C6886` | info |
| `state.neutral` | `#737B74` | neutral |
| `surface.financial` | `#EDF4EF` | wallet and balance modules |
| `surface.operational` | `#EEF2F0` | route and logistics panels |
| `surface.analytics` | `#EEF1F5` | charts and analytics panels |
| `surface.team` | `#F1EEF6` | team and performance modules |
| `surface.commerce` | `#F5F0E8` | listings and commerce tiles |
| `surface.route` | `#F1ECE4` | schedule, route, trip surfaces |
| `surface.proximity` | `#E7F0EA` | nearby and live availability |
| `surface.contact` | `#EAF3ED` | contact and WhatsApp CTA support |

### Dark Theme Tokens

| Token | Value | Use |
| --- | --- | --- |
| `app.background` | `#070B09` | app field |
| `app.background.elevated` | `#0D110E` | top-level elevated canvas |
| `surface.card` | `#141A16` | default large cards |
| `surface.card.strong` | `#1B221D` | high-trust primary cards |
| `surface.glass` | `rgba(17, 23, 19, 0.82)` | overlays, floating bars, filter trays |
| `surface.overlay` | `#111713` | sheets and modal bodies |
| `text.primary` | `#F4F1E9` | all primary text |
| `text.secondary` | `#C4CBC2` | secondary text |
| `text.tertiary` | `#909B91` | metadata only |
| `accent.primary` | `#3A8A5E` | primary actions |
| `accent.strong` | `#173726` | pressed and premium emphasis |
| `divider` | `rgba(255, 255, 255, 0.08)` | separators |
| `border.default` | `rgba(255, 255, 255, 0.12)` | quiet border |
| `border.strong` | `rgba(255, 255, 255, 0.20)` | active border |
| `state.success` | `#58A67B` | success |
| `state.warning` | `#D09A4D` | warning |
| `state.danger` | `#D0727A` | destructive |
| `state.info` | `#7E9CBC` | info |
| `state.neutral` | `#98A199` | neutral |
| `surface.financial` | `#0E1712` | wallet and balance modules |
| `surface.operational` | `#0F1814` | route and logistics panels |
| `surface.analytics` | `#101721` | charts and analytics panels |
| `surface.team` | `#151320` | team and performance modules |
| `surface.commerce` | `#1A1713` | listings and commerce tiles |
| `surface.route` | `#121814` | schedule, route, trip surfaces |
| `surface.proximity` | `#0E1813` | nearby and live availability |
| `surface.contact` | `#10201A` | contact and WhatsApp CTA support |

## 6.2 Theme Rules

- dark mode is not an inversion of light mode
- both themes preserve the same component geometry and hierarchy
- dark mode uses richer layer separation, not more color
- light mode uses warmth and structure, not stark white minimalism
- brand identity remains the same across themes

## 6.3 Typography

System font:
- `Manrope` for the full UI system

Allowed exception:
- partner or club wordmarks may use brand assets, but all interface chrome, labels, tables, forms, and CTAs stay on the system font

Typography rule:
- every text category must feel bigger and heavier than standard mobile UI
- no text below `14px` unless technically unavoidable
- no weight below `600` for user-facing UI text

### Core Scale

| Style | Size | Weight | Use |
| --- | --- | --- | --- |
| `heroDisplay` | `56` | `800` | home hero, balance hero, large score |
| `pageDisplay` | `44` | `800` | major route title |
| `pageTitle` | `36` | `800` | screen title |
| `sectionTitle` | `28` | `800` | section anchors |
| `cardTitleXL` | `24` | `800` | hero card heading |
| `cardTitle` | `22` | `800` | standard card heading |
| `bodyXL` | `20` | `700` | main explanatory text |
| `bodyLG` | `18` | `700` | default body |
| `body` | `16` | `700` | compact body |
| `labelLG` | `16` | `800` | button, tabs, nav, chips |
| `label` | `15` | `800` | field label, row title, badge |
| `metaStrong` | `15` | `700` | metadata with importance |
| `meta` | `14` | `700` | smallest allowed system text |
| `dataXL` | `32` | `800` | large metrics |
| `dataLG` | `26` | `800` | balances and totals |
| `data` | `22` | `800` | supporting metrics |

### Category Rules

- hero headings: `44-56`, `800`
- page titles: `36-44`, `800`
- section headers: `28`, `800`
- card titles: `22-24`, `800`
- body text: `16-20`, `700`
- labels: `15-16`, `800`
- chips and badges: `15-16`, `800`
- metadata: `14-15`, `700`
- helper and support text: `14-15`, `700`
- button text: `16`, `800`
- tab and navigation labels: `15-16`, `800`
- input text and placeholder: `16-18`, `700`
- stats, score, balance, and pricing: `22-56`, `800`

Typography anti-patterns to remove:
- `10-12px` chips
- light metadata
- faint placeholders
- small mono timestamps unless essential
- multiple font families in a single route

## 6.4 Spacing Scale

| Token | Value | Use |
| --- | --- | --- |
| `space.1` | `4` | micro gap |
| `space.2` | `8` | tight inline gap |
| `space.3` | `12` | dense content gap |
| `space.4` | `16` | standard inner spacing |
| `space.5` | `20` | comfortable block spacing |
| `space.6` | `24` | default page padding |
| `space.7` | `32` | major section gap |
| `space.8` | `40` | large section separation |
| `space.9` | `48` | hero to content break |
| `space.10` | `64` | screen-ending breathing room |

Layout rule:
- prefer fewer modules with `24-32` spacing over many modules with `8-12`

## 6.5 Corner Radius Scale

| Token | Value | Use |
| --- | --- | --- |
| `radius.sm` | `16` | small chips and inline pills |
| `radius.md` | `22` | buttons and fields |
| `radius.lg` | `28` | compact cards |
| `radius.xl` | `32` | primary cards |
| `radius.2xl` | `36` | sheets and large panels |
| `radius.pill` | `999` | full pills |

## 6.6 Elevation and Shadow System

Elevation rule:
- surfaces should feel substantial, not floating everywhere
- use contrast and scale first, shadow second

Shadow tiers:
- `resting`: almost invisible, mostly border and gradient driven
- `clay`: broad soft shadow plus quiet top highlight
- `floating`: used for sticky CTA bars, nav chrome, and overlay trays
- `overlay`: used for sheets and modals only

## 6.7 Blur and Glass Rules

Blur is reserved for:
- bottom nav shell
- floating filter bars
- modal containers
- elevated bottom sheets

Blur values:
- subtle glass: `12`
- standard glass: `18`
- sheet glass: `22`

Glass rules:
- never place heavy blur behind dense text
- always pair glass with a readable fill tint
- never use glass for primary content cards

## 6.8 Iconography

- bold rounded icons
- `22-24` default interactive icon size
- no ultra-thin icon sets
- use filled or bold-outlined icons consistently per screen family
- primary actions pair icon plus text only when the icon improves scanability

## 6.9 Illustration

- minimal use
- abstract operational cues, not playful mascots
- use diagrams, route dots, trust badges, receipts, shields, tickets, or structured empty states
- no cartoon art

## 6.10 Layout Grid and Responsiveness

Mobile grid:
- single-column default
- `24` horizontal padding on phones
- `32` padding on large phones or compact tablets
- max content width `720`

Responsive rules:
- grow spacing before adding columns
- keep CTA bars pinned and consistent
- preserve large text first, then reflow chips and secondary facts

## 7. Surface Language

### Clay Surfaces

Use for:
- primary cards
- balance modules
- trip cards
- listing cards
- match cards
- analytics panels
- button containers
- segmented controls

Visual behavior:
- soft vertical gradient
- quiet border
- subtle inner highlight
- broad shadow with low contrast
- large radius

### Glass Surfaces

Use for:
- floating nav chrome
- persistent filter bars
- premium modal shells
- bottom sheets
- transient action trays

Visual behavior:
- disciplined blur
- strong readability
- no hard white frost in dark mode
- no heavy transparency on top of detailed content

### Admin Flatness Rule

Admin should be flatter than consumer:
- fewer decorative gradients
- more line structure
- more row logic
- more obvious status and action grouping
- still premium, but more infrastructural than indulgent

## 8. Layout System

Every screen should resolve into five blocks in this order:

1. identity
2. primary action
3. current state
4. supporting context
5. secondary tools

Screen rules:
- one dominant job per route
- one clear primary CTA above the fold
- no more than two high-emphasis cards before first scroll on standard routes
- secondary tools go below fold or into sheets
- list-first thinking beats dashboard thinking for operational clarity

Preferred screen patterns:
- hero + CTA + supporting list
- hero + segmented control + primary list
- hero + facts + bottom action bar
- structured settings rows grouped by intent
- analytics overview + one chart + action rows

## 9. Navigation Patterns

### Bottom Navigation

- floating premium bar
- bold icons and labels
- selected state uses accent and surface lift
- unselected labels remain readable, never faint
- maintain current root shell

### Top App Bars

- transparent or softly blended into background
- strong left-aligned titles
- only keep actions that matter to the route
- avoid more than two trailing actions

### Segmented Controls

- thick pill container
- 52-56 height
- strong selected fill
- only for `2-4` high-value views

### Tabs

- use when the content models are fundamentally different
- avoid using tabs for what should be filters
- keep labels short and bold

### Sheets

- default place for filters, share, invite, advanced settings, and overflow tools
- sheets should be easier to scan than the route they came from

### Back Navigation

- preserve existing logic
- only change when the current route is misleading or overloaded

### Floating Actions

- use sparingly
- reserve for create, contact, or recenter actions that genuinely benefit from persistent access

## 10. Component Library

Every component should exist in a small number of strong variants, not many weak variants.

### Buttons

Families:
- primary
- secondary
- tertiary text
- destructive
- utility compact
- sticky bottom CTA

Rules:
- minimum height `56`
- primary uses evergreen gradient
- secondary uses strong surface and border
- destructive stays serious, not bright red
- label is always bold and large

### Inputs

Families:
- standard text field
- search field
- amount field
- segmented selector
- dropdown row
- date/time field
- multiline notes field

Rules:
- large text
- generous padding
- visible focus state
- helper text remains readable
- placeholder is never faint and never tiny

### Selectors

Families:
- chip group
- pill segmented control
- vehicle selector
- seat selector
- amount selector
- category selector

Rules:
- use few options on-screen
- selected state should be unmistakable
- never rely only on border change

### Cards

Families:
- summary hero card
- data card
- list card
- route/trip card
- listing card
- score card
- team/player card
- membership card
- finance card
- admin metric panel

Rules:
- stronger titles
- fewer nested containers
- route facts, trust cues, and CTA grouped in one block
- avoid stacking card inside card unless operationally necessary

### Status Elements

Families:
- badge
- banner
- inline pill
- progress state row
- verification module
- risk warning panel

Rules:
- status always has icon or shape cue plus label
- use semantic colors sparingly
- warning and risk should be prominent but calm

### List Rows

Families:
- standard action row
- settings row
- transaction row
- member row
- seller row
- route row
- match row

Rules:
- title is large
- subtitle remains readable
- right-side metadata is bold enough to matter
- use divider rhythm instead of extra cards where possible

### Sheets and Modals

Families:
- filter sheet
- quick action sheet
- preview sheet
- confirmation sheet
- destructive confirmation

Rules:
- heavy title
- short copy
- one dominant CTA
- support actions stay secondary

### States

Families:
- loading
- empty
- no results
- verification pending
- success confirmation
- blocked or restricted

Rules:
- state title is forceful and short
- one next step
- avoid apologetic or vague language

## 11. Product-Specific Adaptation

## 11.1 Consumer

- premium surfaces
- stronger hero modules
- emotionally calm but confident
- simplified options above the fold

## 11.2 Operator / Provider

- quick state recognition
- immediate contact and dispatch actions
- stronger row density
- route, proximity, and availability prioritized over storytelling

## 11.3 Admin

- flatter surface system
- more rows and tables, fewer decorative cards
- large headings and strong section dividers
- action clusters pinned near state blocks

## 11.4 Fintech and Wallet

Must emphasize:
- balances
- transaction truth
- payment safety
- verification state
- risk clarity

Component priorities:
- balance hero
- trust summary
- send/request/pay CTAs
- transaction list
- risk or verification banners

## 11.5 Mobility

Must emphasize:
- route
- time
- vehicle
- proximity
- contact
- demand state

Required modules:
- route block
- nearby card
- trip or schedule module
- vehicle selector
- demand and status indicators
- strong call and WhatsApp CTA hierarchy

Mobility screen rule:
- timing, route, proximity, and action handoff must feel immediate

## 11.6 Marketplace

Must emphasize:
- image or seller credibility block
- rank and category filter structure
- price and negotiation clarity
- seller trust
- contact or buy action

Required modules:
- premium listing cards
- seller trust modules
- category filters
- search surfaces
- offer or action cards
- strong buy or contact CTA hierarchy

## 11.7 Football Club and Fan

Must emphasize:
- official identity
- match significance
- score and standings
- membership status
- ticket and follow actions

Required modules:
- match cards
- score modules
- team and player cards
- standings surfaces
- fan membership surfaces
- ticket, join, and follow CTAs

Club rule:
- feel elite and official, not playful or noisy

## 12. Component Combination Patterns

### Home Hub

Above the fold:
- authority header
- one summary hero
- one quick action band
- one recent activity preview

Below the fold:
- seasonal or campaign surfaces
- recommendations
- missions or engagement modules

### Mobility Discovery

Above the fold:
- route/search intent
- nearby and live status module
- primary schedule or contact CTA

Then:
- map or route preview
- sorted results list
- overflow filters in sheet

### Listing Discovery

Above the fold:
- search field
- category filter bar
- ranking or trust cue

Then:
- strong listing cards
- persistent contact or buy patterns

### Match and Ticketing

Above the fold:
- match identity card
- timing and venue facts
- ticket or follow CTA

Then:
- seat or tier selector
- membership benefits
- related club modules

### Admin Workspace

Above the fold:
- workspace title
- current state summary
- one action rail

Then:
- metrics
- queues
- task tables
- deeper config sections

## 13. Copy Style

Tone:
- short
- bold
- confident
- useful
- friction-light
- serious but human

Rules:
- prefer verbs
- prefer nouns users recognize immediately
- avoid cleverness
- avoid layered helper paragraphs
- avoid startup marketing tone
- avoid weak phrases such as "you may want to"

Examples:
- `Send money`
- `Contact seller`
- `Schedule trip`
- `Verify identity`
- `Upgrade plan`
- `Buy ticket`
- `Follow club`

## 14. Motion System

Principles:
- calm
- smooth
- deliberate
- premium

Allowed motion:
- soft fade
- subtle vertical rise
- light scale compression on press
- elegant sheet movement
- smooth list entry for low-count modules

Not allowed:
- bounce
- springy toy-like motion
- exaggerated overshoot
- constant ambient animation

Standard timing:
- press: `100-120ms`
- element enter: `180-220ms`
- sheet open: `260-320ms`
- route transition: `240-320ms`

## 15. Accessibility and Usability

Baseline rules:
- tap targets `>= 48`, preferred `56`
- body text `>= 16`
- metadata `>= 14`
- contrast must remain strong in both themes
- state changes must have text, not only color
- forms must support large text without losing action visibility
- lists must scan in one glance

Accessibility rule:
- premium does not mean subtle
- premium means obvious, stable, and readable

## 16. Theme Switching Guidance

Support:
- system theme
- manual light selection
- manual dark selection

Rules:
- switching theme must preserve component proportions and hierarchy
- light and dark use identical spacing and typography scales
- no special one-off dark mode widgets
- persistent state like selected tabs and chips keeps meaning in both themes

## 17. Flutter Readiness

Implementation model:
- keep the current app shell and route structure
- migrate shared tokens first
- migrate primitives second
- migrate screen families third

Technical expectations:
- token-driven
- widget-friendly
- no fragile custom render work
- moderate gradients
- low-cost blur usage
- reusable shared widgets

Theme entry points:
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/app_theme_components.dart`
- `lib/core/theme/app_theme_text.dart`
- `lib/core/theme/cool_palette.dart`
- `lib/core/theme/cool_foundations.dart`

Migration target primitives:
- `lib/shared/widgets/cool_card.dart`
- `lib/shared/widgets/cool_glass_card.dart`
- `lib/shared/widgets/cool_button.dart`
- `lib/shared/widgets/cool_text_field.dart`
- `lib/shared/widgets/tab_pill.dart`
- `lib/shared/widgets/cool_screen_background.dart`
- `lib/shared/widgets/cool_screen_scaffold.dart`

## 18. Screen Standardization Rules

### What becomes reusable

- action bars
- summary hero cards
- route/trip cards
- listing cards
- trust modules
- settings rows
- seller/provider rows
- score and stat modules
- admin metric panels
- filter trays
- sticky CTA bars

### What becomes flatter in admin

- stacked cards that only separate minor sections
- decorative gradients on operational data
- oversized visual branding inside management routes

### What becomes more premium in consumer

- home hero
- wallet hero
- listing cards
- ticket and membership modules
- profile identity summary

### What becomes clearer in forms

- larger labels
- fewer fields per visible step
- visible grouping
- strong validation language
- strong next-step CTA

### What becomes stronger in navigation

- bottom nav label size and clarity
- top-level route identity
- segmented views instead of many chips
- overflow sheets for secondary tools

### What becomes more authoritative in typography

- all labels
- all metadata
- nav labels
- button labels
- balance and stat displays
- settings rows
- admin operational text

## 19. Migration Plan

### Phase 1: Audit and Token Lock

- inventory legacy font overrides
- inventory direct color usage outside theme
- inventory duplicate card and button patterns
- lock the redesign tokens before visual rollout

### Phase 2: Shared Primitive Upgrade

- upgrade theme tokens
- add semantic surfaces and motion tokens
- refactor `CoolCard`, `CoolButton`, `CoolTextField`, `TabPill`, and sheet containers

### Phase 3: High-Impact Screens

Priority order:
- home
- mobility home and trip discovery
- wallet hub and statements
- profile
- group detail and create group
- club ticketing and support checkout

### Phase 4: Role Families

- consumer family
- operator/provider family
- admin family
- club/fan family

### Phase 5: Cleanup

- remove old color and text overrides
- delete dead one-off widgets
- converge feature modules onto shared row, card, and CTA families

## 20. Rollout Safety Rules

- redesign screen families, not isolated screens
- use feature flags for high-risk route changes
- keep existing navigation entry points where possible
- preserve transactional terminology
- ship changes in visually obvious but behaviorally stable increments
- measure tap success, completion, and support friction after each phase

## 21. Success Criteria

The redesign is successful when the app feels:
- premium instead of cheap
- disciplined instead of patched together
- clear instead of crowded
- authoritative instead of generic
- trustworthy instead of uncertain
- executive instead of casual

The redesign fails if:
- typography becomes smaller to fit clutter
- dark mode looks like a gamer skin
- admin becomes decorative
- branding overrides clarity
- users lose their route mental model

## 22. Immediate Implementation Priorities

Start here:
1. lock typography and semantic tokens
2. strengthen shared card, button, field, sheet, and nav primitives
3. redesign home, mobility, wallet, and profile as the first coherent family
4. redesign trip cards, listing cards, match cards, settings rows, and admin metric panels as reusable modules
5. roll the system through partner and club flows only after the base primitives are stable

This is the authoritative system for the next modernization phase of the app.
