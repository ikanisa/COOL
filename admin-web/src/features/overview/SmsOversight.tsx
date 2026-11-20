import {useEffect, useState} from 'react';
import type {AdminRequest} from '../../api/client';
import {Button, Card, ErrorState, LoadingState} from '../../ui';
import {isObject, isSafeCount} from '../core/contracts';

const assistedLabels = {queued: 'Queued receipts', claimed: 'Claimed receipts', send_started: 'Send started', uncertain: 'Send outcome unknown'} as const;
const nativeLabels = {pending: 'Pending', retrying: 'Retrying', blocked: 'Blocked', unmatched: 'Unmatched', posted: 'Internally credited'} as const;
const payerLabels = {pending: 'Pending', gateway_accepted: 'Gateway accepted', sent: 'Sent', delivered: 'Reported delivered', failed: 'Failed', unknown: 'Outcome unknown', suppressed: 'Suppressed'} as const;
type CountKey = keyof typeof assistedLabels;
type NativeCountKey = keyof typeof nativeLabels;
type PayerCountKey = keyof typeof payerLabels;
interface Oversight {
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

function formatAge(seconds: number | null): string {
  if (seconds === null) return 'None recorded';
  if (seconds < 60) return `${seconds} s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} h ${Math.floor((seconds % 3600) / 60)} min`;
  return `${Math.floor(seconds / 86400)} d ${Math.floor((seconds % 86400) / 3600)} h`;
}

function parseNativeQueue(value: unknown): Oversight['native'] {
  if (value === undefined) return null;
  const keys = Object.keys(nativeLabels) as NativeCountKey[];
  if (!isObject(value) || Object.keys(value).length !== keys.length + 1) return invalid();
  const counts = {} as Record<NativeCountKey, number>;
  for (const key of keys) {
    if (!isSafeCount(value[key])) return invalid();
    counts[key] = value[key];
  }
  return {counts, oldestPendingSeconds: age(value.oldest_pending_seconds)};
}

function parsePayerQueue(value: unknown): Oversight['payer'] {
  if (value === undefined) return null;
  const keys = Object.keys(payerLabels) as PayerCountKey[];
  if (!isObject(value) || Object.keys(value).length !== keys.length) return invalid();
  const counts = {} as Record<PayerCountKey, number>;
  for (const key of keys) {
    if (!isSafeCount(value[key])) return invalid();
    counts[key] = value[key];
  }
  return counts;
}

export function parseSmsOversight(value: unknown): Oversight {
  if (!isObject(value) || value.contract_version !== 1 || value.scope !== 'admin_operational_health' ||
      value.metrics_scope !== 'all_retained_rows' || value.worker_heartbeat !== 'not_recorded' || value.external_services_checked !== false ||
      typeof value.checked_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value.checked_at) ||
      !Number.isFinite(Date.parse(value.checked_at)) || new Date(value.checked_at).toISOString().slice(0, 19) !== value.checked_at.slice(0, 19) ||
      !isObject(value.queues) || !isObject(value.queues.assisted_sms) || value.queues.assisted_sms.automatic_retry !== false ||
      (value.configuration !== undefined && value.configuration !== null && !isObject(value.configuration))) return invalid();
  const sms = value.queues.assisted_sms, configuration = isObject(value.configuration) ? value.configuration : {};
  const counts = {} as Record<CountKey, number>;
  for (const key of Object.keys(assistedLabels) as CountKey[]) {
    if (!isSafeCount(sms[key])) return invalid();
    counts[key] = sms[key];
  }
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

/** Metadata only: a stale sample never presents counts as current. */
export function SmsOversight({request, permissions, authorityKey}: {request: AdminRequest; permissions: readonly string[]; authorityKey: string}) {
  const allowed = permissions.includes('system_health.read');
  const [revision, setRevision] = useState(0), [now, setNow] = useState(Date.now);
  const [state, setState] = useState<{scope: string; sample: Oversight | null; error: boolean} | null>(null);
  const scope = JSON.stringify([authorityKey, revision]); const current = state?.scope === scope ? state : null;
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController();
    void request('oversight/health', {authenticated: true, expectedStatus: 200, signal: controller.signal})
      .then(parseSmsOversight)
      .then(sample => {if (!controller.signal.aborted) setState({scope, sample, error: false});})
      .catch(() => {if (!controller.signal.aborted) setState({scope, sample: null, error: true});});
    return () => controller.abort();
  }, [allowed, request, scope]);
  useEffect(() => {
    if (!allowed) return;
    const timer = window.setInterval(() => setNow(Date.now()), 5000);
    return () => window.clearInterval(timer);
  }, [allowed]);
  if (!allowed) return null;
  const checked = current?.sample ? Date.parse(current.sample.checkedAt) : NaN;
  const fresh = Number.isFinite(checked) && now >= checked - 5000 && now < checked + 60000;
  return <Card className="overview-oversight"><div className="overview-oversight-heading"><h2>SMS oversight</h2>
    <Button icon="refresh" onClick={() => {setNow(Date.now()); setRevision(value => value + 1);}}>Refresh SMS oversight</Button></div>
    {!current ? <LoadingState label="Loading SMS oversight" /> : current.error ?
      <ErrorState message="SMS oversight could not be verified." onRetry={() => setRevision(value => value + 1)} /> : current.sample && <>
        <p className="overview-measured">Checked {new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'}).format(new Date(current.sample.checkedAt))} Kigali</p>
        {!fresh ? <p role="status">Sample expired. Refresh for current counts.</p> : <>
          <section aria-label="BuriMunsi SMS processing" className="overview-oversight-section">
            <h3>BuriMunsi SMS processing</h3>
            {current.sample.native ? <>
              <dl className="overview-oversight-counts">{(Object.keys(nativeLabels) as NativeCountKey[]).map(key => <div key={key}><dt>{nativeLabels[key]}</dt><dd>{current.sample!.native!.counts[key].toLocaleString('en-US')}</dd></div>)}</dl>
              <p>Oldest pending work at check: {formatAge(current.sample.native.oldestPendingSeconds)}. Internal credits measure ledger postings. Provider settlement is recorded separately.</p>
            </> : <p role="status">BuriMunsi queue measurements are unavailable.</p>}
          </section>
          {current.sample.payer && <section aria-label="BuriMunsi payer receipts" className="overview-oversight-section">
            <h3>BuriMunsi payer receipts</h3>
            <dl className="overview-oversight-counts">{(Object.keys(payerLabels) as PayerCountKey[]).map(key => <div key={key}><dt>{payerLabels[key]}</dt><dd>{current.sample!.payer![key].toLocaleString('en-US')}</dd></div>)}</dl>
            <p>Recorded gateway observations for approved collections.</p>
          </section>}
          <section aria-label="Assisted receipt delivery" className="overview-oversight-section">
            <h3>Assisted receipt delivery</h3>
            <dl className="overview-oversight-counts">{(Object.keys(assistedLabels) as CountKey[]).map(key => <div key={key}><dt>{assistedLabels[key]}</dt><dd>{current.sample!.counts[key].toLocaleString('en-US')}</dd></div>)}</dl>
            {current.sample.oldestQueuedSeconds !== undefined && <p>Oldest queued at check: {formatAge(current.sample.oldestQueuedSeconds)}</p>}
            {current.sample.oldestUnobservedSendSeconds !== undefined && <p>Oldest unconfirmed send at check: {formatAge(current.sample.oldestUnobservedSendSeconds)}</p>}
            <p>Handset delivery is unverified.</p>
          </section>
          <p>Managed MoMo processing: {current.sample.managed} · Native SMS parsing: {current.sample.parsing} · Native SMS ledger: {current.sample.ledger}</p>
        </>}
        <p>Worker activity and provider availability are not verified.</p>
      </>}
  </Card>;
}
