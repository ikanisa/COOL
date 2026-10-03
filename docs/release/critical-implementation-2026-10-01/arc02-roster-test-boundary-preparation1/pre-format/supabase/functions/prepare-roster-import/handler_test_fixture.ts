import { assertEquals } from "../_shared/test_assert.ts";
import { SYNTHETIC_ROSTER_AI_CONFIGURATION } from "../_shared/roster_ai_dispatch_test_fixture.ts";
import { normalizeRosterCandidates } from "../_shared/roster_import.ts";
import { PublicError } from "../_shared/production_contract.ts";
import { rosterSha256 } from "../_shared/roster_provenance.ts";
import {
  createRosterImportHandler,
  type RosterHandlerDependencies,
} from "./handler.ts";

const ACTOR = "11111111-1111-4111-8111-111111111111";
const SESSION = "22222222-2222-4222-8222-222222222222";
const REQUEST = "33333333-3333-4333-8333-333333333333";
const IMPORT = "44444444-4444-4444-8444-444444444444";
const REVISION = "55555555-5555-4555-8555-555555555555";
const EXTRACTION = "66666666-6666-4666-8666-666666666666";
const RESERVATION = "77777777-7777-4777-8777-777777777777";
const DECODER_SECRET = "local-synthetic-decoder-signing-key-only-20260930";
const EXPIRY = "2099-01-01T00:00:00Z";
const PNG =
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAFElEQVR4nGOUS+lhYGBgYgADKAUAE/ABFCFAuesAAAAASUVORK5CYII=";
const TEXT =
  "member_name,momo_name,momo_number\nNiyonzima Élodie,Élodie Niyonzima,0788123456\n";
const encoder = new TextEncoder();
function base64(value: string | Uint8Array): string {
  return btoa(
    String.fromCharCode(
      ...(typeof value === "string" ? encoder.encode(value) : value),
    ),
  );
}
function token(patch: Record<string, unknown> = {}): string {
  return `Bearer e30.${
    base64(
      JSON.stringify({
        sub: ACTOR,
        session_id: SESSION,
        role: "authenticated",
        ...patch,
      }),
    ).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")
  }.synthetic`;
}
function pasted(patch: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    contract_version: 1,
    request_id: REQUEST,
    source_type: "text",
    content: TEXT,
    ...patch,
  };
}
function ai(patch: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    contract_version: 1,
    request_id: REQUEST,
    source_type: "image",
    filename: "fixture.png",
    mime_type: "image/png",
    content_base64: PNG,
    ai_consent: true,
    consent_version: "roster-ai-extraction-v1",
    ...patch,
  };
}
function request(
  payload: Record<string, unknown> = pasted(),
  auth = token(),
  headers: Record<string, string> = {},
): Request {
  return new Request("https://edge.test/prepare-roster-import", {
    method: "POST",
    headers: {
      authorization: auth,
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify(payload),
  });
}
function provider(): Record<string, unknown> {
  return {
    id: "resp_fixture",
    object: "response",
    status: "completed",
    error: null,
    incomplete_details: null,
    output: [{
      id: "msg_fixture",
      type: "message",
      role: "assistant",
      status: "completed",
      content: [{
        type: "output_text",
        annotations: [],
        text: JSON.stringify({
          rows: [{
            source_row: 1,
            member_name: "Niyonzima Élodie",
            momo_name: "Élodie Niyonzima",
            momo_number: "0788123456",
            confidence: 0.96,
          }],
        }),
      }],
    }],
  };
}
function assert(value: unknown): asserts value {
  if (!value) throw new Error("Assertion failed");
}
function rejects(run: () => unknown, code: string): void {
  try {
    run();
  } catch (error) {
    assert(error instanceof PublicError);
    assertEquals(error.code, code);
    return;
  }
  throw new Error(`Expected ${code}`);
}
type Call = { name: string; args: Record<string, unknown> };
function fixturePromise<T>(body: () => T): Promise<T> {
  try {
    return Promise.resolve(body());
  } catch (error) {
    return Promise.reject(error);
  }
}
function fixture() {
  const calls: Call[] = [], events: string[] = [];
  let original: Record<string, unknown> = {};
  let cached: Record<string, unknown> | null = null;
  let decoderSourceHash = "", decoderDerivedHash: string | null = null;
  const state = {
    sourcePatch: {} as Record<string, unknown>,
    previewPatch: {} as Record<string, unknown>,
    sourceError: null as { message: string; code: string } | null,
    failError: false,
    completeError: false,
    completeSqlInvalid: false,
    fetchError: null as Error | null,
    providerResponse: () => new Response(JSON.stringify(provider())),
    authError: false,
    apiKey: "synthetic-key",
    replay: false,
    configurationPatch: {} as Record<string, unknown>,
  };
  const deps: RosterHandlerDependencies = {
    authenticate: () =>
      fixturePromise(() => {
        events.push("authenticate");
        if (state.authError) throw new Error("Authentication required");
        return { id: ACTOR };
      }),
    configuration: () => ({
      ...SYNTHETIC_ROSTER_AI_CONFIGURATION,
      model: "fixture-model",
      apiKey: state.apiKey,
      decoderUrl: "http://localhost/decode",
      decoderSecret: DECODER_SECRET,
      decoderBuildSha256: "d".repeat(64),
      ...state.configurationPatch,
    }),
    rpc: (name, args) =>
      fixturePromise(() => {
        if (name === "reserve_roster_resources") {
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              reservation_id: RESERVATION,
              request_id: args.p_request_id,
              actor_id: args.p_actor_id,
              session_id: args.p_session_id,
              source_sha256: args.p_source_sha256,
              state: state.replay ? "finished" : "reserved",
              replayed: state.replay,
              expires_at: EXPIRY,
            },
          };
        }
        if (name === "verify_roster_source_integrity") {
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              reservation_id: RESERVATION,
              source_sha256: decoderSourceHash,
              derived_sha256: decoderDerivedHash,
              decoder_receipt_sha256: args.p_decoder_receipt_sha256,
              verified: true,
            },
          };
        }
        if (name === "finish_roster_resources") {
          return {
            error: null,
            data: {
              contract_version: 1,
              ok: true,
              reservation_id: RESERVATION,
              outcome: args.p_outcome,
              charged: true,
            },
          };
        }
        events.push(name);
        calls.push({ name, args });
        if (name === "create_roster_import_source") {
          if (state.sourceError) {
            return { data: null, error: state.sourceError };
          }
          original = args;
          return {
            data: {
              contract_version: 1,
              ok: true,
              request_id: args.p_request_id,
              import_id: IMPORT,
              source_sha256: args.p_original_sha256,
              source_size: args.p_original_size,
              source_kind: args.p_source_kind,
              extraction_id: args.p_ai_consent ? EXTRACTION : null,
              expires_at: EXPIRY,
              derived_sha256: args.p_derived_sha256,
              derived_assurance: args.p_source_kind === "xlsx"
                ? "client_derived_tsv"
                : null,
              state: state.replay ? "preview_ready" : "awaiting_preview",
              replayed: state.replay,
              completed_preview: state.replay ? cached : null,
              error_code: null,
              ...state.sourcePatch,
            },
            error: null,
          };
        }
        if (name === "fail_roster_import_preview") {
          return {
            data: {
              contract_version: 1,
              ok: true,
              import_id: IMPORT,
              state: "failed",
              error_code: args.p_error_code,
              replayed: false,
            },
            error: state.failError ? { message: "private failure" } : null,
          };
        }
        assertEquals(name, "complete_roster_import_preview");
        if (state.completeSqlInvalid) {
          return {
            data: null,
            error: { code: "22023", message: "private SQL detail" },
          };
        }
        if (state.completeError) {
          throw new Error("private transport failure after possible commit");
        }
        const preview = normalizeRosterCandidates(args.p_candidates);
        cached = {
          contract_version: 1,
          ok: true,
          import_id: IMPORT,
          source_sha256: original.p_original_sha256,
          source_kind: original.p_source_kind,
          source_receipt: {
            request_id: original.p_request_id,
            source_size: original.p_original_size,
            client_filename: original.p_client_filename,
            declared_mime: original.p_declared_mime,
            detected_type: original.p_detected_type,
            derived_sha256: original.p_derived_sha256,
            derived_assurance: original.p_source_kind === "xlsx"
              ? "client_derived_tsv"
              : null,
            extraction_id: original.p_ai_consent ? EXTRACTION : null,
            ai_consent: original.p_ai_consent,
            consent_version: original.p_consent_version,
            parser_version: "collect-roster-parser-v1",
            schema_version: "collect-roster-rows-v1",
          },
          revision_id: REVISION,
          parent_revision_id: null,
          revision_number: 1,
          reviewed_rows_sha256: "a".repeat(64),
          ...preview,
          can_submit: false,
          requires_human_review: true,
          processing_method: original.p_ai_consent
            ? "openai_structured_extraction"
            : "deterministic",
          model: original.p_ai_consent ? "fixture-model" : null,
          expires_at: EXPIRY,
          ...state.previewPatch,
        };
        return { data: cached, error: null };
      }),
    // This fixture simulates an independently signed decoder receipt. Actual
    // codec/workbook behavior is exercised against the Linux sandbox separately.
    decoderFetch: async (_url, init) => {
      const input = JSON.parse(String(init?.body));
      decoderSourceHash = input.source_sha256;
      const content = input.kind === "xlsx" ? TEXT : null;
      decoderDerivedHash = content === null
        ? null
        : await rosterSha256(encoder.encode(content));
      const payload = JSON.stringify({
        ...Object.fromEntries(
          ["request_id", "reservation_id", "nonce", "kind", "mime"].map(
            (k) => [k, input[k]],
          ),
        ),
        contract_version: 1,
        issued_at: Math.floor(Date.now() / 1000),
        ok: true,
        policy_version: "collect-roster-decoder-v1",
        decoder_build_sha256: "d".repeat(64),
        toolchain: {
          python: "3.12",
          pillow: "12.3.0",
          pypdfium2: "5.2.0",
          pypdf: "6.19.0",
          openpyxl: "3.1.5",
          defusedxml: "0.7.1",
        },
        source_sha256: input.source_sha256,
        source_size: atob(input.content_base64).length,
        derived_sha256: decoderDerivedHash,
        derived_content: content,
        frames: input.kind === "image" ? 1 : 0,
        pages: input.kind === "pdf" ? 1 : 0,
        pixels: input.kind === "xlsx" ? 0 : 6,
        expanded_bytes: 24,
      });
      const key = await crypto.subtle.importKey(
        "raw",
        encoder.encode(DECODER_SECRET),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      );
      const signature = [
        ...new Uint8Array(
          await crypto.subtle.sign("HMAC", key, encoder.encode(payload)),
        ),
      ].map((v) => v.toString(16).padStart(2, "0")).join("");
      return new Response(JSON.stringify({ payload, signature }));
    },
    fetch: (_url, init) =>
      fixturePromise(() => {
        events.push("provider");
        assertEquals(calls[0].name, "create_roster_import_source");
        assertEquals(calls[0].args.p_ai_consent, true);
        assertEquals(
          calls[0].args.p_consent_version,
          "roster-ai-extraction-v1",
        );
        assertEquals(init?.redirect, "error");
        assert(init?.signal);
        const body = JSON.parse(String(init?.body));
        assertEquals(body.store, false);
        assertEquals(body.tools, undefined);
        if (state.fetchError) throw state.fetchError;
        return state.providerResponse();
      }),
  };
  return {
    state,
    calls,
    events,
    deps,
    handler: createRosterImportHandler(deps),
  };
}
async function errorResponse(
  response: Response,
  status: number,
  error: string,
) {
  assertEquals(response.status, status);
  assertEquals(await response.json(), { error });
}

export {
  ACTOR,
  ai,
  assert,
  base64,
  type Call,
  encoder,
  errorResponse,
  EXPIRY,
  fixture,
  IMPORT,
  pasted,
  PNG,
  provider,
  rejects,
  request,
  REQUEST,
  REVISION,
  SESSION,
  TEXT,
  token,
};
