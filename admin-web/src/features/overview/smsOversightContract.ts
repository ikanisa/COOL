import {isObject, isSafeCount} from '../core/contracts';

export const assistedLabels = {queued: 'Queued receipts', claimed: 'Claimed receipts', send_started: 'Send started', uncertain: 'Send outcome unknown'} as const;
export const nativeLabels = {pending: 'Pending', retrying: 'Retrying', blocked: 'Blocked', unmatched: 'Unmatched', posted: 'Internally credited'} as const;
export const payerLabels = {pending: 'Pending', gateway_accepted: 'Gateway accepted', sent: 'Sent', delivered: 'Reported delivered', failed: 'Failed', unknown: 'Outcome unknown', suppressed: 'Suppressed'} as const;
type CountKey = keyof typeof assistedLabels;
type NativeCountKey = keyof typeof nativeLabels;
type PayerCountKey = keyof typeof payerLabels;
export interface Oversight {
  checkedAt: string;
  counts: Record<CountKey, number>;
  oldestQueuedSeconds?: number | null;
  oldestUnobservedSendSeconds?: number | null;
  native: {counts: Record<NativeCountKey, number>; oldestPendingSeconds: number | null} | null;
  payer: Record<PayerCountKey, number> | null;
  managed: string;
  parsing: string;
  ledger: string;
}
function invalid(): never {throw new Error('The SMS oversight sample could not be verified.');}

function age(value: unknown): number | null {
  if (value === null || isSafeCount(value)) return value;
  return invalid();
}

function parseCounts<Key extends string>(data: Record<string, unknown>, keys: readonly Key[]): Record<Key, number> {
  const counts = {} as Record<Key, number>;
  for (const key of keys) {
    if (!isSafeCount(data[key])) return invalid();
    counts[key] = data[key];
  }
  return counts;
}

function parseNativeQueue(value: unknown): Oversight['native'] {
  if (value === undefined) return null;
  const keys = Object.keys(nativeLabels) as NativeCountKey[];
  if (!isObject(value) || Object.keys(value).length !== keys.length + 1) return invalid();
  return {counts: parseCounts(value, keys), oldestPendingSeconds: age(value.oldest_pending_seconds)};
}

function parsePayerQueue(value: unknown): Oversight['payer'] {
  if (value === undefined) return null;
  const keys = Object.keys(payerLabels) as PayerCountKey[];
  if (!isObject(value) || Object.keys(value).length !== keys.length) return invalid();
  return parseCounts(value, keys);
}

export function parseSmsOversight(value: unknown): Oversight {
  if (!isObject(value) || value.contract_version !== 1 || value.scope !== 'admin_operational_health' ||
      value.metrics_scope !== 'all_retained_rows' || value.worker_heartbeat !== 'not_recorded' || value.external_services_checked !== false ||
      typeof value.checked_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value.checked_at) ||
      !Number.isFinite(Date.parse(value.checked_at)) || new Date(value.checked_at).toISOString().slice(0, 19) !== value.checked_at.slice(0, 19) ||
      !isObject(value.queues) || !isObject(value.queues.assisted_sms) || value.queues.assisted_sms.automatic_retry !== false ||
      (value.configuration !== undefined && value.configuration !== null && !isObject(value.configuration))) return invalid();
  const sms = value.queues.assisted_sms, configuration = isObject(value.configuration) ? value.configuration : {};
  const counts = parseCounts(sms, Object.keys(assistedLabels) as CountKey[]);
  function setting(key: string, allowed: string[]): string {
    const result = configuration[key];
    if (result === null || result === undefined) return 'unknown';
    if (typeof result !== 'string' || !allowed.includes(result)) return invalid();
    return result;
  }
  return {
    checkedAt: value.checked_at, counts,
    oldestQueuedSeconds: sms.oldest_queued_seconds === undefined ? undefined : age(sms.oldest_queued_seconds),
    oldestUnobservedSendSeconds: sms.oldest_unobserved_send_seconds === undefined ? undefined : age(sms.oldest_unobserved_send_seconds),
    native: parseNativeQueue(value.queues.burimunsi_sms), payer: parsePayerQueue(value.queues.burimunsi_payer_sms), managed: setting('momo_processing', ['enabled', 'paused']),
    parsing: setting('native_auto_processing', ['enabled', 'disabled']), ledger: setting('native_sms_ledger', ['enabled', 'disabled']),
  };
}
