# UI UX System

Use this file when the task is about visual hierarchy, composition, interaction design, accessibility, or module-level UX rules.

## Core Visual System

### Color

Primary system colors come from `AppColors`:

- `bg`, `surface`, `surface2`, `surface3` for layered dark UI
- `text`, `text2`, `text3` for hierarchy
- `accent` for primary action and active state
- `blue`, `orange`, `red`, `yellow` for semantic reinforcement

Rules:

- do not use accent everywhere
- avoid glow-heavy or neon-heavy surfaces by default
- use stronger brand colors only where the partner surface needs it
- never rely on color alone for status

### Typography

- `DM Sans` for interface text
- `DM Mono` for balances, amounts, codes, references, and compact numeric summaries

Rules:

- use tabular-feeling numeric presentation for money
- keep headings brief and decision-oriented
- do not fill screens with explanatory copy when structure can do the work

### Backgrounds

`CoolScreenBackground` is intentionally restrained. Do not add decorative gradients to compensate for information hierarchy problems.

## Composition Rules

### Above-the-fold budget

- one dominant purpose
- one primary CTA
- at most three visually distinct blocks

### Route responsibility

- if the screen mixes browse, configure, transact, and monitor, split it or simplify it
- if a card only routes somewhere else, consider a row or a clearer CTA
- if the same action is reachable from multiple equal-weight blocks, collapse them

### Large-screen caution

The app is portrait-only by product decision. Designs should not assume tablet or landscape-first layouts.

## State Matrix Requirements

Every important screen or flow should define:

- resting
- loading or skeleton
- empty
- partial data
- error
- offline or stale
- permission-blocked
- rollout-disabled
- success

This is especially important for:

- MoMo
- Mobility
- tickets and checkout
- profile access settings
- admin configuration

## Interaction Rules

### Motion

Motion should:

- confirm input
- preserve continuity
- guide the next action
- clarify success or failure

Motion should not:

- trivialize financial risk
- create false confidence
- mask slow data loads

Always support reduced motion.

### Touch

- minimum target size should stay near `44x44 pt` or `48x48 dp`
- one-hand use matters for MoMo and mobility flows
- avoid tiny chips as critical controls

## Trust Design Rules

### Payments

Always show:

- recipient
- route type
- amount
- pending vs confirmed state
- reference where available
- what happens next

Never hide:

- the receiving identity
- whether confirmation is still pending
- draft or manual-review state when it affects ledger meaning

### Maps

Maps are useful only when they genuinely improve trip selection. If a map is unavailable, provide:

- list-first discovery
- route summary
- manual place search
- explicit unavailable copy

### Permissions

Permission design must be truthful:

- explain why access is needed
- show current status
- offer a fallback when the product supports one
- send users to settings only when necessary

## Module-Specific UX Rules

### Home

- quick actions should be compact and obvious
- recent activity must be real
- do not make the home screen a second dashboard for every module

### MoMo

- treat statements as first-class, not buried diagnostics
- `Back` and `Home` affordances must exist on standalone routes
- QR and NFC are secondary to the USSD and ledger truth path

### Groups

- group trust and recipient clarity matter more than decorative community UI
- invite and contribution actions should be easy to discover
- creation should use progressive disclosure

### Mobility

- use steps for trip scheduling
- separate rider and driver concern density
- do not bury the trip board under filters and map chrome

### Partners And Rayon

- brand expression is allowed, but system trust and clarity win
- ticket, checkout, and support flows must reflect payment state plainly
- generic partner discovery and dedicated partner flows should not share the exact same visual weight

### Basket

- checkout should read like a final review, not a second browsing screen
- totals, quantities, and pending-state language must be explicit
- the MoMo handoff should feel like a deliberate next step, not a surprise

### Auth

- reduce copy and friction
- OTP screens must explain what channel is being used
- avoid forcing profile completion after successful verification

### Profile

- one travel-role control, not duplicate role cards
- access settings should be grouped and factual
- account setup belongs in sheets or focused subsections

### Admin

- reduce storytelling
- increase consequence clarity
- use tables, rows, explicit states, and repair actions

## Accessibility Rules

- support dynamic type and wrapping
- give amounts meaningful screen-reader phrasing
- use explicit button labels
- do not rely on placeholder-only fields
- make error copy actionable

## Localization Rules

- English and French are first-order requirements
- account for text expansion
- format money, dates, and phone numbers by locale and country rules
- keep short labels short enough for French expansion

## Composition Anti-Patterns

- multiple dashboards stacked before scroll
- repeated summary pills and duplicate metadata
- giant `Wrap` clusters
- chips plus tabs plus segmented controls on the same screen without a strong reason
- partner marketing chrome on admin or operational views
- empty states that are caused by bad filtering rather than missing data

## Practical Output Structure

When answering a design request, structure the response around:

1. primary user task
2. current clutter or risk
3. what to keep
4. what to remove, merge, or move
5. new above-the-fold anatomy
6. state matrix
7. accessibility and localization notes
8. implementation notes
