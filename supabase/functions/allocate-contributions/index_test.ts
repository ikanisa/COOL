import {
  type AllocateContributionsHandlerDependencies,
  createAllocateContributionsHandler,
} from "./index.ts";

type RpcCall = {
  name: string;
  args: Record<string, unknown>;
};

type InFilter = {
  table: string;
  column: string;
  values: unknown[];
};

function expectEquals<T>(actual: T, expected: T, message: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: expected ${JSON.stringify(expected)}, got ${
        JSON.stringify(actual)
      }`,
    );
  }
}

function expect(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

function buildRequest(body: Record<string, unknown> = {
  partner_id: "partner-1",
}) {
  return new Request(
    "https://example.com/functions/v1/allocate-contributions",
    {
      method: "POST",
      headers: {
        authorization: "Bearer caller-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
}

function buildDeps(overrides: {
  scopedReviewError?: { message: string } | null;
  allocationError?: { message: string } | null;
  parsedPayerName?: string | null;
} = {}) {
  const rpcCalls: RpcCall[] = [];
  const adminTables: string[] = [];
  const inFilters: InFilter[] = [];

  const scopedReviews = [{ review_id: "recon-1" }, { review_id: "" }];
  const recons = [
    {
      id: "recon-1",
      match_status: "manual_review",
      parsed_sms_id: "parsed-1",
      metadata: { matching_group_ids: ["group-1"] },
    },
  ];
  const parsedRows = [
    {
      id: "parsed-1",
      amount: 25000,
      payer_phone: "+250788111333",
      payer_name: overrides.parsedPayerName ?? null,
      momo_tx_id: "momo-1",
      payee_phone: null,
    },
  ];
  const members = [
    {
      user_id: "user-1",
      display_name: "Jeanne",
      phone: "0788111333",
      group_id: "group-1",
      group_name: "Alpha Circle",
      contribution_amount: 25000,
    },
  ];

  const userClient = {
    auth: {
      getUser: async () => ({
        data: { user: { id: "caller-1" } },
        error: null,
      }),
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      rpcCalls.push({ name, args });
      if (name === "get_bank_manual_review_allocations") {
        return {
          data: overrides.scopedReviewError ? null : scopedReviews,
          error: overrides.scopedReviewError ?? null,
        };
      }
      if (name === "get_bank_all_group_members_for_matching") {
        return { data: members, error: null };
      }
      if (name === "bank_allocate_manual_review_allocation") {
        return { data: null, error: overrides.allocationError ?? null };
      }
      if (name === "bank_write_ai_allocation_suggestion") {
        return { data: [{ review_id: args.p_review_id }], error: null };
      }
      throw new Error(`Unexpected RPC: ${name}`);
    },
  };

  const adminClient = {
    from: (table: string) => {
      adminTables.push(table);
      if (table === "momo_reconciliations") {
        const query = {
          select: () => query,
          in: (column: string, values: unknown[]) => {
            inFilters.push({ table, column, values });
            return query;
          },
          order: () => query,
          limit: async () => ({ data: recons, error: null }),
        };
        return query;
      }
      if (table === "momo_sms_parsed") {
        const query = {
          select: () => query,
          in: async (column: string, values: unknown[]) => {
            inFilters.push({ table, column, values });
            return { data: parsedRows, error: null };
          },
        };
        return query;
      }
      throw new Error(`Unexpected admin table query: ${table}`);
    },
  };

  const deps: AllocateContributionsHandlerDependencies = {
    createAdminClient: () =>
      adminClient as unknown as ReturnType<
        AllocateContributionsHandlerDependencies["createAdminClient"]
      >,
    createUserClient: () =>
      userClient as unknown as ReturnType<
        AllocateContributionsHandlerDependencies["createUserClient"]
      >,
    getGeminiApiKey: () => "",
  };

  return {
    deps,
    getState: () => ({ rpcCalls, adminTables, inFilters }),
  };
}

Deno.test("allocate-contributions rejects unauthorized bank review access before admin reads", async () => {
  const { deps, getState } = buildDeps({
    scopedReviewError: {
      message: "Not authorized to view this bank custody workspace.",
    },
  });
  const handler = createAllocateContributionsHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();
  const state = getState();

  expectEquals(response.status, 403, "unauthorized workspace should be 403");
  expectEquals(
    payload.error,
    "Not authorized to view this bank custody workspace.",
    "response should expose the bank RPC error",
  );
  expectEquals(state.adminTables, [], "admin client should not read tables");
});

Deno.test("allocate-contributions suggests only from scoped reviews and scoped members", async () => {
  const { deps, getState } = buildDeps();
  const handler = createAllocateContributionsHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();
  const state = getState();

  expectEquals(response.status, 200, "allocation response status");
  expectEquals(payload.processed, 1, "processed count");
  expectEquals(payload.suggested, 1, "suggested count");
  expectEquals(payload.auto_allocated, 0, "auto allocation count");
  expectEquals(
    state.inFilters.find((filter) =>
      filter.table === "momo_reconciliations" && filter.column === "id"
    )?.values,
    ["recon-1"],
    "reconciliation reads must stay limited to scoped review IDs",
  );
  expect(
    state.rpcCalls.some((call) =>
      call.name === "get_bank_all_group_members_for_matching"
    ),
    "handler should fetch members through the scoped bank RPC",
  );
  const suggestionCall = state.rpcCalls.find((call) =>
    call.name === "bank_write_ai_allocation_suggestion"
  );
  expect(!!suggestionCall, "handler should write through suggestion RPC");
  expectEquals(
    suggestionCall?.args,
    {
      p_partner_id: "partner-1",
      p_review_id: "recon-1",
      p_group_id: "group-1",
      p_member_user_id: "user-1",
      p_confidence: 65,
      p_reasoning:
        "exact phone match, exact amount match, candidate group match",
    },
    "suggestion RPC arguments",
  );
});

Deno.test("allocate-contributions falls back to guarded suggestion when auto-allocation fails", async () => {
  const { deps, getState } = buildDeps({
    allocationError: { message: "allocation rejected" },
    parsedPayerName: "Jeanne",
  });
  const handler = createAllocateContributionsHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();
  const state = getState();

  expectEquals(response.status, 200, "allocation response status");
  expectEquals(payload.suggested, 1, "suggested count");
  expectEquals(payload.auto_allocated, 0, "auto allocation count");
  expect(
    state.rpcCalls.some((call) =>
      call.name === "bank_allocate_manual_review_allocation"
    ),
    "high-confidence match should try auto-allocation",
  );
  expect(
    state.rpcCalls.some((call) =>
      call.name === "bank_write_ai_allocation_suggestion"
    ),
    "failed auto-allocation should fall back to guarded suggestion",
  );
});
