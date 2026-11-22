/* eslint-disable no-control-regex -- Reject control characters in user-supplied filters. */
import { useCallback, useMemo, useRef, type ReactNode } from 'react';
import { Link, useLocation, useSearchParams } from 'react-router';
import type { AdminRequest } from '../../api/client';
import { safeAdminReturnLocation, useSession } from '../../session/SessionProvider';
import { Button, Card, EmptyState, ErrorState, LoadingState, PageHeader } from '../../ui';
import type { Page } from './contracts';
import { useOperationRead } from './useOperationRead';
import './operations.css';

export interface Actor { id: string; role: string; canonical: boolean; canExtract: boolean; canManageGateway: boolean; }

export function useActor() {
  const session = useSession();
  const user = session.user;
  const id = user?.id, role = user?.role, model = user?.financialModel;
  const canExtract = user?.role !== 'staff' && (user?.permissions.includes('sms.extract') ?? false);
  const canManageGateway = user?.role !== 'staff' && (user?.permissions.includes('gateway.manage') ?? false);
  const actor = useMemo<Actor | null>(() => id && role ? {
    id, role, canonical: model === 'canonical_evidence_ledger', canExtract, canManageGateway,
  } : null, [id, role, model, canExtract, canManageGateway]);
  return {session, actor};
}

export function formatStatus(value: string) { return value.replace(/_/g, ' ').replace(/^./, (first) => first.toUpperCase()); }
export function statusTone(value: string): 'success' | 'warning' | 'danger' | 'info' | 'neutral' {
  if (['active', 'reviewed', 'linked', 'delivered', 'accepted'].includes(value)) return 'success';
  if (['rejected', 'revoked', 'failed_no_send', 'parse_failed', 'suppressed'].includes(value)) return 'danger';
  if (['pending', 'needs_review', 'under_review', 'queued', 'uncertain', 'received', 'not_extracted'].includes(value)) return 'warning';
  return 'info';
}
const kigaliTime = new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'});
export function formatTime(value: string | number | null | undefined) {
  if (value === null || value === undefined) return 'Not recorded';
  const date = new Date(typeof value === 'number' ? value * 1000 : value);
  return Number.isFinite(date.getTime()) ? kigaliTime.format(date) : 'Not recorded';
}
export function query(offset: number, status: string, search = '', limit = 25) {
  const params = new URLSearchParams({limit: String(limit), offset: String(offset)});
  if (status) params.set('status', status);
  if (search) params.set('search', search);
  return params.toString();
}

export interface Column<T> { label: string; render: (row: T) => ReactNode; }
export interface RecordsFilter { key: string; label: string; allLabel: string; options: readonly {value: string; label: string}[] }
export interface RecordsProps<T> {
  title: string; subtitle: string; permission: string; statuses?: readonly string[]; searchable?: boolean;
  filters?: readonly RecordsFilter[]; smsPagination?: boolean;
  rowKey: (row: T) => string; columns: Column<T>[];
  load: (request: AdminRequest, offset: number, status: string, search: string, actor: Actor, filters: Record<string, string>, limit: number) => Promise<Page<T>>;
  extra?: ReactNode | ((reload: () => void) => ReactNode);
}

export function RecordsPage<T>({title, subtitle, permission, statuses = [], searchable = false, filters = [], smsPagination = false, rowKey, columns, load, extra}: RecordsProps<T>) {
  const {session, actor} = useActor();
  const [params, setParams] = useSearchParams();
  const searchForm = useRef<HTMLFormElement>(null);
  const limits = params.getAll('limit'), offsets = params.getAll('offset');
  const rawLimit = smsPagination && limits.length === 1 ? limits[0] : '25';
  const validLimit = !smsPagination || limits.length === 0 || limits.length === 1 && /^[1-9]\d{0,2}$/.test(rawLimit) && Number(rawLimit) <= 100;
  const limit = smsPagination && validLimit ? Number(rawLimit) : 25;
  const rawOffset = offsets.length === 1 ? offsets[0] : null;
  const rawPage = smsPagination && validLimit && params.getAll('page').length === 1 ? params.get('page') : null;
  const pageOffset = rawPage && /^[1-9]\d{0,9}$/.test(rawPage) && (Number(rawPage) - 1) * limit <= 2147483647 ? (Number(rawPage) - 1) * limit : 0;
  const offset = !validLimit || offsets.length > 1 ? 0 : rawOffset === null ? pageOffset : /^\d{1,10}$/.test(rawOffset) && Number(rawOffset) <= 2147483647 && Number(rawOffset) % limit === 0 ? Number(rawOffset) : 0;
  const candidateStatus = params.get('status') ?? '';
  const status = statuses.includes(candidateStatus) ? candidateStatus : '';
  const candidateSearch = params.get('search') ?? '';
  const search = searchable && candidateSearch.length <= 200 && !/[\x00-\x1f\x7f]/.test(candidateSearch) ? candidateSearch : '';
  const selectedFilters = Object.fromEntries(filters.map(filter => {
    const candidate = params.getAll(filter.key).length === 1 ? params.get(filter.key) ?? '' : '';
    return [filter.key, filter.options.some(option => option.value === candidate) ? candidate : ''];
  }));
  const filterKey = JSON.stringify(selectedFilters);
  const changeParams = (changes: Record<string, string | number>) => {
    const next = new URLSearchParams(params);
    if (smsPagination && Object.hasOwn(changes, 'offset')) next.delete('page');
    for (const [name, value] of Object.entries(changes)) {
      if (value === '' || value === 0) next.delete(name);
      else next.set(name, String(value));
    }
    setParams(next);
  };
  const canRead = !!actor && session.status === 'authenticated' && !!session.user?.permissions.includes(permission);
  const loadPage = useCallback(() => actor ? load(session.request, offset, status, search, actor, JSON.parse(filterKey) as Record<string, string>, limit) : Promise.reject(new Error('Account unavailable.')), [actor, filterKey, limit, load, offset, search, session.request, status]);
  const key = JSON.stringify([session.epoch, actor?.id ?? '', actor?.canonical ?? null, permission, offset, limit, status, search, filterKey]);
  const {result, retry} = useOperationRead(key, canRead, loadPage);
  const noRecords = result?.status === 'success' && result.value.rows.length === 0;
  const outOfRangeReceiptPage = smsPagination && offset > 0 && noRecords && result.value.total > 0;
  const hasFilters = smsPagination && Boolean(search || status || Object.values(selectedFilters).some(Boolean));
  const clearFilters = hasFilters ? <Button onClick={() => {
    searchForm.current?.reset();
    changeParams({search: '', status: '', offset: 0, ...Object.fromEntries(filters.map(({key}) => [key, '']))});
  }}>Clear filters</Button> : undefined;

  return <><PageHeader eyebrow="Collect Admin / Operations" title={title} subtitle={subtitle} />
    {canRead && (typeof extra === 'function' ? extra(retry) : extra)}
    {!canRead ? <ErrorState title="Access unavailable" message="Your current account cannot open these records." /> : <Card className="operations-records">
      <div className="operations-toolbar"><h2>{title}</h2>
        {searchable && <form ref={searchForm} className="operations-search" onSubmit={(event) => { event.preventDefault(); const value = new FormData(event.currentTarget).get('search'); if (typeof value === 'string' && !/[\x00-\x1f\x7f]/.test(value) && value.length <= 200) changeParams({offset: 0, search: value.trim()}); }}>
          <label className="admin-sr-only" htmlFor="operations-search">Search {title}</label><input key={search} id="operations-search" name="search" className="admin-input" type="search" maxLength={200} defaultValue={search} placeholder={smsPagination ? 'Search all receipts' : 'Search records'} /><Button type="submit" icon="search">Search</Button>
        </form>}
        {statuses.length > 0 && <label className="operations-filter"><span>Status</span><select className="admin-input" value={status} onChange={(event) => changeParams({offset: 0, status: event.target.value})}><option value="">All statuses</option>{statuses.map((value) => <option key={value} value={value}>{formatStatus(value)}</option>)}</select></label>}
        {filters.map(filter => <label className="operations-filter" key={filter.key}><span>{filter.label}</span><select className="admin-input" value={selectedFilters[filter.key]} onChange={(event) => changeParams({offset: 0, [filter.key]: event.target.value})}><option value="">{filter.allLabel}</option>{filter.options.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>)}
        {(!noRecords || outOfRangeReceiptPage) && clearFilters}
        {smsPagination && <Button onClick={retry}>Refresh</Button>}
      </div>
      {smsPagination && result?.status === 'success' && <p className="operations-receipt-load">Loaded {formatTime(result.receivedAt)} Kigali</p>}
      {!result ? <LoadingState label={`Loading ${title.toLowerCase()}`} /> : result.status === 'error' ? <ErrorState message={result.message} onRetry={retry} /> : noRecords ? <>
        {outOfRangeReceiptPage
          ? <EmptyState title="No receipts on this page"
              description={`${result.value.total} matching ${result.value.total === 1 ? 'receipt' : 'receipts'}.`}
              action={<Button onClick={() => changeParams({offset: 0})}>Return to first page</Button>} />
          : <EmptyState title="No records found" description={hasFilters ? undefined : 'Change your filters or check again later.'} action={clearFilters} />}
        {offset > 0 && <div className="operations-pagination"><Button onClick={() => changeParams({offset: Math.max(0, offset - result.value.limit)})}>Previous</Button></div>}
      </> : <>
        <div className="admin-table-wrap" tabIndex={0} role="region" aria-label={`${title} records`}>
          <table className={smsPagination ? 'admin-table operations-receipt-table' : 'admin-table'} role="table">
            <thead role="rowgroup"><tr role="row">{columns.map(({label}) => <th key={label} role="columnheader" scope="col">{label}</th>)}</tr></thead>
            <tbody role="rowgroup">{result.value.rows.map(row => <tr key={rowKey(row)} role="row">
              {columns.map(column => <td key={column.label} role="cell">
                {smsPagination && <span className="operations-receipt-field" aria-hidden="true">{column.label}</span>}
                {column.render(row)}
              </td>)}
            </tr>)}</tbody>
          </table>
        </div>
        <div className="operations-pagination"><span>Showing {offset + 1}–{offset + result.value.rows.length} of {result.value.total}</span><div><Button onClick={() => changeParams({offset: Math.max(0, offset - result.value.limit)})} disabled={offset === 0}>Previous</Button><Button onClick={() => changeParams({offset: offset + result.value.limit})} disabled={offset + result.value.rows.length >= result.value.total || offset + result.value.limit > 2147483647}>Next</Button></div></div>
      </>}
    </Card>}
  </>;
}

export function RecordLink({to, children, returnTo}: {to: string; children: ReactNode; returnTo?: string}) {
  const location = useLocation();
  const query = new URLSearchParams({returnTo: returnTo ?? location.pathname + location.search});
  return <Link className="operations-link" to={`${to}?${query}`}>{children}</Link>;
}

interface DetailProps<T> {
  title: string; subtitle: string; permission: string; back: string; resourceKey: string; valid: boolean;
  load: (request: AdminRequest, actor: Actor, offset: number) => Promise<T>;
  render: (value: T, offset: number, setOffset: (offset: number) => void, reload: () => void, returnPath: string) => ReactNode;
  additionalReturns?: string[];
}

export function DetailPage<T>({title, subtitle, permission, back, resourceKey, valid, load, render, additionalReturns = []}: DetailProps<T>) {
  const {session, actor} = useActor();
  const [params, setParams] = useSearchParams();
  const rawOffset = params.get('relatedOffset') ?? '0';
  const offset = /^\d{1,10}$/.test(rawOffset) && Number(rawOffset) <= 2147483647 && Number(rawOffset) % 25 === 0 ? Number(rawOffset) : 0;
  const setOffset = (value: number) => {const next = new URLSearchParams(params); if (value === 0) next.delete('relatedOffset'); else next.set('relatedOffset', String(value)); setParams(next);};
  const canRead = !!actor && session.status === 'authenticated' && !!session.user?.permissions.includes(permission);
  const loadDetail = useCallback(() => actor ? load(session.request, actor, offset) : Promise.reject(new Error('Account unavailable.')), [actor, load, offset, session.request]);
  const {result, retry} = useOperationRead(`${session.epoch}:${actor?.id ?? ''}:${resourceKey}:${offset}`, canRead && valid, loadDetail);
  const candidate = safeAdminReturnLocation(params.get('returnTo'));
  const returnPath = candidate && [back, ...additionalReturns].includes(new URL(candidate, 'https://admin.invalid').pathname) ? candidate : back;
  return <><PageHeader eyebrow="Collect Admin / Operations" title={title} subtitle={subtitle} /><p><Link className="operations-link" to={returnPath}>← Back to records</Link></p>
    {!canRead ? <ErrorState title="Access unavailable" message="Your current account cannot open this record." /> : !valid ? <ErrorState title="Record unavailable" message="Select a valid record." /> : !result ? <LoadingState label="Loading record" /> : result.status === 'error' ? <ErrorState message={result.message} onRetry={retry} /> : render(result.value, offset, setOffset, retry, returnPath)}
  </>;
}

export function Facts({items}: {items: [string, ReactNode][]}) {
  return <dl className="operations-facts">{items.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value ?? 'Not recorded'}</dd></div>)}</dl>;
}

export function RelatedPagination<T>({page, offset, onChange}: {page: Page<T>; offset: number; onChange: (offset: number) => void}) {
  if (page.total === 0) return <p>No related records.</p>;
  if (page.rows.length === 0) return <div className="operations-pagination"><span>No records on this page.</span><Button onClick={() => onChange(Math.max(0, offset - page.limit))} disabled={offset === 0}>Previous</Button></div>;
  return <div className="operations-pagination"><span>Showing {offset + 1}–{offset + page.rows.length} of {page.total}</span><div><Button onClick={() => onChange(Math.max(0, offset - page.limit))} disabled={offset === 0}>Previous</Button><Button onClick={() => onChange(offset + page.limit)} disabled={offset + page.rows.length >= page.total}>Next</Button></div></div>;
}
