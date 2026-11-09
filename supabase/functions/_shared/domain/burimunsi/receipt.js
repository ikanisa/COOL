import {BuriError, requireThat} from './errors.js';
import {normalizePhone, wholeRwf, providerTime, canonicalJson, sha256} from './values.js';
export const PARSER_VERSION = 'burimunsi.mmoney.en-ftid.v1';
// This grammar supports the owner-supplied English FT Id format ONLY.
// New carrier/language/reversal variants require approved fixtures, not fuzzy guessing.
const GRAMMAR = /^You have received ([0-9,]+) RWF from ([^\r\n()]{1,160}) \(([^\r\n()]{1,40})\) at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\. Balance: ([0-9,]+) RWF\. FT Id: ([0-9]{1,40})\.$/;
const SECRET = /\b(?:OTP|one[ -]time|verification[ -]code|passcode|password|PIN[ -]code)\b/i;
export function parseReceipt(source, profile) {
  requireThat(profile && profile.version && Number.isInteger(profile.offsetMinutes) && Array.isArray(profile.senders) && profile.senders.length > 0, 'provider_profile_required', 503);
  requireThat(source && source.complete === true, 'incomplete_receipt');
  requireThat(typeof source.sender === 'string' && profile.senders.some(s => typeof s === 'string' && s.toLowerCase() === source.sender.toLowerCase()), 'unsupported_sender');
  requireThat(typeof source.body === 'string' && new TextEncoder().encode(source.body).length <= 8192 && !/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/.test(source.body), 'unsupported_receipt');
  requireThat(!SECRET.test(source.body), 'secret_bearing_message');
  const m = GRAMMAR.exec(source.body);
  requireThat(m, 'unsupported_receipt');
  const [, amountRaw, name, phoneRaw, atRaw, walletRaw, ftId] = m;
  requireThat(name === name.trim() && name.length > 0 && !name.includes('FT Id:'), 'unsupported_receipt');
  let fullPhone = null;
  if (!/^\*{3,12}[0-9]{1,4}$/.test(phoneRaw)) fullPhone = normalizePhone(phoneRaw);
  return Object.freeze({parserVersion:PARSER_VERSION, profileVersion:profile.version,
    provider:'mtn_momo', eventKind:'incoming_receipt', currency:'RWF',
    amountRwf:wholeRwf(amountRaw), amountRaw, payerNameRaw:name,
    payerPhoneRaw:phoneRaw, fullPayerPhone:fullPhone, atRaw,
    at:providerTime(atRaw,profile.offsetMinutes), walletBalanceRwf:wholeRwf(walletRaw,{positive:false}),
    walletBalanceRaw:walletRaw, ftId, feeRwf:null, paymentReferenceRaw:null,
    rawBody:source.body, rawSender:source.sender});
}
/** Used BEFORE retention; returns no body, name or code when rejected. */
export function classifyCapture(source, profile, binding) {
  if (!binding || !binding.active || !Number.isInteger(binding.subscriptionId) || binding.subscriptionId < 0 ||
      source.subscriptionId !== binding.subscriptionId || !binding.installationId || !binding.version) {
    return {retain:false,code:'receiving_route_unresolved'};
  }
  try { parseReceipt(source,profile); return {retain:true,code:'incoming_receipt'}; }
  catch (e) { if (e instanceof BuriError) return {retain:false,code:e.code}; throw e; }
}
export function transactionKey(receivingAccountId, receipt) {
  requireThat(typeof receivingAccountId === 'string' && receivingAccountId.length > 0 && receivingAccountId.length <= 128, 'receiving_account_required');
  return canonicalJson([receipt.provider,receivingAccountId,receipt.eventKind,receipt.ftId]);
}
export async function receiptFingerprint(receipt) {
  // Different observations of one reference are retained; differing facts conflict.
  return sha256(canonicalJson([receipt.amountRwf,receipt.currency,receipt.payerNameRaw,
    receipt.payerPhoneRaw,receipt.at,receipt.eventKind,receipt.ftId]));
}
