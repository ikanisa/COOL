# Collect product contract: Rwanda MoMo USSD

Collect is a Rwanda-only group-contribution system. Members use RWF and MTN MoMo or Airtel Money USSD. Collect is a technology and record-keeping service; it does not operate a wallet, hold deposits, or receive a member's MoMo PIN or OTP.

## Member identity and groups

- Sign-in uses a verified Rwanda WhatsApp number. A complete member profile has country `RW`, currency `RWF`, a six-digit Collect ID, and a valid Rwanda MoMo provider and number.
- Members may create private groups on eligible Android builds after SMS consent and Play Integrity verification. Public groups are platform sponsored.
- Group receiver details are MoMo details. The app shows the exact payee and whole-RWF amount before the USSD handoff.
- Signed-out visitors may inspect public groups. A member must complete a Rwanda MoMo profile before creating a payment intent.

## Payment finality

A pending intent is not a contribution. The mobile-network USSD prompt is where the member authorizes payment. Authenticated, consented receipt SMS is candidate evidence. The server checks receiver, payer, amount, time window, and transaction ID, and sends ambiguous or incomplete evidence to a permission-gated Admin queue. A production-confirmed contribution and balanced ledger posting require independently reconciled settlement evidence or an explicitly approved constrained finality policy. The existing exact-match flow cannot be called production-approved until that policy and its deployed implementation are validated.

## Admin and public surfaces

The Admin PWA supports Rwanda groups, members, MoMo payees, transactions, reconciliations, and ledgers. The public website explains local group savings and MoMo USSD. All surfaces use the owner-selected Revolut design skill for visual decisions while keeping Collect terminology and access controls.

## Release boundary

Source checks, local tests, migration validation, visual and interaction review under the owner-selected `revolut-design` skill, provider/device UAT, deployment, and store review are distinct evidence areas. The skill is the sole UI/UX authority; repository screenshots and reports are evidence, not an independent design rule or approval.
