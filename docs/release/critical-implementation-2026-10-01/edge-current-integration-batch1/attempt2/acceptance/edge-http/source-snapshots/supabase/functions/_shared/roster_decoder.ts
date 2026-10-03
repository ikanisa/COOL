import {
  boundedBody,
  objectValue,
  PublicError,
  SHA256,
  uuid,
} from "./production_contract.ts";
import { rosterSha256, type RosterSource } from "./roster_provenance.ts";

export const ROSTER_DECODER_POLICY = "collect-roster-decoder-v1";
export const ROSTER_DECODER_TOOLCHAIN = {
  python: "3.12",
  pillow: "12.3.0",
  pypdfium2: "5.2.0",
  pypdf: "6.19.0",
  openpyxl: "3.1.5",
  defusedxml: "0.7.1",
} as const;
export type RosterDecoded = {
  policy_version: string;
  source_sha256: string;
  source_size: number;
  derived_sha256: string | null;
  derived_content: string | null;
  frames: number;
  pages: number;
  pixels: number;
  expanded_bytes: number;
  receipt_sha256: string;
  decoder_build_sha256: string;
  toolchain: typeof ROSTER_DECODER_TOOLCHAIN;
};
const encoder = new TextEncoder();
async function key(secret: string): Promise<CryptoKey> {
  if (encoder.encode(secret).length < 32) {
    throw new PublicError("roster_decoder_unavailable", 503);
  }
  return await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}
async function mac(secret: string, bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.sign(
    "HMAC",
    await key(secret),
    bytes as BufferSource,
  );
  return [...new Uint8Array(hash)].map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}
function invalid(): never {
  throw new PublicError("roster_decoder_receipt_invalid", 503);
}
/** HMAC covers exact UTF-8 payload bytes, never a reparsed/canonicalized object. */
export async function decodeRosterSource(
  source: RosterSource,
  sourceHash: string,
  reservationId: string,
  config: {
    url: string | undefined;
    secret: string | undefined;
    buildSha256: string | undefined;
  },
  fetcher: typeof fetch = fetch,
): Promise<RosterDecoded> {
  if (
    !config.url || !config.secret || !config.buildSha256 ||
    !SHA256.test(config.buildSha256)
  ) {
    throw new PublicError("roster_decoder_unavailable", 503);
  }
  let endpoint: URL;
  try {
    endpoint = new URL(config.url);
  } catch {
    throw new PublicError("roster_decoder_unavailable", 503);
  }
  // Fixed operator-configured endpoint only; no user URL/redirect credentials.
  if (
    endpoint.username || endpoint.password || endpoint.search ||
    endpoint.hash || endpoint.pathname !== "/decode" ||
    (endpoint.protocol !== "https:" &&
      !(endpoint.protocol === "http:" &&
        ["127.0.0.1", "localhost", "roster-decoder"].includes(
          endpoint.hostname,
        )))
  ) {
    throw new PublicError("roster_decoder_unavailable", 503);
  }
  const nonce = crypto.randomUUID();
  const request = JSON.stringify({
    request_id: source.requestId,
    reservation_id: uuid(reservationId, "roster_budget_receipt_invalid"),
    source_sha256: sourceHash,
    mime: source.mime,
    kind: source.kind,
    content_base64: source.base64,
    policy_version: ROSTER_DECODER_POLICY,
    nonce,
    issued_at: Math.floor(Date.now() / 1000),
  });
  let response: Response;
  try {
    response = await fetcher(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Roster-HMAC ${await mac(
          config.secret,
          encoder.encode(request),
        )}`,
      },
      body: request,
      signal: AbortSignal.timeout(12_000),
      redirect: "error",
    });
  } catch {
    throw new PublicError("roster_decoder_unavailable", 503);
  }
  const raw = await boundedBody(response, 550_000);
  let envelope: Record<string, unknown>;
  try {
    envelope = objectValue(JSON.parse(raw));
  } catch {
    return invalid();
  }
  if (!response.ok) {
    const allowed = new Set([
      "roster_invalid_file",
      "roster_image_dimensions_exceeded",
      "roster_animation_limit",
      "roster_pdf_encrypted",
      "roster_pdf_object_limit",
      "roster_pdf_page_limit",
      "roster_pdf_active_content",
      "roster_pdf_expansion_limit",
      "roster_pdf_pixel_limit",
      "roster_xlsx_expansion_limit",
      "roster_xlsx_formula",
      "roster_xlsx_external_reference",
      "roster_xlsx_active_content",
      "roster_xlsx_header",
      "roster_xlsx_cell_type",
      "roster_xlsx_empty",
      "roster_decoder_resource_limit",
    ]);
    throw new PublicError(
      allowed.has(String(envelope.error))
        ? String(envelope.error)
        : "roster_decoder_unavailable",
      response.status === 429 ? 429 : 422,
    );
  }
  if (
    Object.keys(envelope).sort().join(",") !== "payload,signature" ||
    typeof envelope.payload !== "string" ||
    typeof envelope.signature !== "string" || !SHA256.test(envelope.signature)
  ) return invalid();
  const bytes = encoder.encode(envelope.payload);
  const signature = Uint8Array.from(
    envelope.signature.match(/../g)!,
    (s) => parseInt(s, 16),
  );
  if (
    !await crypto.subtle.verify(
      "HMAC",
      await key(config.secret),
      signature,
      bytes,
    )
  ) return invalid();
  let receipt: Record<string, unknown>;
  try {
    receipt = objectValue(JSON.parse(envelope.payload));
  } catch {
    return invalid();
  }
  const fields = [
    "contract_version",
    "request_id",
    "reservation_id",
    "nonce",
    "issued_at",
    "kind",
    "mime",
    "ok",
    "policy_version",
    "toolchain",
    "source_sha256",
    "source_size",
    "derived_sha256",
    "frames",
    "pages",
    "pixels",
    "expanded_bytes",
    "derived_content",
    "decoder_build_sha256",
  ];
  if (
    Object.keys(receipt).length !== fields.length ||
    fields.some((k) => !(k in receipt)) || receipt.contract_version !== 1 ||
    receipt.ok !== true ||
    receipt.request_id !== source.requestId ||
    receipt.reservation_id !== reservationId || receipt.nonce !== nonce ||
    !Number.isSafeInteger(receipt.issued_at) ||
    Math.abs(Date.now() / 1000 - Number(receipt.issued_at)) > 30 ||
    receipt.kind !== source.kind || receipt.mime !== source.mime ||
    receipt.policy_version !== ROSTER_DECODER_POLICY ||
    receipt.source_sha256 !== sourceHash ||
    receipt.source_size !== source.bytes.length ||
    receipt.decoder_build_sha256 !== config.buildSha256
  ) return invalid();
  const toolchain = objectValue(receipt.toolchain);
  if (
    Object.keys(toolchain).length !==
      Object.keys(ROSTER_DECODER_TOOLCHAIN).length ||
    Object.entries(ROSTER_DECODER_TOOLCHAIN).some(([k, v]) =>
      toolchain[k] !== v
    )
  ) return invalid();
  for (const k of ["frames", "pages", "pixels", "expanded_bytes"]) {
    if (!Number.isSafeInteger(receipt[k]) || Number(receipt[k]) < 0) {
      return invalid();
    }
  }
  if (
    Number(receipt.frames) > 20 || Number(receipt.pages) > 20 ||
    Number(receipt.pixels) > 40_000_000 ||
    Number(receipt.expanded_bytes) > 160_000_000 ||
    (source.kind === "image" &&
      (Number(receipt.frames) < 1 || receipt.pages !== 0 ||
        Number(receipt.pixels) < 1)) ||
    (source.kind === "pdf" &&
      (receipt.frames !== 0 || Number(receipt.pages) < 1 ||
        Number(receipt.pixels) < 1)) ||
    (source.kind === "xlsx" &&
      (receipt.frames !== 0 || receipt.pages !== 0 || receipt.pixels !== 0 ||
        Number(receipt.expanded_bytes) > 8 * 1024 * 1024))
  ) return invalid();
  if (source.kind === "xlsx") {
    if (
      typeof receipt.derived_content !== "string" ||
      encoder.encode(receipt.derived_content).length > 512_000 ||
      typeof receipt.derived_sha256 !== "string" ||
      !SHA256.test(receipt.derived_sha256) ||
      await rosterSha256(encoder.encode(receipt.derived_content)) !==
        receipt.derived_sha256
    ) return invalid();
    // Compare exact original-derived TSV, including ordering and every cell.
    // Never normalize away a substitution by comparing only candidate counts.
    if (receipt.derived_content !== source.content) {
      throw new PublicError("roster_xlsx_derived_mismatch", 422);
    }
  } else if (
    receipt.derived_content !== null || receipt.derived_sha256 !== null
  ) return invalid();
  return {
    ...receipt,
    receipt_sha256: await rosterSha256(bytes),
  } as RosterDecoded;
}
