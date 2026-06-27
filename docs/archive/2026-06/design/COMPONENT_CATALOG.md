# Collect Component Catalog

## Core Components

- `CollectButton`: primary, secondary, subtle, danger, and icon-supported commands with at least 48 px mobile targets.
- `CollectCard`: base glass surface with tokenized padding, radius, border, blur, and shadow.
- `CollectVisualFeatureCard`: shared generated-asset product surface for group, contribution, payment, and other rich first-viewport moments.
- `MoneyHeroCard`, `MoneyCard`, and `AmountHero`: amount-first surfaces for raised, pending, and review metrics.
- `CollectStatusChip`: icon and label status for neutral, success, warning, danger, info, and privacy.
- `CollectAvatar`: safe identity presentation without exposing raw phone/MOMO.
- `CollectListTile`, `ActivityFeedItem`, and `FinancialListRow`: scan-friendly activity, ledger, and navigation rows.
- `SectionHeader`: consistent title/action layout.
- `ScreenHeader`: shared dark finance-grade secondary-route header with official `CollectBrandMark`, high-contrast title text, and action capsules.
- `CollectEmptyState`, `CollectErrorState`, `LoadingSkeleton`, and `LoadingStatePanel`: reusable state surfaces with semantic loading context.
- `CollectBottomSheet` and `BottomActionSurface`: 28-radius action surfaces for modal and sticky mobile workflows.
- `SearchWithClearField` and `PremiumSegmentedFilter`: mobile filtering and search.
- `QuickActionRail` and `QuickActionButton`: compact screen-level action shortcuts.
- Home visual story rail: Collect-owned generated product visuals for MoMo signal, group momentum, and QR/share surfaces.
- Home Momentum feed: data-backed generated-media cards for public group progress, supporter count, share/payment context, and privacy-safe semantics.
- `InfoSecurityBanner`: privacy, safety, and product-boundary messaging.
- `PaymentIntentStatusCard`: pending intent status after MoMo dialer launch.
- `QRCard`: safe share link display.
- `LedgerRow`: confirmed and review payment rows.
- `ReceiverConsentCard`: Android SMS app-access consent, flags, and sync state.
- Admin page header panel and admin data table: compact operations surfaces with rounded borders, dense rows, status chips, and responsive pagination.

## Visual Evidence Utilities

- `scripts/collect_visual_evidence_capture.sh`: creates the Revolut reference, Collect mobile route, and Admin PWA contact sheets from available evidence by default; use `COLLECT_VISUAL_EVIDENCE_FRESH=1` only when the local Flutter screenshot runtime is stable.
- `scripts/android_route_visual_evidence.sh`: runs the physical Android route matrix, saves route PNG screenshots, writes a summary, and generates a Collect mobile route contact sheet.
- `scripts/generate_visual_evidence_contact_sheets.py`: PIL-based contact sheet generator for reference and implementation evidence.

## Debug Catalog

The debug-only route `/dev/design-system` displays representative tokens, typography, components, status states, money rows, payment-intent status, SMS access consent, and admin cards.
