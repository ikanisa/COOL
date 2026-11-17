# Native observation to Collect ledger: implementation boundary

**Superseded product direction, 12 November:** The owner has instructed that
M-Money transactions be processed and displayed automatically, without a
manual SMS-verification workflow. The text below records the earlier
observation-only design and its technical constraints; it is not the intended
product flow. Implement automatic native provenance, parsing, transaction
storage and direction-aware display while preserving original source evidence
and avoiding invented fields or duplicate financial effects.

Status: design and assessment only. No native observation is promoted to a
canonical receipt or ledger entry by this work. The native promotion assessment
adapter is default off and has no HTTP route. The SQL context remains an
unregistered draft. Its synthetic qualification exercised authorization,
encrypted storage, recipient-text matching and zero financial effects; those
checks do not authenticate the sender, prove message completeness or establish a
receiving wallet for a message that omits it.

## Required additive implementation

1. Establish a reviewed, server-verifiable source/wallet witness for the actual
   capture format. It must bind the immutable observation, raw-body and object
   digests, capture completeness and receiving account to current approved
   collection/account scope. A SIM subscription, Android sender label, parser
   result, configured account, or a client-supplied `complete` flag is not by
   itself such a witness. Messages with absent, ambiguous, revoked or conflicting
   proof stay unresolved. Preserve the existing product's chosen assurance;
   do not invent a carrier or managed-session proof.
2. Add a typed native provenance record and allow an `app.sms_receipts` row to
   reference either its genuine managed `originating_session_id` or a verified
   native observation, never both or neither. The existing managed-session FK and
   legacy insert semantics must remain enforced. Pin the exact predecessor
   constraints, storage trigger, grants, RLS and retention catalog before an
   additive migration, and revalidate the original committed encrypted object
   rather than creating or transferring another receiver binding.
3. Extend the live `app.momo_processing_jobs` constraint and enrollment guard
   with a separate typed native source branch. The current branch requires a
   binding, binding version and account; do not manufacture these fields for
   native capture. Validate the native source, current scoped account, approved
   profile and evidence again in the processing transaction.
4. Feed the verified native source into the existing canonical parse/transaction
   flow. Preserve `app.momo_transactions`' unique key
   `(provider, receiving_account_id, event_kind, provider_transaction_id)`,
   compare immutable core facts under the existing mutation lock, and preserve
   accepted, duplicate and conflict outcomes and original-source lineage.
   Exact retries must resolve to the same committed outcome; uncertain outcomes
   must remain visible rather than be replayed or acknowledged as committed.
5. Extend `private.burimunsi_transaction_scopes`, its adoption trigger and
   posting preparation/allocation/custody readers to distinguish verified native
   provenance from the existing gateway binding/credential branch. Keep the
   gateway branch unchanged. Only the existing guarded ledger transaction can
   create a financial effect, after current authority, profile, source, storage,
   recipient evidence, conflict and duplicate checks pass.
6. Add catalog and inspection coverage for every new provenance field/relation;
   keep unknown retention effects blocked. Qualify both source types, cross-phone
   and cross-group denial, revocation/profile races, original-source preservation,
   conflicting duplicates, concurrent admissions and lost responses in isolated
   PostgreSQL and storage before enabling the feature. Confirm the actual Pixel
   format and run an authorized end-to-end test without reposting historical data.

The historical workbook example links code 41258 in a separate transaction row,
while its corresponding SMS text does not contain that code. That linkage is
historical detection-format evidence, not proof of the current phone/account
association or authority to repost the transaction. A separate count-only Pixel
diagnostic found ten messages matching the provisional markers; none contained
the runtime code as a standalone numeric token or near the tested recipient
labels. This is limited to those ten messages and tested patterns, and does not
establish their destination. It did not validate a wallet, message completeness,
posting or a real end-to-end transaction.

## Existing gateway witness and automatic enrollment

The current canonical gateway path treats an Owner-approved binding, its exact
installation grant and custodian, wallet, credential, subscription record and
version as its routing evidence. It revalidates those records at upload and
posting. This is the existing operator-approved trust model; it is not a
cryptographic carrier verification. The native PIN login automatically creates
or reuses an installation grant, but it does not create the gateway binding or
prove that the phone receives messages for a particular wallet. The gateway
credential is unique to one binding and installation. A different installation
cannot reuse it without changing the existing custody contract.

An automatic credential recovery for an already paired installation could be
implemented using current four-proof PIN authority and the existing exact
binding, grant and credential, without another pairing-code entry. It would not
establish a route for an unpaired phone or prove a message's receiving wallet.
A first-seen native receipt therefore still needs an independent, reviewed
source/account witness and a complete-source capture; its typed provenance,
canonical job and custody branches must then be qualified. The current active
Android scanner emits incomplete `catch_up` observations; the local PDU
correlation classes are not integrated into that scanner. No automatic posting
or new association has been implemented on this basis.
