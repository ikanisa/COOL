# Design System: COOL Interface System
**Project ID:** Repo-grounded audit (no linked Stitch project ID found locally)
**Audit Basis:** Flutter routes, theme tokens, shared widgets, representative screens, and UI tests

## 1. Visual Theme & Atmosphere
The core COOL interface is a dark-first editorial command surface. It should feel premium, stable, and operational rather than playful or consumer-generic. The mood is closer to a financial control deck than a cheerful wallet app: dense enough to feel capable, but calm enough to communicate trust.

The visual language relies on deep graphite canvases, bright paper-like text, cobalt action color, and large, molded cards with clay-like depth. Typography carries most of the authority. Headlines are oversized, tightly tracked, and heavy. Supporting copy is still unusually weighty, which makes even secondary information feel deliberate.

The Rayon branch is a controlled variant, not a separate design system. It keeps the same structural DNA but swaps the mood from institutional fintech to stadium-premium energy through club blue, gold, and condensed sports typography.

## 2. Color Palette & Roles
- **Midnight Graphite (#111413):** Default dark app background for core consumer and admin routes.
- **Elevated Carbon (#151817):** Main raised scaffold surface for app bars, shells, and elevated containers.
- **Clay Surface (#191C1B):** Standard card body for stacked modules and grouped content.
- **Bright Paper Ink (#F3F5F1):** Primary text on dark surfaces. Used for titles, key metrics, and high-priority labels.
- **Muted Ledger Text (#C3CAC4):** Secondary text for descriptions, metadata, and supporting copy.
- **Quiet Tertiary Ash (#8C948D):** Low-emphasis labels, placeholders, and inactive states.
- **Command Cobalt (#0047AB):** Primary action color. Used for buttons, active navigation, selected chips, and focused emphasis.
- **Deep Command Blue (#003888):** Stronger pressed or concentrated action state.
- **Moss Success (#3A8A5E):** Healthy state, confirmed routes, and positive completion cues.
- **Soft Coral Warning (#FFB59A):** Warnings, cautionary chips, and medium-risk operational states.
- **Rose Risk (#D0727A):** Destructive, high-risk, or high-demand states.
- **Steel Signal (#89AFFF):** Informational accents and analytics-friendly secondary emphasis on dark mode.
- **Stone Mist (#F1F3F0):** Default light-mode app background.
- **Porcelain Panel (#F5F6F4):** Light-mode elevated surface.
- **Paper Card (#E7EBE7):** Light-mode card and grouped container surface.

### Rayon Variant
- **Club Blue (#0047AB):** Primary brand field for Rayon actions and hero emphasis.
- **Club Gold (#C9A84C):** Premium accent for membership, achievements, and matchday highlights.
- **Club White (#F4F6FA):** High-contrast light foreground against saturated Rayon brand blocks.

## 3. Typography Rules
The core type family is **Manrope**. It should always feel firm and editorial.

- **Weight floor:** Do not use weights below `w600`. The interface depends on visually heavy copy.
- **Display hierarchy:** Use oversized headlines with negative tracking for route titles, hero balances, and major section headers.
- **Body hierarchy:** Even body text should feel substantial. Secondary copy can soften in color, but not in overall presence.
- **Data typography:** Use **DM Mono** for IDs, ledger values, codes, and system-style readouts that need a machine-readable feel.
- **Rayon typography:** Use **Barlow** and **Barlow Condensed** for sports-facing hero text, matchday labels, and branded section headers.

### Practical Scale
- **Display Large (56):** Primary tab roots and flagship hero statements.
- **Display Small (40):** Detail heroes and major secondary screens.
- **Headline Medium (30):** Section anchors and strong card headings.
- **Body Medium (17):** Dense but readable explanatory text.
- **Label Large (16):** Buttons, tabs, and compact command labels.

## 4. Component Stylings
### Buttons
Primary buttons are compact, forceful action blocks with restrained corner rounding. They should feel like command controls, not soft consumer pills.

- Shape: subtly rounded rectangular edges, around `6px`
- Fill: solid cobalt with a faint top-left sheen
- Text: bright, heavy, centered, never delicate
- Elevation: soft floating shadow only when interactive

Secondary buttons are quieter, often transparent or low-emphasis, and should preserve the same weight and authority without competing with the main action.

### Cards & Containers
Cards are the main structural device. They should read like molded slabs floating over a dark field.

- Shape: generously rounded corners, typically `24px` to `32px`
- Surface: tonal separation instead of visible divider lines
- Depth: clay-like shadows with a soft top highlight
- Use: command decks, balance modules, analytics sections, grouped forms, and content stacks

### Inputs & Forms
Inputs are filled, padded, and heavy enough to belong to the same system as the cards.

- Shape: softly rounded corners, roughly `14px` to `22px`
- Surface: filled tonal background, not white boxes or high-contrast outlines
- Focus: subtle cobalt edge and slightly brighter surface
- Labels: bold and short, with strong semantic wording

### Navigation
The primary navigation model is a floating glass dock with a central wallet action.

- Bottom nav: blurred glass bar, large radius, low-contrast outline
- Primary jump action: centered floating wallet button
- App bars: quiet, transparent chrome with strong icon affordances and large route titles below

### Sheets & Dialogs
Overlays should feel dense and premium rather than lightweight.

- Surface: frosted overlay panel
- Shape: large top radius for sheets, large card radius for dialogs
- Depth: soft overlay shadow, never harsh black

### Chips, Tabs, and Status
- Tabs and pills should be wide, stable, and clearly selected through fill, not just border treatment.
- Status badges should use semantic surfaces and strong contrast text.
- Operational, financial, analytics, route, and proximity contexts should each feel distinct through surface tinting rather than decorative ornament.

## 5. Layout Principles
The system is mobile-first, but it behaves like an intentional command interface rather than a cramped handset UI.

- **Standard horizontal padding:** `24px`
- **Primary vertical rhythm:** `32px`, `40px`, and `64px`
- **Bottom-safe content clearance:** large enough to respect the floating nav chrome
- **Tablet behavior:** constrain content rather than stretching it edge to edge

Use a stacked flow. Lead with a single commanding heading, a short subhead, then a sequence of modular cards. Avoid thin divider lines wherever possible. Prefer tonal layers, spacing, and grouped surfaces to separate content.

## 6. Brand Variants & Interface Modes
### Core COOL
Use the default Manrope-led editorial system for:
- Home
- Groups
- Mobility
- MoMo
- Profile
- Credit
- Admin

### Rayon Variant
Use the Rayon variant when the screen is explicitly club-branded.

Allowed Rayon overrides:
- Barlow or Barlow Condensed typography
- Blue and gold brand saturation
- Sports-oriented headlines and matchday emphasis

Rayon should still inherit:
- Core spacing scale
- Large rounded card geometry
- Glass navigation language
- Heavy typography philosophy
- Calm motion and premium depth

### Light Mode
Light mode is supported and should feel like the same system translated into paper surfaces, not a separate brand. Keep contrast strong, preserve weight, and avoid pastel drift.

## 7. Stitch Prompting Guardrails
When generating new screens in Stitch for this product:

- Describe the interface as a **premium editorial fintech command surface**.
- Keep the canvas **dark graphite** by default, with **cobalt primary actions** and **paper-bright text**.
- Use **large, molded cards** with generous radius and soft clay depth.
- Keep typography **heavy, compressed, and authoritative**.
- Avoid thin dividers, generic fintech gradients, tiny labels, or playful rounded-everything treatment.
- Prefer **stacked card modules**, **short decisive subheads**, and **one dominant action per section**.
- For Rayon screens, keep the same structural system but switch to **club-blue and gold sports energy** with **Barlow Condensed headlines**.

## 8. Prompting Shortcuts
Use phrases like:

- “dark-first editorial command surface”
- “premium financial operations UI with clay depth”
- “heavy Manrope hierarchy with tight headline tracking”
- “cobalt primary actions on deep graphite surfaces”
- “generously rounded tonal cards instead of bordered boxes”
- “floating glass navigation dock with centered wallet action”
- “Rayon variant with club blue, gold accents, and condensed sports typography”
