import { useEffect, useMemo, useRef, useState } from 'react';
import { Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge } from '../../ui';
import { containsControl, evidenceReference, formatField, formatMoney, isId, label, paymentReference } from '../core/contracts';
import type { FeatureAccess } from '../core/types';
import { parseReconciliationDetail, parseReconciliationPage } from './contracts';
import type { ReconciliationPage } from './contracts';
import { CanonicalReconciliationActions } from './CanonicalActions';
import { LegacyReconciliationActions } from './LegacyReconciliationActions';
import type { PendingIdentity } from '../core/pendingAttempt';
import '../core/core.css';

interface QueueProps extends FeatureAccess { locationSearch?: string }
interface DetailProps extends FeatureAccess { id: string; returnTo?: string | null; identity?: PendingIdentity; allowMutations?: boolean; verifyFresh?: () => Promise<boolean> }
const LIMIT = 25;
const canonicalStatuses = ['recorded', 'ambiguous', 'reconciled', 'confirmed', 'corrected', 'reversed'];
const legacyStatuses = ['pending', 'confirmation_recorded', 'evidence_conflict'];

function safeSearch(value: string): string { return value.length <= 200 && !containsControl(value) ? value : ''; }
function toLocation(search: string, status: string, page: number): string {
  const query = new URLSearchParams();
  if (search) query.set('search', search);
  if (status) query.set('status', status);
  if (page > 1) query.set('page', String(page));
  return `/admin/reconciliations${query.toString() ? `?${query.toString()}` : ''}`;
}
function safeReturn(raw?: string | null): string {
  if (!raw || raw.length > 2000 || containsControl(raw, true) || raw.includes('\\') || raw.includes('#') || !raw.startsWith('/') || raw.startsWith('//')) return '/admin/reconciliations';
  try {
    const url = new URL(raw, 'https://collect.invalid');
    const keys = [...url.searchParams.keys()];
    if (url.origin !== 'https://collect.invalid' || url.pathname !== '/admin/reconciliations' || url.hash ||
        keys.some(key => !['search', 'status', 'page'].includes(key)) || new Set(keys).size !== keys.length) return '/admin/reconciliations';
    return `${url.pathname}${url.search}`;
  } catch { return '/admin/reconciliations'; }
}
function rowText(value: unknown): string { return typeof value === 'string' && value.trim() ? value : 'Not recorded'; }

export function ReconciliationQueuePage({ request, permissions, actorId, authorityKey, financialModel, navigate, locationSearch = '' }: QueueProps) {
  const allowed = permissions.includes('reconciliations.read');
  const filter = useMemo(() => {
    const query = new URLSearchParams(locationSearch);
    const status = query.get('status') ?? '';
    const page = Number(query.get('page') ?? 1);
    const statuses = financialModel === 'canonical_evidence_ledger' ? canonicalStatuses : legacyStatuses;
    return { search: safeSearch(query.get('search') ?? ''), status: statuses.includes(status) ? status : '', page: Number.isSafeInteger(page) && page >= 1 && page <= 85899346 ? page : 1 };
  }, [locationSearch, financialModel]);
  const [draftState, setDraftState] = useState({ base: filter.search, value: filter.search });
  const draft = draftState.base === filter.search ? draftState.value : filter.search;
  const [result, setResult] = useState<ReconciliationPage | null>(null);
  const [resultScope, setResultScope] = useState('');
  const currentScope = JSON.stringify([authorityKey, financialModel, filter.search, filter.status, filter.page]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController(); let active = true;
    const offset = (filter.page - 1) * LIMIT;
    const query = new URLSearchParams({ limit: String(LIMIT), offset: String(offset) });
    if (financialModel === 'canonical_evidence_ledger') { query.set('search', filter.search); query.set('status', filter.status); }
    else { if (filter.search) query.set('search', filter.search); if (filter.status) query.set('verification_status', filter.status); }
    request(`reconciliations?${query.toString()}`, { signal: controller.signal }).then(data => {
      const parsed = parseReconciliationPage(data, financialModel, LIMIT, offset, filter.status);
      if (active) { setResult(parsed); setResultScope(currentScope); setState('ready'); }
    }).catch(() => { if (active) { setResultScope(currentScope); setState('error'); } });
    return () => { active = false; controller.abort(); };
  }, [allowed, request, actorId, authorityKey, financialModel, filter.search, filter.status, filter.page, currentScope, retry]);
  const go = (search: string, status: string, page: number) => navigate(toLocation(search, status, page));
  const selected = toLocation(filter.search, filter.status, filter.page);
  return <>
    <PageHeader title="Reconciliations" subtitle="Review recorded payment evidence and attribution." />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view reconciliations." /> : <Card>
      <div className="core-toolbar"><div><h2>Review queue</h2><p>Evidence and recorded contributions are not provider settlement.</p></div>
        <form className="core-search" onSubmit={event => { event.preventDefault(); go(safeSearch(draft.trim()), filter.status, 1); }}>
          <label className="core-visually-hidden" htmlFor="reconciliation-search">Search reconciliations</label><input id="reconciliation-search" className="admin-input" placeholder="Search records" maxLength={200} value={draft} onChange={event => setDraftState({ base: filter.search, value: event.target.value })} />
          <Button type="submit">Search</Button><Button type="button" onClick={() => { setDraftState({ base: '', value: '' }); go('', '', 1); }}>Clear</Button>
        </form>
      </div>
      <div className="core-filters"><label>Status <select className="admin-input" value={filter.status} onChange={event => go(filter.search, event.target.value, 1)}><option value="">All statuses</option>{(financialModel === 'canonical_evidence_ledger' ? canonicalStatuses : legacyStatuses).map(status => <option key={status} value={status}>{label(status)}</option>)}</select></label></div>
      {state === 'loading' || resultScope !== currentScope ? <LoadingState label="Loading reconciliations" /> :
       state === 'error' ? <ErrorState message="The reconciliation records could not be verified or the service is unavailable." onRetry={() => { setState('loading'); setRetry(value => value + 1); }} /> :
       !result || result.rows.length === 0 ? <EmptyState title="No records found" description="Change your search or filters and try again." /> : <>
        <div className="admin-table-wrap" role="region" aria-label="Reconciliation queue" tabIndex={0}><table className="admin-table"><thead><tr><th scope="col">Reference</th><th scope="col">Group</th><th scope="col">Receiver</th><th scope="col">Amount</th><th scope="col">Evidence status</th><th scope="col">Open</th></tr></thead><tbody>{result.rows.map(row => {
          const status = rowText(financialModel === 'canonical_evidence_ledger' ? row.status : row.verification_status);
          const title = financialModel === 'canonical_evidence_ledger' ? paymentReference(row) : rowText(row.provider_reference);
          const group = rowText(financialModel === 'canonical_evidence_ledger' ? row.group_name : row.group_title);
          const payee = rowText(financialModel === 'canonical_evidence_ledger' ? row.payee_label : row.payee_name);
          const query = new URLSearchParams({ returnTo: selected });
          return <tr key={String(row.id)}><td>{title}</td><td>{group}</td><td>{payee}</td><td>{formatMoney(row.amount_rwf)}</td><td><StatusBadge tone={status === 'confirmed' || status === 'reconciled' || status === 'confirmation_recorded' ? 'success' : 'warning'}>{label(status)}</StatusBadge></td><td><Button type="button" aria-label={`View ${title}`} onClick={() => navigate(`/admin/reconciliations/${row.id}?${query.toString()}`)}>View</Button></td></tr>;
        })}</tbody></table></div>
        <div className="core-pager"><span>Showing {result.offset + 1}–{result.offset + result.rows.length} of {result.total}</span><div><Button type="button" disabled={filter.page === 1} onClick={() => go(filter.search, filter.status, filter.page - 1)}>Previous</Button><span aria-current="page">{filter.page}</span><Button type="button" disabled={result.nextOffset === null} onClick={() => go(filter.search, filter.status, filter.page + 1)}>Next</Button></div></div>
       </>}
    </Card>}
  </>;
}

const detailFields: readonly [string, string][] = [['title', 'Reference'], ['provider_reference', 'Provider reference'], ['group_name', 'Group'], ['group_title', 'Group'], ['payee_label', 'Receiver'], ['payee_name', 'Receiver'], ['amount_rwf', 'Recorded amount'], ['allocated_amount_rwf', 'Allocated amount'], ['unallocated_amount_rwf', 'Unallocated amount'], ['status', 'Status'], ['verification_status', 'Evidence status'], ['settlement_status', 'Provider settlement']];
const relatedFields: readonly [string, string][] = [['id', 'Record'], ['status', 'Status'], ['outcome', 'Outcome'], ['amount_rwf', 'Amount'], ['kind', 'Kind'], ['reference', 'Reference'], ['created_at', 'Created']];

function RelatedSection({ name, initial, id, actorId, principalId, financialModel, permissions, role, request, version, groupVersion }: {
  name: string; initial: ReconciliationPage; id: string; actorId: string; principalId: string | null;
  financialModel: FeatureAccess['financialModel']; permissions: readonly string[]; role: string; request: FeatureAccess['request']; version: unknown; groupVersion: number | null;
}) {
  const [page, setPage] = useState(initial);
  const [state, setState] = useState<'ready' | 'loading' | 'error'>('ready');
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const go = async (offset: number) => {
    if (state !== 'ready') return;
    setState('loading');
    try {
      const query = new URLSearchParams({ [financialModel === 'canonical_evidence_ledger' ? 'relation' : 'related']: name, limit: String(page.limit), offset: String(offset) });
      const data = await request(`reconciliations/${id}?${query.toString()}`);
      const parsed = parseReconciliationDetail(data, financialModel, id, actorId, principalId, permissions, role, name, page.limit, offset);
      if (parsed.resource.version !== version || parsed.groupVersion !== groupVersion) throw new Error('The payment or group changed');
      if (mounted.current) { setPage(parsed.related[name]); setState('ready'); }
    } catch { if (mounted.current) setState('error'); }
  };
  const visibleFields = relatedFields.filter(([key]) => page.rows.some(row => key in row));
  return <Card><div className="core-detail"><h2>{label(name)}</h2>{state === 'error' && <p role="alert">This page could not be verified. Reopen the record before continuing.</p>}
    {page.rows.length === 0 ? <p>No records found.</p> : <div className="admin-table-wrap" role="region" aria-label={`${label(name)} records`} tabIndex={0}><table className="admin-table"><thead><tr>{visibleFields.map(([key, title]) => <th key={key} scope="col">{financialModel === 'canonical_evidence_ledger' && name === 'evidence' && key === 'reference' ? 'Evidence reference' : title}</th>)}</tr></thead><tbody>{page.rows.map(row => <tr key={String(row.id)}>{visibleFields.map(([key]) => <td key={key}>{financialModel === 'canonical_evidence_ledger' && name === 'evidence' && key === 'reference' ? evidenceReference(row[key]) : formatField(key, row[key])}</td>)}</tr>)}</tbody></table></div>}
    <div className="core-pager"><span>{page.total === 0 ? '0 records' : `${page.offset + 1}–${page.offset + page.rows.length} of ${page.total}`}</span><div><Button type="button" disabled={state !== 'ready' || page.offset === 0} onClick={() => void go(Math.max(0, page.offset - page.limit))}>Previous</Button><Button type="button" disabled={state !== 'ready' || page.nextOffset === null} onClick={() => void go(page.nextOffset!)}>Next</Button></div></div>
  </div></Card>;
}

export function ReconciliationDetailPage({ id, request, permissions, actorId, principalId, authorityKey, financialModel, navigate, returnTo, role, identity, allowMutations = false, verifyFresh }: DetailProps) {
  const allowed = permissions.includes('reconciliations.read');
  const [result, setResult] = useState<ReturnType<typeof parseReconciliationDetail> | null>(null);
  const [resultScope, setResultScope] = useState('');
  const currentScope = JSON.stringify([authorityKey, financialModel, id]);
  const permissionToken = JSON.stringify([...permissions].sort());
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!allowed || !isId(id)) return;
    const controller = new AbortController(); let active = true;
    const query = new URLSearchParams({ limit: String(LIMIT), offset: '0' });
    request(`reconciliations/${id}?${query.toString()}`, { signal: controller.signal }).then(data => {
      const parsed = parseReconciliationDetail(data, financialModel, id, actorId, principalId, JSON.parse(permissionToken) as string[], role);
      if (active) { setResult(parsed); setResultScope(currentScope); setState('ready'); }
    }).catch(() => { if (active) { setResultScope(currentScope); setState('error'); } });
    return () => { active = false; controller.abort(); };
  }, [allowed, id, request, actorId, principalId, authorityKey, financialModel, permissionToken, role, currentScope, retry]);
  return <>
    <PageHeader title="Reconciliation" subtitle="Review the retained evidence and related records." actions={<Button type="button" onClick={() => navigate(safeReturn(returnTo))}>Back to reconciliations</Button>} />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view this record." /> :
      !isId(id) ? <ErrorState message="Select a valid record." /> :
      state === 'loading' || resultScope !== currentScope ? <LoadingState label="Loading reconciliation" /> :
      state === 'error' || !result ? <ErrorState message="The reconciliation could not be verified or the service is unavailable." onRetry={() => { setState('loading'); setRetry(value => value + 1); }} /> : <>
        <Card><div className="core-detail"><h2>Payment evidence</h2><dl>{detailFields.filter(([key]) => result.resource[key] !== undefined).map(([key, title]) => <div key={key}><dt>{financialModel === 'canonical_evidence_ledger' && key === 'provider_reference' ? 'Evidence reference' : title}</dt><dd>{financialModel === 'canonical_evidence_ledger' && key === 'title' ? paymentReference(result.resource) : financialModel === 'canonical_evidence_ledger' && key === 'provider_reference' ? evidenceReference(result.resource[key]) : formatField(key, result.resource[key])}</dd></div>)}</dl></div></Card>
        <p className="core-note">Recorded evidence does not establish provider settlement.</p>
        {financialModel === 'canonical_evidence_ledger' && identity && verifyFresh && <CanonicalReconciliationActions key={`${currentScope}:actions`} detail={result} identity={identity} allowMutations={allowMutations} verifyFresh={verifyFresh}
          access={{request, permissions, actorId, principalId, authorityKey, financialModel, navigate, role}}
          onCompleted={() => { setState('loading'); setRetry(value => value + 1); }} />}
        {financialModel === 'transaction_journals' && identity && verifyFresh && <LegacyReconciliationActions key={`${currentScope}:legacy-actions`} detail={result} identity={identity} allowMutations={allowMutations} verifyFresh={verifyFresh}
          access={{request, permissions, actorId, principalId, authorityKey, financialModel, navigate, role}}
          onCompleted={() => { setState('loading'); setRetry(value => value + 1); }} />}
        {Object.entries(result.related).map(([name, page]) => <RelatedSection key={`${currentScope}:${name}`} name={name} initial={page} id={id} actorId={actorId} principalId={principalId} financialModel={financialModel} permissions={permissions} role={role} request={request} version={result.resource.version} groupVersion={result.groupVersion} />)}
      </>}
  </>;
}
