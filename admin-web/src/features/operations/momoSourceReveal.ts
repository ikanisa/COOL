/* eslint-disable no-control-regex -- Reject controls in operator input and untrusted sender metadata. */
import { z } from 'zod';
import type { AdminRequest } from '../../api/client';
import type { PendingIdentity } from '../core';
import type { MomoSourceJob } from './momoContracts';
import {parseMomoSourceCandidate, type MomoExtraction} from './momoSourceActions';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
export interface MomoSourceRevealContext {
  request: AdminRequest; identity: PendingIdentity; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; source: MomoSourceJob;
  enabled: boolean; isEnabled?: () => boolean; isCurrent: () => boolean; verifyFresh: () => Promise<boolean>; signal?: AbortSignal;
}
export interface MomoRevealedSource {sender: string; body: string; bodySha256: string; candidate?: MomoExtraction;}
function fail(message: string): never {throw new Error(message);}
export function momoRevealReason(input: string): string {
  const value = input.trim();
  if (value.length < 8 || value.length > 500 || /[\x00-\x1f\x7f]/.test(value)) fail('Enter a reason of 8 to 500 characters on one line.');
  return value;
}
function current(context: MomoSourceRevealContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'canonical_evidence_ledger' || !['sms.read', 'sms.reveal'].every((permission) => context.identity.permissions.includes(permission)) ||
      !Number.isFinite(expires) || expires <= Date.now() || !UUID.test(context.source.raw_sms_id) || !context.source.body_sha256 || !HASH.test(context.source.body_sha256)) fail('Source access is unavailable to your current account.');
}
function enabled(context: MomoSourceRevealContext) {
  current(context);
  if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Source access is not enabled for the current workspace.');
}
/** This audited GET has no idempotency or receipt lookup. Never retry it automatically. */
export async function revealMomoSource(context: MomoSourceRevealContext, reason: string): Promise<MomoRevealedSource> {
  enabled(context); const reviewedReason = momoRevealReason(reason);
  if (!await context.verifyFresh()) fail('Complete current verification before viewing this source.');
  enabled(context);
  const body = await context.request(`momo/sources/${context.source.raw_sms_id}/content`, {reviewReason: reviewedReason, ...(context.signal ? {signal: context.signal} : {})});
  enabled(context);
  const data = z.object({raw_sms_id: z.string().regex(UUID), body_sha256: z.string().regex(HASH), raw_sender: z.string(), raw_body: z.string(), latest_attempt: z.unknown()}).strict().parse(body);
  if (!Object.hasOwn(body, 'latest_attempt') || data.raw_sms_id !== context.source.raw_sms_id || data.body_sha256 !== context.source.body_sha256 ||
      !data.raw_sender.trim() || data.raw_sender.length > 96 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(data.raw_sender) ||
      !data.raw_body || data.raw_body.includes('\0') || new TextEncoder().encode(data.raw_body).length > 16384 || !globalThis.crypto?.subtle) fail('The source content could not be verified.');
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(data.raw_body));
  const hash = [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  enabled(context);
  if (hash !== data.body_sha256) fail('The source content could not be verified.');
  const latest = data.latest_attempt;
  const candidate = latest && typeof latest === 'object' && !Array.isArray(latest) ? parseMomoSourceCandidate((latest as Record<string, unknown>).output_json) : null;
  return {sender: data.raw_sender, body: data.raw_body, bodySha256: hash, ...(candidate ? {candidate} : {})};
}
