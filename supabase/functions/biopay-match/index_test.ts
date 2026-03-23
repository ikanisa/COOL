import {
  type BiopayMatchHandlerDependencies,
  createBiopayMatchHandler,
} from "./index.ts";
import type {
  BiopayMatchProtectionConfig,
  BiopayMatchRateOutcome,
} from "../_shared/biopay_match_abuse.ts";

const fixedNow = new Date("2026-03-23T12:00:00.000Z");
const sampleEmbedding = Array.from({ length: 128 }, (_, index) => index / 1000);

function buildConfig(): BiopayMatchProtectionConfig {
  return {
    threshold: 0.72,
    rateWindowSeconds: 60,
    userMaxAttempts: 8,
    ipMaxAttempts: 20,
    missWindowSeconds: 600,
    maxMissesPerWindow: 5,
    lockoutSeconds: 900,
  };
}

function buildRequest() {
  return new Request("https://example.com/functions/v1/biopay-match", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
      "x-forwarded-for": "198.51.100.20",
      "x-client-info": "cool/1.0.0",
      "user-agent": "CoolAppTest/1.0",
    },
    body: JSON.stringify({ embedding: sampleEmbedding }),
  });
}

function buildDeps(overrides: {
  userAttempts?: number;
  ipAttempts?: number;
  missAttempts?: number;
  latestLockoutAt?: string | null;
  matchRow?: Record<string, unknown> | null;
} = {}) {
  const rateEvents: Array<{ outcome: BiopayMatchRateOutcome; scope: string }> =
    [];
  const matchEvents: Array<Record<string, unknown>> = [];
  const operationalEvents: Array<Record<string, unknown>> = [];
  const edgeFailures: Array<Record<string, unknown>> = [];
  let matchCalls = 0;

  const deps: BiopayMatchHandlerDependencies = {
    createAdminClient: () => ({}),
    createUserClient: () => ({
      auth: {
        getUser: async () => ({
          data: { user: { id: "user-1" } },
          error: null,
        }),
      },
    }),
    now: () => new Date(fixedNow),
    getProtectionConfig: async () => buildConfig(),
    countRecentRateEvents: async (_adminClient, options) => {
      if (options.scope == "ip") {
        return overrides.ipAttempts ?? 0;
      }

      if (options.outcomes?.length == 1 && options.outcomes[0] == "miss") {
        return overrides.missAttempts ?? 0;
      }

      return overrides.userAttempts ?? 0;
    },
    getLatestRateEventAt: async () => overrides.latestLockoutAt ?? null,
    recordRateEvent: async (_adminClient, event) => {
      rateEvents.push({
        outcome: event.outcome,
        scope: event.scope,
      });
    },
    recordOperationalHealthEvent: async (_adminClient, event) => {
      operationalEvents.push(event as Record<string, unknown>);
    },
    recordEdgeFunctionFailure: async (_adminClient, options) => {
      edgeFailures.push(options as Record<string, unknown>);
    },
    runMatchRpc: async () => {
      matchCalls += 1;
      return overrides.matchRow ?? {
        profile_id: "profile-1",
        user_id: "payee-1",
        display_name: "Marie",
        route_type: "phone_number",
        recipient_value: "0781234567",
        country_code: "RW",
        consent_version: "biopay-v1",
        score: 0.91,
      };
    },
    insertMatchEvent: async (_adminClient, event) => {
      matchEvents.push(event as Record<string, unknown>);
    },
  };

  return {
    deps,
    getState: () => ({
      rateEvents,
      matchEvents,
      operationalEvents,
      edgeFailures,
      matchCalls,
    }),
  };
}

Deno.test("biopay-match allows a request that is within limits", async () => {
  const { deps, getState } = buildDeps();
  const handler = createBiopayMatchHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();
  const state = getState();

  if (response.status != 200) {
    throw new Error(`Expected 200 response, received ${response.status}`);
  }

  if (payload.success != true || payload.data?.match != true) {
    throw new Error(`Unexpected payload: ${JSON.stringify(payload)}`);
  }

  if (state.matchCalls != 1) {
    throw new Error(
      `Expected one match RPC call, received ${state.matchCalls}`,
    );
  }

  if (state.matchEvents.length != 1) {
    throw new Error(
      `Expected one match event insert, received ${state.matchEvents.length}`,
    );
  }

  const outcomes = state.rateEvents.map((event) => event.outcome).sort();
  if (outcomes.join(",") != "match,match") {
    throw new Error(`Unexpected rate outcomes: ${outcomes.join(",")}`);
  }
});

Deno.test("biopay-match throttles requests that exceed the user attempt budget", async () => {
  const config = buildConfig();
  const { deps, getState } = buildDeps({
    userAttempts: config.userMaxAttempts,
  });
  const handler = createBiopayMatchHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();
  const state = getState();

  if (response.status != 429) {
    throw new Error(`Expected 429 response, received ${response.status}`);
  }

  if (
    payload.message !=
      "Too many BioPay match attempts. Please wait a moment before trying again."
  ) {
    throw new Error(`Unexpected payload: ${JSON.stringify(payload)}`);
  }

  if (state.matchCalls != 0) {
    throw new Error("Throttled requests must not reach the match RPC");
  }

  if (state.rateEvents[0]?.outcome != "blocked_user_rate_limit") {
    throw new Error(
      `Expected blocked_user_rate_limit, received ${
        state.rateEvents[0]?.outcome
      }`,
    );
  }
});

Deno.test("biopay-match blocks users with an active miss lockout", async () => {
  const { deps, getState } = buildDeps({
    latestLockoutAt: new Date(fixedNow.getTime() - 60_000).toISOString(),
  });
  const handler = createBiopayMatchHandler(deps);

  const response = await handler(buildRequest());
  const payload = await response.json();
  const state = getState();

  if (response.status != 423) {
    throw new Error(`Expected 423 response, received ${response.status}`);
  }

  if (
    payload.message !=
      "Too many failed BioPay match attempts. Please wait before trying again."
  ) {
    throw new Error(`Unexpected payload: ${JSON.stringify(payload)}`);
  }

  if (state.matchCalls != 0) {
    throw new Error("Locked-out requests must not reach the match RPC");
  }

  if (state.rateEvents[0]?.outcome != "blocked_lockout") {
    throw new Error(
      `Expected blocked_lockout, received ${state.rateEvents[0]?.outcome}`,
    );
  }
});
