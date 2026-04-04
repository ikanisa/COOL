import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import {
  buildManualReviewResult,
  reconcileParsedSms,
} from "./reconciliation.ts";
import {
  assert,
  assertDeepEquals,
  assertEquals,
  FakeAdminClient,
  type TableStore,
} from "./reconciliation_test_support.ts";

const sampleRawSms: RawSmsRecord = {
  id: "sms-1",
  user_id: "user-1",
  sender: "M-Money",
  sms_body: "Payment of 10,000 RWF confirmed.",
  provider: "mtn_rwanda",
  country: "RW",
  sms_received_at: "2026-03-11T15:00:00.000Z",
  detected_tx_type: "payment",
  detected_amount: 10000,
  detected_tx_id: "ABC12345",
};

const sampleParsedSms: ParsedSms = {
  parse_status: "parsed",
  confidence: 0.98,
  tx_direction: "debit",
  tx_type: "payment",
  tx_category: "group_contribution",
  cashflow_bucket: "savings",
  momo_tx_id: "ABC12345",
  amount: 10000,
  currency: "RWF",
  tx_date: "2026-03-11",
  tx_time: "15:00:00",
  tx_datetime_iso: "2026-03-11T15:00:00.000Z",
  payer_name: "Alex Fan",
  payer_number_last3: "456",
  payer_number_full: "250788123456",
  payee_name: "COOL App",
  payee_number_or_code: "250788111222",
  merchant_code: null,
  fee_amount: 0,
  balance_after: 25000,
  counterparty_name: "COOL App",
  ai_summary: "Paid into a COOL App flow.",
  recurring_pattern_hint: "one_off",
  narrative: "Test payment",
  notes: null,
};

Deno.test("buildManualReviewResult marks the record as a manual review", () => {
  const result = buildManualReviewResult("Needs operator review", {
    reason: "example",
    candidate_score: 11,
  });

  assertEquals(
    result.matchType,
    "manual_review",
    "match type should be manual",
  );
  assertEquals(
    result.matchStatus,
    "manual_review",
    "match status should be manual",
  );
  assertEquals(result.ledgerStatus, "draft", "ledger should remain draft");
  assertEquals(
    result.metadata.auto_match,
    false,
    "manual review should disable auto-match",
  );
  assertEquals(
    result.metadata.reason,
    "example",
    "custom metadata should round-trip",
  );
});

Deno.test("reconcileParsedSms returns manual review when amount is missing", async () => {
  const adminClient = new FakeAdminClient({});
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    { ...sampleParsedSms, amount: null },
    "parsed-sms-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(result.matchType, "manual_review", "missing amount should bail");
  assertEquals(
    result.metadata.reason,
    "missing_amount",
    "reason should explain the failure",
  );
});

Deno.test("reconcileParsedSms confirms a matched group contribution", async () => {
  const tables: TableStore = {
    group_contributions: [
      {
        id: "contribution-1",
        group_id: "group-1",
        user_id: "user-1",
        amount: 10000,
        momo_reference: "GCT-001",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
      },
    ],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "group_contribution",
    "group contribution should resolve from the domain row directly",
  );
  assertEquals(result.matchStatus, "matched", "matched payment should post");
  assertEquals(
    result.targetTable,
    "group_contributions",
    "group contribution should be the target table",
  );
  assertEquals(
    result.targetRecordId,
    "contribution-1",
    "resolved contribution id should be returned",
  );
  assertEquals(
    result.metadata.group_id,
    "group-1",
    "group id should be included in metadata",
  );
  assertEquals(
    tables.group_contributions[0]?.status,
    "confirmed",
    "group contribution should be confirmed",
  );
});

Deno.test("reconcileParsedSms allocates group payments directly from payee routes", async () => {
  const tables: TableStore = {
    pending_transactions: [],
    groups: [
      {
        id: "group-route-1",
        name: "Abanyamurava Savings",
        type: "community",
        receiving_momo_code: "250788111222",
        momo_number: null,
        receiving_momo_route_type: "phone_number",
      },
    ],
    group_members: [],
    group_contributions: [],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-payee-group-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "payee_route_group",
    "group payee routes should reconcile without pending app transactions",
  );
  assertEquals(
    result.targetTable,
    "group_contributions",
    "payee-route allocations should target group contributions",
  );
  assertEquals(
    result.metadata.group_id,
    "group-route-1",
    "matched group id should be surfaced",
  );
  assertEquals(
    tables.group_contributions.length,
    1,
    "a confirmed contribution should be created from the payee route",
  );
  assertEquals(
    tables.group_contributions[0]?.status,
    "confirmed",
    "created contribution should be confirmed",
  );
});

Deno.test("reconcileParsedSms leaves unmatched target records in pending review", async () => {
  const tables: TableStore = {
    group_contributions: [],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-2",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "manual_review",
    "missing target records should fall back to manual review",
  );
  assertEquals(
    result.matchStatus,
    "manual_review",
    "missing targets should require review",
  );
  assertEquals(
    result.metadata.reason,
    "no_matching_payment_record",
    "reason should explain the manual review",
  );
  assertDeepEquals(
    tables.group_contributions,
    [],
    "no contribution rows should be created",
  );
});

Deno.test("reconcileParsedSms allocates partner payments directly from payee routes", async () => {
  const tables: TableStore = {
    pending_transactions: [],
    group_contributions: [],
    groups: [],
    partner_payment_routes: [
      {
        id: "route-1",
        partner_id: "partner-1",
        recipient_code: "250788111222",
        reconciliation_label: "bank_partner",
        status: "active",
        partners: {
          name: "Urwego Bank",
          slug: "urwego",
        },
      },
    ],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-payee-partner-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "payee_route_partner",
    "partner payee routes should reconcile without pending app transactions",
  );
  assertEquals(
    result.targetTable,
    "partner_payment_routes",
    "generic partner allocations should target payment routes",
  );
  assertEquals(
    result.targetRecordId,
    "route-1",
    "matched route id should round-trip",
  );
  assertEquals(
    result.metadata.partner_id,
    "partner-1",
    "partner id should be captured for downstream ledgers",
  );
});

