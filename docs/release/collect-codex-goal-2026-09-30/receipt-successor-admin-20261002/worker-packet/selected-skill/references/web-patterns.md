# Web reference patterns

For deep UI/UX acceptance, keep authenticated web applications and public websites separate. Use W01–W06 versus S01–S06 in the [operational checklist](operational-checklist.md), alongside shared visual/accessibility tests. The [component contracts](component-contracts.md) cover operational tables and website hero/menu behavior without assigning promotional art the authority of a live desktop session.

The [current state/theme follow-up](state-theme-desktop-followup.md) adds observed website hover/focus/selection, public signed-out SSO forms and five official POS screenshots. Public SSO is not an authenticated dashboard, and POS is a distinct product surface. Use the exact source context when mapping colours and controls.

The [latest desktop access check](state-lifecycle-validation.md) adds Business signed-out QR-expiry and recovery-entry observations. The 24-page AU guide was rechecked and is byte-identical to the existing source; it does not add an authenticated dashboard or table comparator. Use its partial depictions only within their visible scope.

The [6 September Business supplement](source-and-mac-validation.md) adds a photographed dark desktop analytics composition, a cashflow/forecast panel and receipt-processing state artwork from official public pages. These broaden static colour/state references; they do not establish live authenticated interactions or measurable full desktop tables.

## Consumer marketing

Source: [UK homepage](https://www.revolut.com/), desktop/mobile observations on 5 September 2026. No authenticated app was entered.

The inspected hero is photographic, edge-filling and blue. White heading/copy overlays it; a dark pill CTA is the next step. Desktop navigation groups product families with login/signup on the right. Phone layouts change heading wrapping, photograph crop and navigation. The expanded phone menu uses category rows and bottom account-entry actions.

Recreate hierarchy, crop, wrapping, widths and CTA position at the selected viewport. Staged product sections and image/tab states should not become a generic card grid. Use current measured values from [tokens.md](tokens.md) for this page rather than historical uppercase marketing defaults.

## Business and operator applications

Sources: [Business 5](https://www.revolut.com/business/rb5/) and [2025 AU admin guide](https://cdn.revolut.com/pdf/2025_Admin_Setup_Guide_AU.pdf). Promotional images are reference evidence, not proof of live permissions or every interaction.

Business 5 documents bulk operations and personalised widgets. The current homepage's bills illustration depicts a desktop receipt-matching detail beside a document preview, with confirm-match and reimbursement actions; this is a promotional composition, not a full captured session. Its phone photograph shows account balance, Accounts, quick actions and grouped activity. The 2025 AU PDF is principally a workflow guide with promotional illustrations; it does not supply the presumed desktop transaction-table screenshot.

For target implementation, keep stable workspace/account context, section navigation, overview widgets, dense record views and contextual review/detail. Preserve column alignment, table headers, right-aligned values and status hierarchy. Bulk selection needs visible count, scope and actions. These table prescriptions are adaptations, not visually measured Revolut table definitions.

Filters, pagination, selection, sorting and detail-return position should survive ordinary navigation. At smaller sizes use the demonstrated mobile/compact reference or label the adaptation. Do not squeeze all desktop columns into a phone.

The 2025 regional guide does not supply current universal eligibility, limits or product copy.

## Consumer web app

The [public desktop supplement](public-desktop-supplement.md) adds six individually inspected historical previews, including light Passkeys and Privacy settings depictions. The publisher dates the cohort April 2025. Their quiet pale surfaces, white groups and violet/grey switch appearances support only those visible compositions. A grey off-state is not a disabled-state specification; persistence, focus and save/recovery remain unverified. The other previews are two marketing heroes, a missing-page composition and a signed-out login. None establishes a current authenticated dashboard or table.

The signed-out entry was inspected directly on 5 September 2026: empty phone/email alternatives, disabled actions and 88 resolved colour variables are preserved in [current web state evidence](current-web-state-evidence.json). This narrows the gap for public web authentication presentation only. No user data was entered, no login completed and no account dashboard inspected.

[US help](https://help.revolut.com/en-US/help/more/revolut-web-app/what-features-are-supported-on-the-web-app/) documents account/card/transaction viewing, statements and selected security/support actions, including limited-access differences. This establishes feature scope, not exact geometry. Obtain a current capture for exact comparison; marketing imagery is not authenticated UI evidence.

[German Stays help](https://help.revolut.com/en-DE/help/revpoints/stays/question-how-to-book-revolut-stays/) also explicitly describes choosing Stays in the consumer web app's left menu and continuing to the booking website. This is a documented web-to-booking journey, not evidence of the rest of the dashboard layout. See H21 in the [recent source ledger](mobile-sources-20260905.md).

The current [tablet store artwork](current-mobile-atlas.md) shows left navigation rails on overview depictions. It does not establish authenticated desktop web breakpoints, browser history or all tablet interactions. Keep native tablet promotional, consumer web, Business web and PWA comparisons separate.

## Revolut Pay

[Official button guidance](https://developer.revolut.com/docs/resources/revolut-pay-button-guidelines) describes source SDK controls, variants and original marks. This is reference documentation, not a direction to copy a branded button or add a payment provider. Keep the target's actual integration and own product identity; visual matching does not authorise provider/configuration changes. These source rules are integration-specific, not universal button styling.

## Implementation recommendations

- Semantic headings/links/buttons and named icon actions.
- Responsive source images, deliberate crops and live text.
- Source-matched widths and typography, checked at compact/wide viewports.
- Dialog/menu focus containment, restoration and appropriate dismissal.
- Real URLs, deep-link reload, browser history and return-to-list state.
- Stable layout while assets load; reduced-motion alternatives.
- Accessible table headers, amounts and status text.
- Designed error, empty, pending and permission states.

These are target implementation recommendations, not claims about private Revolut code. Read [PWA and accessibility](pwa-and-accessibility.md) for installed behavior.
