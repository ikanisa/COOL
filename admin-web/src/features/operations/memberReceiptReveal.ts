/* eslint-disable no-control-regex -- Reject controls in operator input and untrusted sender metadata. */
import {z} from 'zod';
import type {AdminRequest} from '../../api/client';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {MemberReceipt} from './contracts';

const UUID = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const HASH = /^[a-f0-9]{64}$/;
export interface MemberReceiptRevealContext {
  request: AdminRequest; identity: PendingIdentity; financialModel: 'transaction_journals' | 'canonical_evidence_ledger'; receipt: MemberReceipt;
  canManage: boolean; enabled: boolean; isEnabled?: () => boolean; isCurrent: () => boolean; signal?: AbortSignal;
}
export interface RevealedMemberReceipt {sender: string; body: string; bodySha256: string;}
function fail(message: string): never {throw new Error(message);}
export function memberReceiptRevealReason(input: string) {
  const value = input.trim();
  if (value.length < 8 || value.length > 1000 || /[\x00-\x1f\x7f]/.test(value)) fail('Enter a reason of 8 to 1000 characters on one line.');
  return value;
}
function current(context: MemberReceiptRevealContext) {
  const expires = Date.parse(context.identity.expiresAt);
  if (!context.isCurrent() || context.financialModel !== 'transaction_journals' || context.receipt.source_kind === 'capture' || !context.canManage || context.identity.role === 'staff' ||
      !['payments.read', 'payments.manage'].every((permission) => context.identity.permissions.includes(permission)) || !Number.isFinite(expires) || expires <= Date.now() ||
      !UUID.test(context.receipt.id) || !HASH.test(context.receipt.body_sha256)) fail('Member receipt access is unavailable to your current account.');
}
function enabled(context: MemberReceiptRevealContext) {current(context); if (!context.enabled || context.isEnabled && !context.isEnabled()) fail('Member receipt access is not enabled for this workspace.');}
/** Each GET is separately audited and has no operation lookup; it is never retried automatically. */
export async function revealMemberReceipt(context: MemberReceiptRevealContext, reason: string): Promise<RevealedMemberReceipt> {
  enabled(context); const reviewedReason = memberReceiptRevealReason(reason);
  const body = await context.request(`gateway/receipts/${context.receipt.id}/content`, {reviewReason: reviewedReason, ...(context.signal ? {signal: context.signal} : {})}); enabled(context);
  const data = z.object({submission_id: z.string().regex(UUID), raw_sender: z.string(), raw_body: z.string(), body_sha256: z.string().regex(HASH), evidence_level: z.literal('member_submitted')}).strict().parse(body);
  if (data.submission_id !== context.receipt.id || data.body_sha256 !== context.receipt.body_sha256 || !data.raw_sender.trim() || data.raw_sender.length > 80 || /[\x00-\x1f\x7f]/.test(data.raw_sender) ||
      !data.raw_body || data.raw_body.length > 16000 || !globalThis.crypto?.subtle) fail('The receipt content could not be verified.');
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(data.raw_body));
  const hash = [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, '0')).join(''); enabled(context);
  if (hash !== data.body_sha256) fail('The receipt content could not be verified.');
  return {sender: data.raw_sender, body: data.raw_body, bodySha256: hash};
}
