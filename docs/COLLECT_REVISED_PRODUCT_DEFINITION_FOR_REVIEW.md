# Collect product definition for review

Status: Draft for owner review. This document describes the Rwanda-only MoMo USSD direction and does not record product, legal, provider, or release approval.

## Scope

Collect serves Rwanda members and groups using whole-RWF MTN MoMo or Airtel Money USSD contributions. The signed-in app, Admin PWA, public website, payment intent APIs, and local cache use the same scope.

## Member journey

1. Sign in with a Rwanda WhatsApp number and complete a six-digit Collect ID and MoMo profile.
2. Create or join a group under the existing access rules.
3. Review the group receiver and RWF amount.
4. Open the provider USSD prompt and authorize with the network provider.
5. See a confirmed contribution only after trusted receipt evidence is allocated and posted.

## Operational controls

The server checks receiver, payer, amount, time window, transaction ID, authorization, and idempotency. Ambiguous evidence remains in Admin review. Historic records are retained under audit obligations but cannot create new payment activity through retired APIs.

## Acceptance still required

Visual parity, accessibility, real device behavior, provider confirmation, migration replay, deployment verification, and store approval require their own evidence.
