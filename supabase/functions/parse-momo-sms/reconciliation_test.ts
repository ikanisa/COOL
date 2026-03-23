import { type ParsedSms, type RawSmsRecord } from "./ai_parser.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { confirmRayonReferenceMatch } from "../_shared/rayon_payments.ts";
import {
  buildManualReviewResult,
  reconcileParsedSms,
} from "./reconciliation.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message);
  }
}

function assertEquals<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function assertDeepEquals(
  actual: unknown,
  expected: unknown,
  message: string,
): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${message}: expected ${expectedJson}, got ${actualJson}`);
  }
}

type TableRow = Record<string, unknown>;
type TableStore = Record<string, TableRow[]>;
type QueryResult = { data: unknown; error: unknown | null };
type RpcCall = { name: string; args: Record<string, unknown> | undefined };

class FakeAdminClient {
  readonly rpcCalls: RpcCall[] = [];

  constructor(
    private readonly tables: TableStore,
    private readonly options: {
      rpcFailures?: Record<string, string>;
    } = {},
  ) {}

  from(table: string): FakeQueryBuilder {
    return new FakeQueryBuilder(this.tables, table);
  }

  rpc(name: string, args?: Record<string, unknown>): Promise<QueryResult> {
    this.rpcCalls.push({ name, args });
    const failureMessage = this.options.rpcFailures?.[name];
    if (failureMessage) {
      return Promise.resolve({
        data: null,
        error: new Error(failureMessage),
      });
    }

    if (name === "confirm_contribution") {
      const contributionId = typeof args?.p_contribution_id === "string"
        ? args.p_contribution_id
        : null;
      const contributions = this.tables.group_contributions ?? [];
      const contribution = contributionId
        ? contributions.find((row) => row.id === contributionId)
        : null;

      if (!contribution) {
        return Promise.resolve({
          data: {
            status: "error",
            message: "Contribution not found",
          },
          error: null,
        });
      }

      const normalizedStatus = String(contribution.status ?? "")
        .trim()
        .toLowerCase();
      if (normalizedStatus !== "confirmed") {
        contribution.status = "confirmed";
        contribution.confirmed_at = contribution.confirmed_at ??
          new Date().toISOString();

        const groupId = typeof contribution.group_id === "string"
          ? contribution.group_id
          : null;
        const amount = typeof contribution.amount === "number"
          ? contribution.amount
          : Number(contribution.amount ?? 0);
        const group = groupId
          ? (this.tables.groups ?? []).find((row) => row.id === groupId)
          : null;
        if (group) {
          const currentAmount = typeof group.amount === "number"
            ? group.amount
            : Number(group.amount ?? 0);
          group.amount = currentAmount + amount;
        }
      }

      return Promise.resolve({
        data: {
          status: normalizedStatus === "confirmed"
            ? "already_confirmed"
            : "ok",
        },
        error: null,
      });
    }

    return Promise.resolve({ data: null, error: null });
  }
}

class FakeQueryBuilder implements PromiseLike<QueryResult> {
  private action: "select" | "update" | "insert" = "select";
  private filters: Array<
    | { kind: "eq"; column: string; value: unknown }
    | { kind: "in"; column: string; values: unknown[] }
    | { kind: "ilike"; column: string; value: string }
  > = [];
  private limitCount: number | null = null;
  private orderColumn: string | null = null;
  private ascending = true;
  private updatePayload: Record<string, unknown> | null = null;
  private insertPayload: Record<string, unknown>[] = [];
  private insertedRows: TableRow[] | null = null;

  constructor(
    private readonly tables: TableStore,
    private readonly table: string,
  ) {}

  select(_columns: string): this {
    if (this.action !== "insert") {
      this.action = "select";
    }
    return this;
  }

  update(values: Record<string, unknown>): this {
    this.action = "update";
    this.updatePayload = values;
    return this;
  }

  insert(values: Record<string, unknown> | Record<string, unknown>[]): this {
    this.action = "insert";
    this.insertPayload = Array.isArray(values) ? values : [values];
    return this;
  }

  eq(column: string, value: unknown): this {
    this.filters.push({ kind: "eq", column, value });
    return this;
  }

  in(column: string, values: unknown[]): this {
    this.filters.push({ kind: "in", column, values });
    return this;
  }

  ilike(column: string, value: string): this {
    this.filters.push({ kind: "ilike", column, value });
    return this;
  }

  order(column: string, options?: { ascending?: boolean }): this {
    this.orderColumn = column;
    this.ascending = options?.ascending ?? true;
    return this;
  }

  limit(count: number): this {
    this.limitCount = count;
    return this;
  }

  maybeSingle(): Promise<QueryResult> {
    return Promise.resolve(this.execute(true));
  }

  single(): Promise<QueryResult> {
    return Promise.resolve(this.execute(true));
  }

  then<TResult1 = QueryResult, TResult2 = never>(
    onfulfilled?:
      | ((value: QueryResult) => TResult1 | PromiseLike<TResult1>)
      | null,
    onrejected?:
      | ((reason: unknown) => TResult2 | PromiseLike<TResult2>)
      | null,
  ): Promise<TResult1 | TResult2> {
    return Promise.resolve(this.execute(false)).then(onfulfilled, onrejected);
  }

  private execute(expectSingle: boolean): QueryResult {
    if (this.action === "insert") {
      if (this.insertedRows == null) {
        const target = this.tables[this.table] ??= [];
        this.insertedRows = this.insertPayload.map((row, index) => {
          const payload = { ...row };
          payload["id"] ??= `${this.table}-${target.length + index + 1}`;
          return payload;
        });
        target.push(...this.insertedRows);
      }

      const limitedInserted = this.limitCount == null
        ? this.insertedRows
        : this.insertedRows.slice(0, this.limitCount);
      return {
        data: expectSingle ? (limitedInserted[0] ?? null) : limitedInserted,
        error: null,
      };
    }

    const rows = [...(this.tables[this.table] ?? [])]
      .filter((row) => this.matches(row));

    if (this.orderColumn) {
      rows.sort((left, right) => {
        const leftValue = String(left[this.orderColumn!] ?? "");
        const rightValue = String(right[this.orderColumn!] ?? "");
        return this.ascending
          ? leftValue.localeCompare(rightValue)
          : rightValue.localeCompare(leftValue);
      });
    }

    const limitedRows = this.limitCount == null
      ? rows
      : rows.slice(0, this.limitCount);

    if (this.action === "update") {
      for (const row of limitedRows) {
        Object.assign(row, this.updatePayload);
      }
      return { data: limitedRows, error: null };
    }

    return {
      data: expectSingle ? (limitedRows[0] ?? null) : limitedRows,
      error: null,
    };
  }

  private matches(row: TableRow): boolean {
    return this.filters.every((filter) => {
      const value = row[filter.column];
      switch (filter.kind) {
        case "eq":
          return value === filter.value;
        case "in":
          return filter.values.includes(value);
        case "ilike":
          return String(value ?? "").toLowerCase().includes(
            filter.value.replaceAll("%", "").toLowerCase(),
          );
      }
    });
  }
}

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
    driver_subscriptions: [],
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
    driver_subscriptions: [],
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
    driver_subscriptions: [],
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
    driver_subscriptions: [],
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

Deno.test("reconcileParsedSms activates matched driver subscriptions", async () => {
  const tables: TableStore = {
    group_contributions: [],
    driver_subscriptions: [
      {
        id: "driver-sub-1",
        driver_id: "user-1",
        amount: 10000,
        amount_rwf: 10000,
        momo_reference: "SUB-user-1-1741700000000",
        status: "pending",
        started_at: null,
        expires_at: null,
        created_at: "2026-03-11T14:59:00.000Z",
      },
    ],
  };

  const adminClient = new FakeAdminClient(tables);
  const timestamp = "2026-03-11T15:05:00.000Z";
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-sub-1",
    timestamp,
  );

  assertEquals(
    result.matchType,
    "driver_subscription",
    "subscription rows should resolve directly from driver_subscriptions",
  );
  assertEquals(
    result.targetTable,
    "driver_subscriptions",
    "driver subscriptions should be activated",
  );
  assertEquals(
    result.targetRecordId,
    "driver-sub-1",
    "matched subscription id should round-trip",
  );
  assertEquals(
    tables.driver_subscriptions[0]?.status,
    "active",
    "driver subscription should become active",
  );
  assertEquals(
    tables.driver_subscriptions[0]?.started_at,
    timestamp,
    "missing started_at should backfill from reconciliation time",
  );
  assert(
    typeof tables.driver_subscriptions[0]?.expires_at === "string",
    "missing expires_at should be synthesized",
  );
});

Deno.test("reconcileParsedSms confirms matched Rayon ticket references", async () => {
  const tables: TableStore = {
    pending_transactions: [
      {
        id: "pending-ticket-1",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-TICKET-001",
        recipient_momo: "250788111222",
        amount: 10000,
        provider: "mtn_rwanda",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: null,
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_tickets: [
      {
        id: "ticket-1",
        user_id: "user-1",
        referral_invite_id: null,
        seat_type: "VIP",
        amount_paid: 10000,
        qr_code: "qr-1",
        momo_reference: "RS-TICKET-001",
        status: "pending",
        purchased_at: "2026-03-11T14:58:00.000Z",
        rs_matches: {
          home_team: "Rayon Sports FC",
          away_team: "APR FC",
          competition: "League",
          venue: "Amahoro Stadium",
          match_date: "2026-03-20",
          kickoff_time: "18:00:00",
          partner_id: null,
        },
      },
    ],
    users: [],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-ticket-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "rayon_ticket",
    "Rayon ticket references should use the shared confirmation path",
  );
  assertEquals(result.matchStatus, "matched", "ticket should be confirmed");
  assertEquals(
    result.targetTable,
    "rs_tickets",
    "ticket reconciliation should target Rayon tickets",
  );
  assertEquals(
    result.targetRecordId,
    "ticket-1",
    "ticket id should round-trip from the shared confirmation path",
  );
  assertEquals(
    tables.rs_tickets[0]?.status,
    "valid",
    "pending tickets should become valid after confirmation",
  );
  assertEquals(
    result.metadata.ticket_count,
    1,
    "metadata should reflect the confirmed ticket count",
  );
  assertEquals(
    result.metadata.source,
    "parse-momo-sms",
    "shared Rayon confirmation should preserve the parser source",
  );
});

Deno.test("reconcileParsedSms confirms matched Rayon shop order references", async () => {
  const tables: TableStore = {
    pending_transactions: [
      {
        id: "pending-shop-1",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-SHOP-001",
        recipient_momo: "250788111222",
        amount: 12500,
        provider: "mtn_rwanda",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: null,
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_shop_orders: [
      {
        id: "shop-order-1",
        user_id: "user-1",
        referral_invite_id: null,
        total: 12500,
        delivery_address: "Kigali Heights",
        momo_reference: "RS-SHOP-001",
        status: "pending",
        created_at: "2026-03-11T14:58:00.000Z",
      },
    ],
    partners: [
      {
        id: "partner-rayon-1",
        name: "Rayon Sports FC",
      },
    ],
    users: [],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_amount: 12500, detected_tx_id: "SHOP12345" },
    { ...sampleParsedSms, amount: 12500, momo_tx_id: "SHOP12345" },
    "parsed-sms-shop-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "rayon_shop_order",
    "Rayon shop references should use the shop confirmation path",
  );
  assertEquals(
    result.targetTable,
    "rs_shop_orders",
    "shop confirmation should target Rayon shop orders",
  );
  assertEquals(
    result.targetRecordId,
    "shop-order-1",
    "shop order id should round-trip",
  );
  assertEquals(
    tables.rs_shop_orders[0]?.status,
    "paid",
    "pending shop orders should become paid",
  );
  assertEquals(
    result.metadata.partner_id,
    "partner-rayon-1",
    "resolved Rayon partner id should be surfaced in metadata",
  );
  assertEquals(
    result.metadata.points_awarded,
    125,
    "shop confirmation should award points from order total",
  );
});

Deno.test("reconcileParsedSms confirms matched Rayon initiative references", async () => {
  const tables: TableStore = {
    pending_transactions: [
      {
        id: "pending-support-1",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-SUPPORT-001",
        recipient_momo: "250788111222",
        amount: 3000,
        provider: "mtn_rwanda",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: null,
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_initiative_contributions: [
      {
        id: "initiative-contribution-1",
        user_id: "user-1",
        referral_invite_id: null,
        initiative_id: "initiative-1",
        amount: 3000,
        momo_reference: "RS-SUPPORT-001",
        status: "pending",
        created_at: "2026-03-11T14:58:00.000Z",
        rs_initiatives: {
          title: "Youth Academy Fund",
          partner_id: "partner-rayon-1",
        },
      },
    ],
    rs_initiatives: [
      {
        id: "initiative-1",
        raised_amount: 5000,
        supporter_count: 2,
      },
    ],
    users: [],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_amount: 3000, detected_tx_id: "SUP12345" },
    { ...sampleParsedSms, amount: 3000, momo_tx_id: "SUP12345" },
    "parsed-sms-support-1",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "rayon_initiative_support",
    "Rayon initiative references should use the support confirmation path",
  );
  assertEquals(
    result.targetTable,
    "rs_initiative_contributions",
    "support confirmation should target initiative contributions",
  );
  assertEquals(
    result.targetRecordId,
    "initiative-contribution-1",
    "initiative contribution id should round-trip",
  );
  assertEquals(
    tables.rs_initiative_contributions[0]?.status,
    "confirmed",
    "pending initiative contributions should become confirmed",
  );
  assertEquals(
    tables.rs_initiatives[0]?.raised_amount,
    8000,
    "initiative totals should increase once",
  );
  assertEquals(
    tables.rs_initiatives[0]?.supporter_count,
    3,
    "initiative supporter count should increase once",
  );
  assertEquals(
    result.metadata.points_awarded,
    60,
    "support confirmation should award support points",
  );
});

Deno.test("reconcileParsedSms returns manual review when Rayon ticket rows are missing", async () => {
  const adminClient = new FakeAdminClient({
    pending_transactions: [
      {
        id: "pending-missing-ticket",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-TICKET-404",
        recipient_momo: "250788111222",
        amount: 10000,
        provider: "mtn_rwanda",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: null,
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_tickets: [],
  });

  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    sampleRawSms,
    sampleParsedSms,
    "parsed-sms-missing-ticket",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "manual_review",
    "missing Rayon ticket rows should require manual review",
  );
  assertEquals(
    result.metadata.reason,
    "no_matching_payment_record",
    "ticket reason should explain the missing domain candidate",
  );
});

Deno.test("reconcileParsedSms returns manual review when Rayon shop rows are missing", async () => {
  const adminClient = new FakeAdminClient({
    pending_transactions: [
      {
        id: "pending-missing-shop",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-SHOP-404",
        recipient_momo: "250788111222",
        amount: 12500,
        provider: "mtn_rwanda",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: null,
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_shop_orders: [],
  });

  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_amount: 12500, detected_tx_id: "SHOP404" },
    { ...sampleParsedSms, amount: 12500, momo_tx_id: "SHOP404" },
    "parsed-sms-missing-shop",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "manual_review",
    "missing Rayon shop rows should require manual review",
  );
  assertEquals(
    result.metadata.reason,
    "no_matching_payment_record",
    "shop reason should explain the missing domain candidate",
  );
});

Deno.test("reconcileParsedSms returns manual review when Rayon initiative rows are missing", async () => {
  const adminClient = new FakeAdminClient({
    pending_transactions: [
      {
        id: "pending-missing-support",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-SUPPORT-404",
        recipient_momo: "250788111222",
        amount: 3000,
        provider: "mtn_rwanda",
        status: "pending",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: null,
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_initiative_contributions: [],
  });

  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_amount: 3000, detected_tx_id: "SUP404" },
    { ...sampleParsedSms, amount: 3000, momo_tx_id: "SUP404" },
    "parsed-sms-missing-support",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "manual_review",
    "missing Rayon initiative rows should require manual review",
  );
  assertEquals(
    result.metadata.reason,
    "no_matching_payment_record",
    "support reason should explain the missing domain candidate",
  );
});

Deno.test("reconcileParsedSms degrades cleanly when RPCs and WhatsApp delivery fail", async () => {
  const adminClient = new FakeAdminClient(
    {
      pending_transactions: [
        {
          id: "pending-ticket-degraded",
          user_id: "user-1",
          group_id: null,
          group_contribution_id: null,
          reference: "RS-TICKET-DEGRADED",
          recipient_momo: "250788111222",
          amount: 10000,
          provider: "mtn_rwanda",
          status: "pending",
          created_at: "2026-03-11T14:57:00.000Z",
          confirmed_at: null,
        },
      ],
      group_contributions: [],
      driver_subscriptions: [],
      rs_tickets: [
        {
          id: "ticket-degraded-1",
          user_id: "user-1",
          referral_invite_id: "invite-1",
          seat_type: "VIP",
          amount_paid: 10000,
          qr_code: "qr-degraded-1",
          momo_reference: "RS-TICKET-DEGRADED",
          status: "pending",
          purchased_at: "2026-03-11T14:58:00.000Z",
          rs_matches: {
            home_team: "Rayon Sports FC",
            away_team: "APR FC",
            competition: "League",
            venue: "Amahoro Stadium",
            match_date: "2026-03-20",
            kickoff_time: "18:00:00",
            partner_id: "partner-rayon-1",
          },
        },
      ],
      users: [
        {
          id: "user-1",
          phone: "+250788123456",
          whatsapp_number: "+250788123456",
        },
      ],
    },
    {
      rpcFailures: {
        rs_apply_membership_points: "membership points unavailable",
        activate_referral_invite_for_user: "referral activation unavailable",
      },
    },
  );

  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_tx_id: "DEGRADED123" },
    { ...sampleParsedSms, momo_tx_id: "DEGRADED123" },
    "parsed-sms-degraded-ticket",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "rayon_ticket",
    "ticket match should still succeed",
  );
  assertEquals(
    result.metadata.points_awarded,
    0,
    "failed points RPC should zero out awarded points metadata",
  );
  assertEquals(
    result.metadata.referral_activated,
    false,
    "failed referral RPC should degrade to false",
  );
  assertEquals(
    result.metadata.whatsapp_sent,
    false,
    "failed WhatsApp delivery should degrade to false",
  );
  assert(
    adminClient.rpcCalls.some((call) =>
      call.name === "rs_apply_membership_points"
    ),
    "membership points RPC should be attempted",
  );
  assert(
    adminClient.rpcCalls.some((call) =>
      call.name === "activate_referral_invite_for_user"
    ),
    "referral activation RPC should be attempted",
  );
});

Deno.test("reconcileParsedSms keeps Rayon ticket replays idempotent", async () => {
  const tables: TableStore = {
    pending_transactions: [
      {
        id: "pending-ticket-replay",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-TICKET-REPLAY",
        recipient_momo: "250788111222",
        amount: 10000,
        provider: "mtn_rwanda",
        status: "confirmed",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: "2026-03-11T15:00:00.000Z",
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_tickets: [
      {
        id: "ticket-replay-1",
        user_id: "user-1",
        referral_invite_id: null,
        seat_type: "VIP",
        amount_paid: 10000,
        qr_code: "qr-replay-1",
        momo_reference: "RS-TICKET-REPLAY",
        status: "valid",
        purchased_at: "2026-03-11T14:58:00.000Z",
        rs_matches: {
          home_team: "Rayon Sports FC",
          away_team: "APR FC",
          competition: "League",
          venue: "Amahoro Stadium",
          match_date: "2026-03-20",
          kickoff_time: "18:00:00",
          partner_id: "partner-rayon-1",
        },
      },
    ],
    users: [
      {
        id: "user-1",
        phone: "+250788123456",
        whatsapp_number: "+250788123456",
      },
    ],
  };

  const adminClient = new FakeAdminClient(tables);

  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_tx_id: "REPLAY123" },
    { ...sampleParsedSms, momo_tx_id: "REPLAY123" },
    "parsed-sms-replay-ticket",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "rayon_ticket",
    "replayed ticket should still resolve",
  );
  assertEquals(
    tables.rs_tickets[0]?.status,
    "valid",
    "replayed tickets should stay valid",
  );
  assertEquals(
    result.metadata.points_awarded,
    0,
    "replayed tickets must not re-award points",
  );
  assertEquals(
    result.metadata.whatsapp_sent,
    false,
    "replayed tickets must not resend WhatsApp confirmations",
  );
  assert(
    !adminClient.rpcCalls.some((call) =>
      call.name === "rs_apply_membership_points"
    ),
    "replayed tickets with zero points should skip the points RPC",
  );
});

Deno.test("reconcileParsedSms keeps Rayon initiative replays idempotent", async () => {
  const tables: TableStore = {
    pending_transactions: [
      {
        id: "pending-support-replay",
        user_id: "user-1",
        group_id: null,
        group_contribution_id: null,
        reference: "RS-SUPPORT-REPLAY",
        recipient_momo: "250788111222",
        amount: 3000,
        provider: "mtn_rwanda",
        status: "confirmed",
        created_at: "2026-03-11T14:57:00.000Z",
        confirmed_at: "2026-03-11T15:00:00.000Z",
      },
    ],
    group_contributions: [],
    driver_subscriptions: [],
    rs_initiative_contributions: [
      {
        id: "initiative-contribution-replay-1",
        user_id: "user-1",
        referral_invite_id: null,
        initiative_id: "initiative-replay-1",
        amount: 3000,
        momo_reference: "RS-SUPPORT-REPLAY",
        status: "confirmed",
        created_at: "2026-03-11T14:58:00.000Z",
        rs_initiatives: {
          title: "Youth Academy Fund",
          partner_id: "partner-rayon-1",
        },
      },
    ],
    rs_initiatives: [
      {
        id: "initiative-replay-1",
        raised_amount: 5000,
        supporter_count: 2,
      },
    ],
    users: [
      {
        id: "user-1",
        phone: "+250788123456",
        whatsapp_number: "+250788123456",
      },
    ],
  };

  const adminClient = new FakeAdminClient(tables);
  const result = await reconcileParsedSms(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    { ...sampleRawSms, detected_amount: 3000, detected_tx_id: "REPLAYSUP123" },
    { ...sampleParsedSms, amount: 3000, momo_tx_id: "REPLAYSUP123" },
    "parsed-sms-replay-support",
    "2026-03-11T15:05:00.000Z",
  );

  assertEquals(
    result.matchType,
    "rayon_initiative_support",
    "replayed support payments should still resolve",
  );
  assertEquals(
    tables.rs_initiative_contributions[0]?.status,
    "confirmed",
    "replayed support contributions should stay confirmed",
  );
  assertEquals(
    tables.rs_initiatives[0]?.raised_amount,
    5000,
    "replayed support confirmations must not increment totals again",
  );
  assertEquals(
    tables.rs_initiatives[0]?.supporter_count,
    2,
    "replayed support confirmations must not increment supporters again",
  );
  assertEquals(
    result.metadata.points_awarded,
    0,
    "replayed support confirmations must not re-award points",
  );
  assertEquals(
    result.metadata.whatsapp_sent,
    false,
    "replayed support confirmations must not resend WhatsApp",
  );
});

Deno.test("confirmRayonReferenceMatch rejects unsupported Rayon references", async () => {
  const adminClient = new FakeAdminClient({});
  const result = await confirmRayonReferenceMatch(
    adminClient as unknown as ReturnType<typeof createAdminClient>,
    {
      user_id: "user-1",
      reference: "RS-OTHER-001",
    },
    {
      source: "parse-momo-sms",
      timestamp: "2026-03-11T15:05:00.000Z",
      provider: "mtn_rwanda",
      amount: 10000,
    },
  );

  assertEquals(
    result.matchType,
    "manual_review",
    "unsupported Rayon references should return manual review",
  );
  assertEquals(
    result.metadata.reason,
    "unsupported_rayon_reference",
    "manual review should explain the unsupported reference",
  );
});
