# Design System: COOL Interface System (Mobi × Rayon)
**Project ID:** Repo-grounded audit
**Audit Basis:** Flutter routes, theme tokens, shared widgets, representative screens, and UI tests

## 1. Visual Theme & Atmosphere
The core COOL interface is a **strictly dark-mode** editorial command surface. It feels premium, stable, and operational. The mood is a financial control deck—dense enough to feel capable, calm enough to communicate trust. **Light mode is officially depreciated and unsupported.** 

The visual language relies on deep graphite canvases (`CoolScreenBackground`), bright paper-like text, cobalt action colors, and large, molded cards with extreme clay-like depth and heavy blur. Typography carries authority: headlines are oversized and heavy. Soft Liquid Glass semantics govern overlays and floating elements.

## 2. Color Palette & Roles (Dark Only)
- **Midnight Graphite (#111413):** Default dark app background for core consumer and admin routes.
- **Elevated Carbon (#151817):** Main raised scaffold surface for shells.
- **Clay Surface (#191C1B):** Standard card body for stacked modules.
- **Bright Paper Ink (#F3F5F1):** Primary text for titles, key metrics, and high-priority labels.
- **Muted Ledger Text (#C3CAC4):** Secondary text.
- **Quiet Tertiary Ash (#8C948D):** Low-emphasis labels and inactive states.
- **Command Cobalt (#0047AB) / Club Blue:** Primary action color (buttons, active navigation).
- **Club Gold (#C9A84C):** Premium accent for memberships, achievements, and partners.
- **Moss Success (#3A8A5E):** Healthy state / confirmed routes.
- **Soft Coral Warning (#FFB59A):** Warnings and medium-risk operational states.
- **Rose Risk (#D0727A):** Destructive or error states.

## 3. Typography Rules
**Manrope** is the core family. It must feel firm and editorial.
- **Weight floor:** Do not use weights below `w600`.
- **4-Word Copy Limit:** Promotional headers and secondary CTAs must be ruthlessly trimmed. Ex: "Manage Your Cards Here" -> "Manage Cards".
- **Data typography:** Use **DM Mono** for IDs, ledger values, and readouts.
- **Rayon variant:** Use **Barlow** and **Barlow Condensed** for sports-facing hero text and matchday labels.

## 4. Component Stylings
### Backgrounds
- Every screen must be wrapped in `CoolScreenBackground(child: ...)`. Raw `Scaffold` background colors are strictly forbidden. 

### Cards & Containers
- Shape: Generously rounded corners (`24px` to `32px`).
- Depth: Clay-like shadows with a soft top highlight (`CoolShadows.clay()`).
- Responsive: Avoid fixed `height` values (e.g., `height: 240`). Use `BoxConstraints` and `MediaQuery`.

### Navigation
- **3-Item Floating Glass Nav:** Mandated across the shell (`Home`, center `MoMo` FAB, `Profile`). The legacy 5-item bar is deprecated.
- Uses `CoolFloatingNav` Wrapper. It automatically handles branch-switching via `StatefulNavigationShell`.

### Overlays & Animation
- Overlays must use Heavy Blur (`CoolBlur.heavy`).
- Use native `FadeTransition` and `ScaleTransition` for press feedback. **Do not use `Opacity` or `AnimatedBuilder`** as they incur severe GPU rebuild costs.

## 5. Async State Management
- **`CoolAsyncView<T>`:** Mandatory for all data-dependent panels, Riverpod streams, and API resolves. Raw `.when()` with `LinearProgressIndicator` is banned.
- **`CoolSkeletonList`:** Provide deterministic shape-preserving loaders.
- **`CoolErrorView`:** Catch all network anomalies without crashing the widget tree.

## 6. Layout Principles
The system is mobile-first, operating like a strict command interface:
- **Standard horizontal padding:** `24px`
- **Primary vertical rhythm:** `32px`, `40px`
- **Bottom-safe content clearance:** Must clear the floating nav.

## 7. Stitch Prompting Guardrails
When generating new screens:
- Describe the interface as a **dark-only premium editorial fintech command surface**.
- Keep the canvas **dark graphite** using `CoolScreenBackground`.
- Use **large, molded cards** with generous radius and soft clay depth.
- Keep typography **heavy, compressed, and authoritative**. Apply the **4-word limit** to all actionable headers.
- Always implement loading and error states using `CoolAsyncView` and `CoolErrorView`.
- Use **Soft Liquid Glass** for all bottom navs and floating sheets.
