# Collect product contract: Rwanda MoMo USSD

Collect lets signed-in users organize private groups. Its current in-app payment path supports Rwanda contributions in RWF through MTN MoMo or Airtel Money USSD. Collect is a technology and record-keeping service; it does not operate a wallet, hold deposits, or receive a member's MoMo PIN or payment provider OTP. A Collect sign-in code is used only to sign in to Collect.

## Member identity and groups

- Group metadata and membership use the current signed-in Collect app principal. They do not require a phone, country/currency setup, MoMo registration or receiving registry. A complete Rwanda MoMo payment profile has country `RW`, currency `RWF`, a six-digit Collect ID, and a valid Rwanda MoMo provider and number.
- Any signed-in Collect app user may create private group metadata or accept a group invitation. Metadata creation is independent of Android SMS capture, SMS consent and device attestation. Public groups remain platform sponsored; creating or joining a group does not authorize a payment or post a contribution.
- A group may exist without a payment destination. When a Rwanda MoMo payment route is configured, the app shows the exact payee and whole-RWF amount before the USSD handoff. Android users may separately opt in to M-Money SMS capture; permission and receipt evidence do not create a ledger effect.
- Signed-out visitors may inspect public groups. A member must complete a Rwanda MoMo profile before creating a payment intent.

## Payment finality

A pending intent is not a contribution. The mobile-network USSD prompt is where the member authorizes payment. Authenticated, consented receipt SMS is candidate evidence. The server checks receiver, payer, amount, time window, and transaction ID, and sends ambiguous or incomplete evidence to a permission-gated Admin queue. A production-confirmed contribution and balanced ledger posting require independently reconciled settlement evidence or an explicitly approved constrained finality policy. The existing exact-match flow cannot be called production-approved until that policy and its deployed implementation are validated.

## Admin and public surfaces

The Admin PWA supports Rwanda groups, members, MoMo payees, transactions, reconciliations, and ledgers. The public website explains local group savings and MoMo USSD. All surfaces use the owner-selected Revolut design skill for visual decisions while keeping Collect terminology and access controls.

## Release boundary

Source checks, local tests, migration validation, visual and interaction review under the owner-selected `revolut-design` skill, provider/device UAT, deployment, and store review are distinct evidence areas. The skill is the sole UI/UX authority; repository screenshots and reports are evidence, not an independent design rule or approval.
