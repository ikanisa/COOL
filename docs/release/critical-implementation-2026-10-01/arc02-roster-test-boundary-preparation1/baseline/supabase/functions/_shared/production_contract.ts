/** Boundary errors contain developer-authored codes, never user or provider values. */
export class PublicError extends Error {
  constructor(readonly code: string, readonly status = 400) { super(code); this.name = 'PublicError'; }
}
export const RECEIPT_CONTRACT_VERSION = 2;
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const SHA256 = /^[a-f0-9]{64}$/;
const encoder = new TextEncoder();
export function objectValue(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new PublicError('invalid_payload');
  return value as Record<string, unknown>;
}
export function boundedText(value: unknown, code: string, maximum: number, trim = true): string {
  if (typeof value !== 'string' || !value.trim() || encoder.encode(value).length > maximum) throw new PublicError(code);
  return trim ? value.trim() : value;
}
export function uuid(value: unknown, code: string): string {
  if (typeof value !== 'string' || !UUID.test(value)) throw new PublicError(code);
  return value.toLowerCase();
}
export async function boundedBody(message: Request | Response, maximum: number): Promise<string> {
  if (!Number.isSafeInteger(maximum) || maximum < 1) throw new Error('Invalid configured bound');
  const length = message.headers.get('content-length');
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > maximum)) throw new PublicError('payload_too_large', 413);
  if (!message.body) return '';
  const reader = message.body.getReader(); const parts: Uint8Array[] = []; let count = 0;
  try {
    for (;;) {
      const next = await reader.read(); if (next.done) break;
      count += next.value.byteLength;
      if (count > maximum) { await reader.cancel(); throw new PublicError('payload_too_large', 413); }
      parts.push(next.value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(count); let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.length; }
  try { return new TextDecoder('utf-8', {fatal: true}).decode(bytes); }
  catch { throw new PublicError('invalid_utf8'); }
}
export async function boundedJson(request: Request, maximum = 16_384): Promise<Record<string, unknown>> {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type') ?? '')) throw new PublicError('json_required', 415);
  try { return objectValue(JSON.parse(await boundedBody(request, maximum))); }
  catch (error) { if (error instanceof PublicError) throw error; throw new PublicError('invalid_json'); }
}
export function publicFailure(error: unknown): {error: string; status: number} {
  if (error instanceof PublicError) return {error: error.code, status: error.status};
  const message = error instanceof Error ? error.message : '';
  if (['Authentication required','Internal function authorization failed','Unauthorized'].includes(message)) return {error:'authentication_required',status:401};
  return {error:'service_unavailable',status:503};
}
export async function fetchJson(url: string, init: RequestInit, milliseconds = 8_000, maxBytes = 65_536): Promise<{ok: boolean; status: number; data: unknown}> {
  const response = await fetch(url, {...init, signal: AbortSignal.timeout(milliseconds), redirect:'error'});
  const raw = await boundedBody(response, maxBytes);
  let data: unknown = null;
  if (raw) { try { data = JSON.parse(raw); } catch { throw new PublicError('invalid_provider_response',502); } }
  return {ok:response.ok,status:response.status,data};
}
export function requireReceiptContract(value: unknown): void {
  if (value !== RECEIPT_CONTRACT_VERSION) throw new PublicError('receipt_contract_unavailable',503);
}
export type ReceiptAck = {contract_version:2;stored:true;raw_sms_id:string;client_envelope_id:string;owner_user_id:string;body_sha256:string};
export function validateReceiptAck(value: unknown, owner: string, envelope: string, bodyHash: string): ReceiptAck {
  const r = objectValue(value);
  if (r.contract_version !== 2 || r.stored !== true || typeof r.raw_sms_id !== 'string' || !UUID.test(r.raw_sms_id) ||
      r.owner_user_id !== owner || r.client_envelope_id !== envelope || r.body_sha256 !== bodyHash || !SHA256.test(bodyHash)) throw new PublicError('durable_receipt_not_verified',503);
  return {contract_version:2,stored:true,raw_sms_id:r.raw_sms_id.toLowerCase(),client_envelope_id:envelope,owner_user_id:owner,body_sha256:bodyHash};
}
export function zonedInstant(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const s = boundedText(value,'invalid_receipt_time',40);
  if (!/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(s) || !Number.isFinite(Date.parse(s))) throw new PublicError('invalid_receipt_time');
  const parts=s.slice(0,19).split(/[-T :]/).map(Number);
  const [y,m,d,h,min,sec]=parts;
  const days = new Date(Date.UTC(y,m,0)).getUTCDate();
  if (y<100 || m<1 || m>12 || d<1 || d>days || h>23 || min>59 || sec>59) throw new PublicError('invalid_receipt_time');
  return s;
}
