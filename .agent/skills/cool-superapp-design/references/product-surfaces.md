# Product Surfaces

Use this file when the task needs a product map of `COOL`, route placement guidance, or module-specific UX goals.

## Product Summary

`COOL` is a Flutter mobile super-app for:

- community savings and fundraising
- Mobile Money USSD payments with Android SMS confirmation
- rider and driver mobility flows
- partner ecosystems, especially Rayon Sports
- credit visibility
- profile, access, and admin operations

The app is Android-first, English and French, and optimized for Rwanda-first behavior while supporting broader Sub-Saharan and adjacent markets.

## Primary User States

- signed out
- OTP requested
- OTP verified, profile incomplete
- active payer
- group member
- rider
- driver
- partner fan or buyer
- admin

## Navigation Model

### Shell

The main shell is:

- `Home`
- `Groups`
- center `MoMo` FAB
- `Mobility`
- `Profile`

This is not a generic tab bar. `MoMo` is a pushed standalone hub, not a shell branch.

### Standalone routes

Treat these as high-focus standalone destinations:

- `MoMo`
- `MoMo Statements`
- `Partners`
- `Credit`
- scanner flows
- admin routes
- Rayon routes

Standalone routes must always expose a visible path back or home.

## Route Placement Guidance

Use this when deciding whether a new surface belongs in the shell or as a pushed flow.

### Belongs in shell

- long-lived destinations users revisit frequently
- high-level launch or monitor surfaces
- routes that benefit from tab persistence

### Belongs as standalone

- transactional flows
- setup flows
- detail routes
- statements, receipts, confirmations
- partner-branded journeys
- scanner and permission-heavy tasks

## Module Map

### Home

Role:

- launchpad
- trust summary
- recent activity
- missions and lightweight prompts

Primary jobs:

- orient the user fast
- expose top actions without crowding
- show truthful recent movement

### Groups

Role:

- savings groups
- group discovery
- invite flows
- contribution entry points

Primary jobs:

- clarify group identity
- show privacy and membership state
- launch contribution or invite actions

### MoMo

Role:

- payment handoff hub
- receive flows
- QR and NFC utilities
- statements and ledger review

Primary jobs:

- generate the right USSD handoff
- reflect payment state honestly
- preserve references, receipts, and ledger visibility

### Mobility

Role:

- rider discovery
- scheduled trip creation
- trip board
- driver operations

Primary jobs:

- find or post trips quickly
- degrade well when live maps are absent
- keep rider and driver tasks understandable

### Partners

Role:

- partner discovery
- partner-specific financial or service flows
- bank and ecosystem detail surfaces

Primary jobs:

- preserve app-level trust and navigation
- allow brand expression without breaking system consistency

### Rayon

Role:

- membership
- clubs
- shop
- support initiatives
- tickets
- profile and registry

Primary jobs:

- make pending vs confirmed status explicit
- keep each commerce or support flow transactional and verifiable
- bridge partner branding with COOL payment and trust rules

### Credit

Role:

- credit score understanding
- readiness improvement
- visibility into prerequisites

Primary jobs:

- explain rather than hype
- convert confusing eligibility into clear next steps

### Basket

Role:

- shared checkout surface
- last-step review for tickets, shop, and other purchasable partner items
- final confirmation before MoMo handoff

Primary jobs:

- show line items and totals clearly
- preserve pending versus confirmed order meaning
- keep checkout concise and reversible before USSD launch

### Auth

Role:

- entry into the app
- WhatsApp OTP verification
- lightweight identity bootstrap

Primary jobs:

- get to first value quickly
- avoid forcing nonessential setup
- preserve trust during OTP and fallback states

### Profile

Role:

- identity
- payout and route setup
- access and permission controls
- travel role
- support and settings

Primary jobs:

- avoid duplicate controls
- present only real capabilities
- keep account state and device state distinct but understandable

### Admin

Role:

- app configuration
- country and MoMo routing setup
- partner and content operations
- validation and repair tools

Primary jobs:

- make operational consequences obvious
- reduce ambiguity in config forms
- keep destructive actions isolated

## Critical User Journeys

### Auth

1. User opens app
2. Onboarding or OTP request
3. OTP verify
4. User lands on `/home`
5. Profile completion remains voluntary, not forced

### Group contribution

1. User opens group
2. Sees recipient and route context
3. Enters amount
4. App launches USSD
5. Android SMS confirmation reconciles later
6. User sees pending or confirmed state

### MoMo direct payment

1. User opens `MoMo`
2. Chooses number or code route
3. Reviews amount and recipient
4. Launches USSD
5. SMS lands on device
6. App ingests and reconciles SMS to Supabase
7. Statements and home activity reflect the result

### Mobility scheduling

1. User opens schedule trip
2. Picks origin and destination
3. Reviews route or fallback summary
4. Posts trip
5. Trip board and driver views reflect new state

### Rayon purchase

1. User selects ticket, shop, or support amount
2. App shows exact MoMo handoff
3. Pending state remains visible until SMS confirmation
4. Confirmation unlocks downstream value such as QR ticket validity

## Surface-Level Design Priorities

### Must feel trustworthy

- MoMo
- statements
- tickets and checkout
- credit
- admin config

### Must feel efficient

- Home
- trip discovery
- quick actions
- profile setup sheets

### Must feel brand-aware but system-consistent

- partner detail
- Rayon home and subflows

## Current Route And Screen Constraints

Use these constraints before proposing large surface changes:

- `55` routes in the current router
- `4` shell branches
- `53` screen files
- several hotspot screens over `1000` LOC

When a request is broad, prefer improving route clarity and module focus before introducing new surfaces.
