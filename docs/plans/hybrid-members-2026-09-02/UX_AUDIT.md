# Collect Admin — hybrid-member workflow audit

Date: 2 September 2026

Surface: authenticated hosted admin, 1280×720 browser capture

Scope: overview, group list, current creation form, member registry, notifications

Method: fresh read-only browser navigation. Saved screenshot bytes were reopened/inspected. No form submitted.

Overall: existing navigation is a useful base, but the new offline-member workflow is not available. Product Design guided the separation of members from app accounts, assisted creation from public sponsorship, and notification health from a blank list.

## Step 1 — Operations overview: needs investigation

![Current overview](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/01-admin-entry.jpg)

Strength: clear Collect operations navigation with Payees, Transactions, Reconciliations and Ledgers.

Finding: the visible page simultaneously shows three items needing attention, an oldest queue item of 23 days, zero open exceptions and 100% evidence health. These may measure different scopes; the screenshot alone does not prove incorrect data. However, this cannot communicate the proposed receipt/SMS queue health clearly. Define each metric and add oldest unsent receipt, uncertain send count and last worker contact.

Visible test-like labels in the production-badged view require source/data classification by an operator; do not delete them based on appearance.

## Step 2 — Groups: usable base, incomplete for assisted onboarding

![Current group list](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/02-groups.jpg)

Strength: public/private state and MoMo receiving route are visible.

Finding: an active group with a missing route is visibly present; the new assisted flow needs draft versus ready-to-accept-payments states. Group origin, member-import status and linked-app versus no-app counts are not visible in this view. Add these as deliberate information, not an extra wall of metrics.

Accessibility risk: icon-only table headings and action controls require labels/tooltips and keyboard testing. Some right-side content extends beyond the captured viewport; test horizontal table navigation and zoom.

## Step 3 — Create group: wrong scope for the requested journey

![Current create group form](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/03-create-group.jpg)

Strength: the form explicitly warns about public sponsorship and immutable receiving-route details.

Finding: it creates a public, active, Collect-sponsored group. It is not the requested private admin-assisted group with manual/uploaded members. Keep this authorized public path and add the separate assisted flow; do not remove the warning while retaining its behavior.

The visible form is long and scrollable, with internal category/purpose fields ahead of receiving/member onboarding. Proposed assisted order: group details → receiving account → members/import → review. Keep a persistent summary and save draft state. The form was cancelled without submission.

## Step 4 — Members: currently app-account centric

![Current member list](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/04-members.jpg)

Strength: personal numbers are masked in the table.

Finding: the subtitle defines members as users with an active group membership; no manual-add/import action is visible. That is consistent with the source's account-dependent member query, not the requested financial-member registry. Separate Users/App Accounts from Members and add explicit app-link/channel state.

Keep MoMo names/full numbers private in authorized detail/review views. Do not use this work to reintroduce names in public/member-facing profiles.

## Step 5 — Notifications: no dispatch readiness evidence

![Current notifications list](/Volumes/PRO-G40/COOL/docs/plans/hybrid-members-2026-09-02/evidence/05-notifications.jpg)

Strength: a dedicated operational notifications destination already exists.

Finding: the empty view only says delivery activity will appear here. It does not distinguish no eligible jobs, no configured SMS worker, a paused sender, unavailable account, a queue error or historical delivery absence. Add channel tabs/filters, worker status, pending age and explicit observed/uncertain outcomes.

## Evidence limits

- The browser's DOM/visible-DOM inspection did not expose the rendered controls beyond “Enable accessibility”; attempting that control did not expose a useful tree. Screenshot-grounded navigation worked. Treat this as a current assistive-access/automation observation requiring remediation and retesting, not a complete accessibility certification.
- No roster import, offline-member creation, payment, allocation correction, send or production write was performed.
- No mobile responsive, screen-reader, full keyboard, contrast measurement or end-to-end user acceptance was completed.
- Source and hosted versions were not proven identical.
- Each proposed change needs fresh rendered verification after implementation; these screenshots are baseline evidence, not proof of a redesigned implementation.
