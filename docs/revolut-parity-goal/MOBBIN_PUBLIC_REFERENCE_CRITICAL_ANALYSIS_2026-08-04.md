# Collect customer UI cleanup and public-reference analysis

Date: 2026-08-04
Scope: Collect Flutter customer app, 35 routed surfaces, 17 material states, and the interactive contribution prototype

## Executive conclusion

The old Collect visual layer was not a single screen defect. It was embedded in shared background, card, bottom-sheet, navigation, input, header, loading, and status primitives. That shared layer has now been replaced across the customer app.

The two supplied screenshots are specifically closed:

- the boxed WhatsApp panel, green WhatsApp ornament, custom `RW` badge, nested phone field, and panel-wrapped action are gone;
- the boxed masked-phone anchor and small OTP panel are gone;
- phone entry now uses the same large, direct selector-and-field composition as the observed Revolut onboarding reference;
- number confirmation is an explicit dark sheet with one white primary action and one quiet secondary action;
- OTP now uses the observed six large fields, midpoint separator, automatic focus, autofill, and obscured completed digits;
- invalid authentication content remains readable and is returned to the top of the screen after keyboard dismissal.

The cleanup is structural, not a repaint. Route-specific gradients, blur-backed cards, floating navigation capsules, selected-icon pills, decorative glows, broad shadows, and nested glass panels were removed from the shared customer primitives. All 35 routes now resolve through the cleaned layer.

This is not a claim of complete Revolut product parity. Collect remains an SMS-verified group-contribution product using MoMo, with different trust and state requirements.

## Evidence and access boundary

### Visually observed

- The local 24-screen Revolut iOS onboarding set in `/Users/jeanbosco/Downloads/Revolut iOS Onboarding` was inspected screen by screen. It includes the launch/marketing sequence, country picker, phone entry, number confirmation, OTP empty/complete, incorrect-code sheet, notification choice, residence, name, and identity screens.
- The public Mobbin Revolut app page and its visible taxonomy were inspected. The public page reports 159 iOS flows, but most non-onboarding screen imagery is blurred or plan-gated.
- Public product pages from Revolut, Monzo, Splitwise, and AppFuel were inspected for unblurred interaction patterns and product-state language.

### Metadata only

The following Mobbin counts were visible as flow metadata and must not be treated as visual inspection of every screen:

| Mobbin flow | Visible count | Evidence level |
|---|---:|---|
| User onboarding | 24 screens | Visually observed from the retained local set |
| Sending money to a bank account | 12 screens | Metadata only |
| New payment | 3 screens | Metadata only |
| Searching Revolut in Payments | 6 screens | Metadata only |
| QR code | 3 screens | Metadata only |

No blur, paywall, authentication boundary, or access control was bypassed. Blurred previews were used only to understand taxonomy and screen counts; implementation decisions use the retained unblurred onboarding set, official public pages, and Collect's own product requirements.

## Public sources used

- [Mobbin: Revolut iOS flows](https://mobbin.com/apps/revolut-ios-28b2d970-a05d-4509-99dd-83d47dbc3a16/aa23fa4c-2ecb-4027-b126-335f9fcd86b1/flows)
- [AppFuel: Revolut onboarding](https://theappfuel.com/examples/revolut_onboarding)
- [Revolut Help: Group Bills](https://help.revolut.com/en-US/help/transfers/internal-transfers/groups/)
- [Revolut: money transfer app](https://www.revolut.com/en-US/money-transfer/money-transfer-app/)
- [Revolut: send and receive money](https://www.revolut.com/send-and-receive/)
- [Revolut Help: splitting a bill](https://help.revolut.com/help/adding-money/with-money-from-friends-or-relatives/splitting-bill/?lang=en)
- [Monzo Split](https://monzo.com/features/monzo-split)
- [Splitwise](https://www.splitwise.com/)
- [Splitwise getting-started guide](https://kb.splitwise.com/getting-started/how-do-i-use-splitwise)

## Shared legacy chrome removed

| Legacy layer | Previous effect | Current implementation |
|---|---|---|
| Route-specific screen gradients | Different visual worlds by route | One stable account gradient across customer routes |
| `BackdropFilter` card and sheet blur | Foggy nested glass and expensive rendering | Solid readable surfaces with explicit hierarchy |
| Glass borders and broad shadows | Every object appeared framed or floating | Borders reserved for focus, outline actions, and compact controls; card shadows removed |
| Floating gradient bottom navigation | A legacy Collect capsule floated above content | Edge-to-edge black navigation with a fine top divider |
| Selected navigation pill | Active icons sat in another capsule | Active state is communicated by icon/text treatment |
| Route background scope | Components depended on path-specific chrome | Shared tokens no longer read route paths |
| Decorative hero/glow artwork | Generic fintech decoration competed with task content | Functional icon, title, state, and action hierarchy |
| Boxed authentication panel | WhatsApp ornament and multiple nested containers | Direct phone, confirmation, and OTP steps |
| Custom `RW` micro-badge | Small proprietary badge with weak recognition | Standard globe/country affordance plus calling code |
| Blur-backed modal shell | Sheets visually mixed with underlying content | Solid dark sheets and explicit actions |

The old `collect_shadows.dart` layer was deleted because it no longer participates in the customer design system.

## Screen-by-screen critical review

### 1. Phone entry

Observed reference: large top-aligned title, concise explanatory line, two large input surfaces, country/calling-code selector, large bottom primary button, and no containing panel.

Implemented:

- removed the WhatsApp heading and decorative WhatsApp icon;
- removed the outer card and custom `RW` badge;
- enlarged the selector and phone field;
- retained WhatsApp in explanatory copy because it is the actual Collect delivery channel;
- made the primary action a full-width stadium button and disabled state visibly quiet.

Judgement: direct analogue; high-confidence borrow.

### 2. Country selection

Observed reference: dark solid bottom sheet, search first, flag/calling-code/name rows, generous vertical targets.

Implemented: dark solid picker, safe-area handling, search field, favorite Rwanda entry, calling codes, and large row typography.

Judgement: direct analogue; retained package behavior where it improves localization and accessibility.

### 3. Number confirmation

Observed reference: dimmed phone screen with a focused confirmation card/sheet, full number, short explanation, white primary button, gray secondary action.

Implemented: dedicated solid bottom sheet, unmasked normalized number, “Confirm and send”, and “Edit number”. The sheet appears before any OTP request.

Judgement: direct analogue and a material trust improvement.

### 4. OTP entry

Observed reference: “6-digit code”, masked destination, six large cells split 3–3, automatic keyboard focus, dots after entry, resend recovery.

Implemented: six large cells, midpoint separator, autofill hints, autofocus, numeric keyboard, obscured digits, resend/change-number recovery, submission progress, and reviewer-mode copy where applicable.

Judgement: direct analogue. The six cells are intentionally retained because they are present in the observed Revolut reference; the removed defect was the extra containing panel and phone anchor.

### 5. Invalid or expired OTP

Observed reference: focused error treatment, plain language, and one recovery action.

Implemented: semantic error notice, safe red/orange state color, fresh-code instruction, keyboard dismissal, and scroll reset so the title and error remain visible.

Remaining opportunity: a one-action error sheet would be even closer to the observed reference, but the current inline treatment preserves rapid correction and automated accessibility behavior.

### 6. Home

Borrowed pattern: total-first hierarchy, four compact task actions, recent activity, and owned groups. Removed route-specific background chrome and floating navigation.

Collect-specific adaptation: “Total collected” is not a bank balance. It remains explicitly labelled to prevent false account-balance semantics.

### 7. Groups and group detail

Borrowed pattern: compact rows, icon-led group identity, amount at the trailing edge, direct group actions, and activity immediately below the group total.

Removed: gradient group cards, ornamental footers, card shadows, and route-only chrome.

Remaining opportunity: add a visible five-step creation progress indicator and a member contribution-status timeline.

### 8. Contribution group picker and amount entry

Borrowed pattern: search/picker before amount, amount as primary visual object, quick amounts, clear pay-with summary, fee/total disclosure, and one dominant bottom action.

Collect-specific adaptation: MoMo receiver and PIN safety text remain mandatory. Collect must not imitate bank-card or internal-transfer mechanics that it does not perform.

### 9. Contribution review

Borrowed pattern: large amount, compact receiver/payment facts, inline edit, and one final action.

Implemented addition: “What happens next” explains that Collect opens the official MoMo prompt and updates the ledger only after payment confirmation.

Judgement: high-priority trust screen; never collapse this into optimistic success.

### 10. Success and pending states

Borrowed pattern: one clear state symbol, amount, reference, recorded time, and a single completion action.

Collect-specific requirement: success is only shown after the fixture or live verification path reports confirmation. A created intent is not labelled paid.

Remaining opportunity: expose a reusable pending → confirmed → needs-review timeline.

### 11. Activity and ledger

Borrowed pattern: readable financial rows, amount aligned to the right, state icon, search/filter access, and totals outside the list container.

Removed: dense blur, floating search docks, broad shadows, and decorative background layers.

Remaining opportunity: add a transaction-detail route or sheet with status, reference, timestamp, group, receiver mask, and dispute/help action.

### 12. Share, invite, join, and QR

Borrowed pattern: QR as a first-class action, compact share preview, and safe deep-link recovery.

Collect-specific requirement: group identity and receiver information remain bounded; expired and invalid links retain explicit recovery states.

Remaining opportunity: add a join preview with recent safe groups only when the backend can provide verified data.

### 13. Settings and profile

Borrowed pattern: compact list clusters, direct navigation, plain top chrome, and small appearance choices.

Removed: gradient settings clusters, decorative hero panels, shadowed control groups, and floating subpage buttons.

The appearance preview now uses the same solid chrome rather than preserving the retired glass/border layer.

### 14. Offline, sync, missing, and deletion states

Borrowed pattern: one state headline, one explanation, one dominant recovery action, and explicit data availability.

Collect-specific requirement: saved/read-only status, privacy language, and auditable deletion confirmation remain. These do not have a safe direct Revolut analogue and should not be forced into one.

## What should be borrowed next

### P1

1. Transaction-detail route or sheet for Activity and Ledger.
2. Visible `1 of 5` progress in group creation.
3. Reusable payment-status timeline: pending, confirmed, needs review, expired.
4. Permission-aware reminder action from member status, without requesting broader device access.

### P2

1. Activity filter chips only if backend query semantics support them.
2. Safe QR join preview and recent verified groups.
3. Group history timeline for membership and collection events.

## What should not be copied

- Revolut branding, trademarks, proprietary illustration, marketing copy, or product assets.
- KYC, investment, crypto, plan-upsell, Revtag, or bank-account flows that Collect does not offer.
- Card/internal-transfer mechanics that conflict with Collect’s MoMo and SMS-verification model.
- Optimistic paid/success states before provider/SMS verification.
- Raw phone, receiver, SMS, OTP, credential, or production customer data in retained evidence.
- Blurred or gated imagery reconstructed as if it had been directly observed.

## Validation completed

- `flutter analyze`: passed with no issues.
- Full Flutter suite: 449/449 tests passed on the current source after the final scroll-position guard; the repository's wider release-completion gate remains fail-closed.
- Golden QA: 13 app baselines and 6 prototype states repinned and retested.
- iPhone 17 simulator, iOS 26.5, fixture-only material-state matrix: 17/17 states passed with 17 unique screenshots.
- iPhone 17 simulator, iOS 26.5, fixture-only route matrix: 35/35 routes passed with 35 screenshots and 27 distinct visual states.
- Live web prototype rebuilt and visually inspected at mobile width.

The simulator runs prove current-source fixture rendering on the named simulator. They do not prove physical-device behavior, live Supabase/MoMo/SMS behavior, production deployment, store acceptance, or release approval.

## Final assessment

The requested legacy-chrome cleanup is implemented across the customer design system and all routed customer surfaces. The attached WhatsApp and OTP examples no longer exist in their legacy form. Remaining items are product-capability and workflow-depth improvements, not remnants of the retired glass/floating Collect chrome.
