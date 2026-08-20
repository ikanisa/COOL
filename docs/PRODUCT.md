# Collect Product Source Of Truth

Status: Current working product definition
Last reviewed: 2026-08-15

Collect is a Flutter and Supabase platform for SMS-first MoMo group
contributions. Members create payment intents in the app and complete payment
through MoMo off app. Official MoMo SMS is ingested and parsed as candidate
evidence; only an independently authenticated provider-finality event can post
the immutable ledger entries and change payer/group balances.

## Core Rules

- Identity is Collect ID-first. Member-facing flows do not require real names.
- The app is non-custodial for the Rwanda MoMo workflow. The group owner
  receives MoMo payments directly.
- Group creation is Android-only because owner-side SMS access is required for
  automated contribution capture.
- iPhone users can join and contribute but cannot create groups. The blocked
  create message is exactly `group creation is available only on Android`.
- Contributors do not paste SMS, report transaction IDs, or manually confirm
  payments.
- SMS, parser output, the native app, browsers, group owners, and admins cannot
  mint provider finality or post balances.
- Raw SMS, full phone numbers, MoMo numbers, PINs, OTPs, service-role keys,
  provider tokens, and production customer data must not appear in member
  surfaces or public evidence.

## Core Workflow

1. User signs in with WhatsApp OTP and receives a 6-digit Collect ID.
2. User stores a MoMo number in profile/settings.
3. Android group creator creates a group; the receiver MoMo is derived from the
   creator's confirmed profile. Receiver changes are owner-only,
   profile-derived, atomic, audited, and blocked while protected intents exist.
4. Members join through link, QR code, chat app, SMS, or deep link.
5. Contributor taps `Contribute`, enters amount, and Supabase creates a pending
   payment intent linked to group, amount, receiver MoMo, user id, and Collect
   ID.
6. The app opens the MoMo dialer through `tel:`.
7. Official MoMo SMS is uploaded, parsed, and matched to the pending intent as
   an awaiting-provider-confirmation candidate with no ledger impact.
8. A trusted provider/bank connector validates settlement and sends a signed,
   replay-safe confirmation or rejection. Confirmation posts exactly one group
   credit and one member credit; rejection posts none.

## Category And Diaspora Scope

The simplified SMS-first product originally removed categories, targets, cover
images, public-directory behavior, and campaign-style contribution context.

On 2026-06-21, owner direction approved reintroducing first-class collection
categories and a Stripe-powered diaspora rail as an explicitly governed product
expansion. That approval does not weaken the core privacy and non-custodial
rules above.

Current wording for implementation and QA:

- Category-specific collection context is allowed only where it is explicitly
  implemented and approval-gated.
- Rwanda MoMo remains the default payment workflow.
- Stripe diaspora rails must stay sandbox/governance-gated until legal,
  provider, privacy, Data safety, and release-owner approval is recorded.
- Do not add public directory, public campaign claims, credit approval,
  insurance coverage, regulated-status claims, or provider/compliance claims
  without explicit recorded approval.

## Admin Boundary

The Admin PWA is an operational monitoring and control surface. It monitors
groups, members, payment intents, MoMo SMS rows, parser output, allocation and
provider-finality status, ledger entries, receivers, audit logs, settings, and
exceptions.

Client-side admin guards are convenience only. Supabase RLS, security-definer
RPCs, role tables, and audit logs enforce authorization.

## Related Files

- `README.md`: route and command overview.
- `docs/COLLECT_REVISED_PRODUCT_DEFINITION_FOR_REVIEW.md`: historical product
  definition record and detailed journey notes.
- `docs/PRODUCT.md`:
  detailed expansion goal and governance constraints.
- `docs/release/RELEASE_STATUS.md`: current release/governance status.
