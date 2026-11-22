import { useEffect, useMemo, useState } from 'react';
import { Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge } from '../../ui';
import { containsControl, formatField, formatMoney, label, parseCorePage, paymentReference, STATUSES } from './contracts';
import { coreListAction } from './coreRecordActions';
import type { CoreArea, CorePage, DataRow, FeatureAccess, FinancialModel } from './types';
import { AREA_TITLES, CORE_PERMISSIONS } from './types';
import './core.css';

type ListProps = FeatureAccess & { area: CoreArea; locationSearch?: string; allowMutations?: boolean };

const PAGE_SIZE = 25;
const descriptions: Record<CoreArea, string> = {
  groups: 'Explore group records and membership.', users: 'Review user records and account status.',
  members: 'Review members and their group affiliations.', payees: 'Review group payment receivers.',
  transactions: 'Review recorded payment evidence and its status.', ledgers: 'Review contribution records and ledger status.',
};

const baseSorts: Record<CoreArea, readonly [string, string][]> = {
  groups: [['created_at', 'Created'], ['title', 'Group'], ['active_members', 'Members'], ['status', 'Status']],
  users: [['created_at', 'Created'], ['public_id', 'Collect ID'], ['member_type', 'Type'], ['status', 'Status']],
  members: [['created_at', 'Created'], ['public_id', 'Collect ID'], ['member_type', 'Type'], ['status', 'Status']],
  payees: [['created_at', 'Created'], ['label', 'Payee'], ['group_title', 'Group'], ['status', 'Status']],
  transactions: [['created_at', 'Created'], ['group_title', 'Group'], ['observed_at', 'Observed'], ['status', 'Status']],
  ledgers: [['created_at', 'Created'], ['group_title', 'Group'], ['status', 'Status']],
};

interface Filters { search: string; status: string; sort: string; page: number }

function readFilters(search: string, area: CoreArea, model: FinancialModel): Filters {
  const query = new URLSearchParams(search);
  const candidate = query.get('search') ?? '';
  const rawStatus = query.get('status') ?? '';
  const rawSort = query.get('sort') ?? 'created_at_desc';
  const rawPage = Number(query.get('page') ?? 1);
  const validSort = baseSorts[area].some(([field]) => rawSort === `${field}_asc` || rawSort === `${field}_desc`);
  return {
    search: candidate.length <= 200 && !containsControl(candidate) ? candidate : '',
    status: STATUSES[model][area].includes(rawStatus) ? rawStatus : '',
    sort: validSort ? rawSort : 'created_at_desc',
    page: Number.isSafeInteger(rawPage) && rawPage >= 1 && rawPage <= 85899346 ? rawPage : 1,
  };
}

function listLocation(area: CoreArea, filter: Filters): string {
  const query = new URLSearchParams();
  if (filter.search) query.set('search', filter.search);
  if (filter.status) query.set('status', filter.status);
  if (filter.sort !== 'created_at_desc') query.set('sort', filter.sort);
  if (filter.page > 1) query.set('page', String(filter.page));
  const suffix = query.toString();
  return `/admin/${area}${suffix ? `?${suffix}` : ''}`;
}

function recordLocation(area: CoreArea, id: string, returnTo: string): string {
  const query = new URLSearchParams({ returnTo });
  return `/admin/${area}/${id}?${query.toString()}`;
}

function tone(status: string): 'success' | 'warning' | 'danger' | 'info' | 'neutral' {
  if (['active', 'confirmed', 'reconciled', 'confirmation_recorded', 'posted', 'contribution'].includes(status)) return 'success';
  if (['pending', 'recorded', 'draft', 'ambiguous'].includes(status)) return 'warning';
  if (['suspended', 'archived', 'rejection_recorded', 'evidence_conflict', 'reversed', 'deleted'].includes(status)) return 'danger';
  return 'neutral';
}

function columns(area: CoreArea, model: FinancialModel): { label: string; value: (row: DataRow) => string }[] {
  switch (area) {
    case 'groups': return [
      { label: 'Group', value: row => row.title }, { label: 'Slug', value: row => formatField('slug', row.slug) },
      { label: 'Members', value: row => formatField('active_members', row.active_members) },
      { label: 'Type', value: row => label(String(row.collection_type)) }, { label: 'Visibility', value: row => label(String(row.visibility)) },
    ];
    case 'users': case 'members': return [
      { label: 'Collect ID', value: row => row.title }, { label: 'Name on MoMo', value: row => row.display_name_recorded ? String(row.display_name) : 'Not recorded' },
      { label: 'Type', value: row => formatField('member_type', row.member_type) },
      { label: 'MoMo number / code', value: row => formatField('momo_number_or_code', row.momo_number ?? row.momo_pay_code) },
      { label: 'Contributed', value: row => formatMoney(row.total_contributed_rwf) },
    ];
    case 'payees': return [
      { label: 'Payee', value: row => row.title }, { label: 'Group', value: row => String(row.group_name) },
      { label: 'Provider', value: row => formatField('network', row.network) }, { label: 'MoMo number / code', value: row => row.amount },
    ];
    case 'transactions': return [
      { label: 'Reference', value: row => model === 'canonical_evidence_ledger' ? paymentReference(row) : row.title }, { label: 'Group', value: row => String(row.group_name) },
      { label: 'Receiver', value: row => formatField('payee_label', row.payee_label) },
      { label: 'Amount', value: row => formatMoney(row.amount_rwf) }, { label: 'Allocated', value: row => formatMoney(row.allocated_amount_rwf) },
    ];
    case 'ledgers': return [
      { label: 'Record', value: row => row.title }, { label: 'Group', value: row => String(row.group_name) },
      { label: 'Amount', value: row => row.signed_amount_rwf !== undefined ? formatMoney(row.signed_amount_rwf, true) : formatMoney(row.debit_rwf) },
      { label: 'Recorded', value: row => formatField('created_at', row.created_at) },
    ];
  }
}

export function CoreListPage({ area, request, permissions, actorId, role, authorityKey, financialModel, navigate, locationSearch = '', allowMutations = false }: ListProps) {
  const allowed = permissions.includes(CORE_PERMISSIONS[area]);
  const filter = useMemo(() => readFilters(locationSearch, area, financialModel), [locationSearch, area, financialModel]);
  const [draftState, setDraftState] = useState({ base: filter.search, value: filter.search });
  const draft = draftState.base === filter.search ? draftState.value : filter.search;
  const [page, setPage] = useState<CorePage | null>(null);
  const [pageScope, setPageScope] = useState('');
  const currentScope = JSON.stringify([authorityKey, area, financialModel, filter.search, filter.status, filter.sort, filter.page]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [retry, setRetry] = useState(0);
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController();
    let active = true;
    const offset = (filter.page - 1) * PAGE_SIZE;
    const query = new URLSearchParams({ search: filter.search, status: filter.status, limit: String(PAGE_SIZE), offset: String(offset), sort: filter.sort, country: 'RW' });
    request(`core/${area}?${query.toString()}`, { signal: controller.signal }).then(data => {
      const parsed = parseCorePage(data, area, financialModel, PAGE_SIZE, offset, filter.status);
      if (active) { setPage(parsed); setPageScope(currentScope); setState('ready'); }
    }).catch(() => { if (active) { setPageScope(currentScope); setState('error'); } });
    return () => { active = false; controller.abort(); };
  }, [allowed, area, request, actorId, authorityKey, financialModel, filter.search, filter.status, filter.sort, filter.page, currentScope, retry]);

  const update = (changes: Partial<Filters>) => navigate(listLocation(area, { ...filter, ...changes }));
  const tableColumns = columns(area, financialModel);
  const action = coreListAction({area, role, permissions, financialModel, allowed, allowMutations});
  return <>
    <PageHeader title={AREA_TITLES[area]} subtitle={descriptions[area]} actions={action ? <Button type="button" onClick={() => navigate(action.path)}>{action.label}</Button> : undefined} />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view this page." /> : <Card>
      <div className="core-toolbar">
        <div><h2>{AREA_TITLES[area]} list</h2><p>Search and review records</p></div>
        <form className="core-search" onSubmit={event => { event.preventDefault(); const value = draft.trim(); if (value.length <= 200 && !containsControl(value)) update({ search: value, page: 1 }); }}>
          <label className="core-visually-hidden" htmlFor={`search-${area}`}>Search {AREA_TITLES[area]}</label>
          <input id={`search-${area}`} className="admin-input" value={draft} onChange={event => setDraftState({ base: filter.search, value: event.target.value })} maxLength={200} placeholder="Search records" />
          <Button type="submit">Search</Button>
          <Button type="button" onClick={() => { setDraftState({ base: '', value: '' }); update({ search: '', status: '', sort: 'created_at_desc', page: 1 }); }}>Clear</Button>
        </form>
      </div>
      <div className="core-filters">
        <label>Status <select className="admin-input" value={filter.status} onChange={event => update({ status: event.target.value, page: 1 })}>
          <option value="">All statuses</option>{STATUSES[financialModel][area].map(value => <option key={value} value={value}>{label(value)}</option>)}
        </select></label>
        <label>Sort by <select className="admin-input" value={filter.sort} onChange={event => update({ sort: event.target.value, page: 1 })}>
          {baseSorts[area].flatMap(([field, name]) => [<option key={`${field}_asc`} value={`${field}_asc`}>{name} · ascending</option>, <option key={`${field}_desc`} value={`${field}_desc`}>{name} · descending</option>])}
        </select></label>
      </div>
      {state === 'loading' || pageScope !== currentScope ? <LoadingState label={`Loading ${AREA_TITLES[area].toLowerCase()}`} /> :
       state === 'error' ? <ErrorState message="The records could not be verified or the service is unavailable." onRetry={() => { setState('loading'); setRetry(value => value + 1); }} /> :
       !page || page.rows.length === 0 ? <EmptyState title="No records found" description="Change your search or filters and try again." /> : <>
        <div className="admin-table-wrap" role="region" aria-label={`${AREA_TITLES[area]} records`} tabIndex={0}>
          <table className="admin-table"><thead><tr>{tableColumns.map(column => <th scope="col" key={column.label}>{column.label}</th>)}<th scope="col">Status</th><th scope="col">Open</th></tr></thead>
            <tbody>{page.rows.map(row => <tr key={row.id}>{tableColumns.map(column => <td key={column.label}>{column.value(row)}</td>)}<td><StatusBadge tone={tone(row.status)}>{label(row.status)}</StatusBadge></td><td><Button type="button" onClick={() => navigate(recordLocation(area, row.id, listLocation(area, filter)))} aria-label={`View ${area === 'transactions' && financialModel === 'canonical_evidence_ledger' ? paymentReference(row) : row.title}`}>View</Button></td></tr>)}</tbody>
          </table>
        </div>
        <div className="core-pager"><span>Showing {(filter.page - 1) * PAGE_SIZE + 1}–{(filter.page - 1) * PAGE_SIZE + page.rows.length} of {page.total}</span><div><Button type="button" disabled={filter.page <= 1} onClick={() => update({ page: filter.page - 1 })}>Previous</Button><span aria-current="page">{filter.page}</span><Button type="button" disabled={filter.page * PAGE_SIZE >= page.total} onClick={() => update({ page: filter.page + 1 })}>Next</Button></div></div>
       </>}
    </Card>}
  </>;
}
