import { useEffect, useMemo, useRef, useState } from 'react';
import { Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge } from '../../ui';
import { OperatorNotes } from '../notes/OperatorNotes';
import { LegacyTransactionActions } from '../legacy-transactions';
import { AREA_TITLES, CORE_PERMISSIONS } from './types';
import type { CoreArea, CorePage, DataRow, FeatureAccess, FinancialModel } from './types';
import { containsControl, formatField, formatMoney, isId, isObject, isSafeCount, label, parseCorePage, parseCoreRow, paymentReference, STATUSES } from './contracts';
import { listPending } from './pendingAttempt';
import type { PendingAttempt, PendingIdentity } from './pendingAttempt';
import './core.css';

type ListProps = FeatureAccess & { area: CoreArea; locationSearch?: string; allowMutations?: boolean };
type RecordProps = FeatureAccess & { area: CoreArea; id: string; returnTo?: string | null; allowMutations?: boolean; identity?: PendingIdentity; isCurrent?: () => boolean };

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

function safeReturn(area: CoreArea, raw?: string | null): string {
  if (!raw || raw.length > 2000 || containsControl(raw, true) || raw.includes('\\') || raw.includes('#') || !raw.startsWith('/') || raw.startsWith('//')) return `/admin/${area}`;
  try {
    const url = new URL(raw, 'https://collect.invalid');
    if (url.origin !== 'https://collect.invalid' || url.pathname !== `/admin/${area}` || url.hash) return `/admin/${area}`;
    const keys = [...url.searchParams.keys()];
    if (keys.some(key => !['search', 'status', 'sort', 'page'].includes(key)) || new Set(keys).size !== keys.length) return `/admin/${area}`;
    return `${url.pathname}${url.search}`;
  } catch { return `/admin/${area}`; }
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
  return <>
    <PageHeader title={AREA_TITLES[area]} subtitle={descriptions[area]} actions={area === 'groups' && allowed && permissions.includes('collections.create') ? <Button type="button" onClick={() => navigate('/admin/groups/new')}>{allowMutations ? 'Create group' : 'Check group creation request'}</Button> : area === 'users' && allowed && role !== 'staff' && permissions.includes('users.manage') ? <Button type="button" onClick={() => navigate('/admin/users/new')}>{allowMutations ? 'Create person' : 'Check person creation request'}</Button> : area === 'transactions' && allowed && role !== 'staff' && permissions.includes('payments.manage') && (financialModel === 'canonical_evidence_ledger' || ['collections.read', 'receivers.read', 'overview.read'].every(permission => permissions.includes(permission))) ? <Button type="button" onClick={() => navigate('/admin/transactions/new')}>{allowMutations && permissions.includes('collections.read') && permissions.includes('receivers.read') && (financialModel === 'transaction_journals' || permissions.includes('payments.write')) ? 'Record payment evidence' : 'Check evidence request'}</Button> : area === 'ledgers' && allowed && financialModel === 'transaction_journals' && role !== 'staff' && permissions.includes('ledger.manage') ? <Button type="button" onClick={() => navigate('/admin/ledgers/new')}>{allowMutations && permissions.includes('collections.read') && permissions.includes('overview.read') ? 'Create journal draft' : 'Check journal draft request'}</Button> : undefined} />
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

const fields: Record<CoreArea, readonly [string, string][]> = {
  groups: [['title', 'Group'], ['slug', 'Slug'], ['collection_type', 'Type'], ['purpose_label', 'Purpose'], ['visibility', 'Visibility'], ['active_members', 'Members'], ['status', 'Status'], ['created_at', 'Created']],
  users: [['public_id', 'Collect ID'], ['display_name', 'Name on MoMo'], ['member_type', 'Type'], ['whatsapp_number', 'WhatsApp'], ['email', 'Email'], ['momo_provider', 'MoMo provider'], ['momo_number', 'MoMo number'], ['momo_pay_code', 'MoMo code'], ['total_contributed_rwf', 'Recorded contributions'], ['status', 'Status']],
  members: [['public_id', 'Collect ID'], ['display_name', 'Name on MoMo'], ['member_type', 'Type'], ['whatsapp_number', 'WhatsApp'], ['momo_provider', 'MoMo provider'], ['momo_number', 'MoMo number'], ['momo_pay_code', 'MoMo code'], ['total_contributed_rwf', 'Recorded contributions'], ['status', 'Status']],
  payees: [['title', 'Payee'], ['group_name', 'Group'], ['network', 'Provider'], ['momo_number_or_code', 'MoMo number / code'], ['status', 'Status']],
  transactions: [['title', 'Reference'], ['group_name', 'Group'], ['payee_label', 'Receiver'], ['amount_rwf', 'Recorded amount'], ['allocated_amount_rwf', 'Allocated amount'], ['status', 'Evidence status'], ['settlement_status', 'Settlement'], ['observed_at', 'Observed']],
  ledgers: [['title', 'Record'], ['group_name', 'Group'], ['signed_amount_rwf', 'Signed amount'], ['debit_rwf', 'Debit'], ['credit_rwf', 'Credit'], ['status', 'Status'], ['created_at', 'Created']],
};
const relationFields: readonly [string, string][] = [['id', 'Record'], ['public_id', 'Collect ID'], ['group_title', 'Group'], ['title', 'Title'], ['name', 'Name'], ['display_name', 'Name on MoMo'], ['label', 'Label'], ['code', 'Code'], ['role', 'Role'], ['status', 'Status'], ['network', 'Provider'], ['momo_number_or_code', 'MoMo number / code'], ['amount_rwf', 'Amount'], ['created_at', 'Created']];
const relations: Record<string, readonly string[]> = { groups: ['memberships', 'payees', 'accounts'], users: ['memberships'], payees: [], transactions: ['evidence', 'reviews', 'allocations', 'journals', 'payer_insights', 'ledger_entries'], journals: ['entries'], ledgers: [] };
interface RelatedPage { total: number; limit: number; offset: number; nextOffset: number | null }

function relatedPage(data: Record<string, unknown>, name: string, rows: unknown[]): RelatedPage | null {
  if (data.related_pages === undefined || data.related_pages === null) {
    if (data.related_truncated === true) throw new Error('The related record page is incomplete.');
    return null;
  }
  if (!isObject(data.related_pages) || !isObject(data.related_pages[name])) throw new Error('Invalid related page');
  const page = data.related_pages[name];
  if (Object.keys(page).length !== 4 || !isSafeCount(page.total) || !isSafeCount(page.limit) || page.limit < 1 || page.limit > 100 ||
      !isSafeCount(page.offset) || rows.length !== Math.min(page.limit, Math.max(0, page.total - page.offset)) ||
      page.next_offset !== (page.offset + rows.length < page.total ? page.offset + rows.length : null)) throw new Error('Invalid related page');
  return { total: page.total, limit: page.limit, offset: page.offset, nextOffset: page.next_offset as number | null };
}

function validateRelated(data: Record<string, unknown>, resource: string, requiredRelation?: string): void {
  if (!isObject(data.related) || typeof data.related_truncated !== 'boolean') throw new Error('Invalid related records');
  const names = Object.keys(data.related);
  if (requiredRelation && (names.length !== 1 || names[0] !== requiredRelation)) throw new Error('Invalid related page');
  if (isObject(data.related_pages) && Object.keys(data.related_pages).length !== names.length) throw new Error('Invalid related pages');
  for (const name of names) {
    const rows = data.related[name];
    if (!relations[resource]?.includes(name) || !Array.isArray(rows) || rows.length > 200 || rows.some(row => !isObject(row))) throw new Error('Invalid related records');
    relatedPage(data, name, rows);
  }
}

function CoreRelatedSection({ name, initial, page, resource, id, actorId, financialModel, request, version, membershipRecovery, membershipWrite, accountRead, journalRecovery, journalWrite, navigate }: {
  name: string; initial: Record<string, unknown>[]; page: RelatedPage | null; resource: string; id: string; actorId: string;
  financialModel: FinancialModel; request: FeatureAccess['request']; version: unknown; membershipRecovery: boolean; membershipWrite: boolean; accountRead: boolean; journalRecovery: boolean; journalWrite: boolean; navigate: FeatureAccess['navigate'];
}) {
  const [rows, setRows] = useState(initial);
  const [currentPage, setCurrentPage] = useState(page);
  const [state, setState] = useState<'ready' | 'loading' | 'error'>('ready');
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const go = async (offset: number) => {
    if (!currentPage || state === 'loading') return;
    setState('loading');
    try {
      const query = new URLSearchParams({ relation: name, limit: String(currentPage.limit), offset: String(offset) });
      const data = await request(`operations/${resource}/${id}?${query.toString()}`);
      if (data.resource_type !== resource || data.current_actor_id !== actorId || !isObject(data.resource) ||
          (data.resource.id !== id && !(resource === 'users' && data.resource.operator_admin_id === id)) || data.resource.version !== version ||
          (financialModel === 'canonical_evidence_ledger' && (data.contract_version !== 2 || data.model !== financialModel))) throw new Error('The record changed');
      validateRelated(data, resource, name);
      const related = data.related as Record<string, unknown>;
      const nextRows = related[name] as Record<string, unknown>[];
      const nextPage = relatedPage(data, name, nextRows);
      if (!nextPage || nextPage.offset !== offset || nextPage.limit !== currentPage.limit) throw new Error('Invalid related page');
      if (mounted.current) { setRows(nextRows); setCurrentPage(nextPage); setState('ready'); }
    } catch { if (mounted.current) setState('error'); }
  };
  const visibleFields = relationFields.filter(([key]) => rows.some(row => key in row));
  const membershipActions = name === 'memberships' && membershipRecovery;
  const accountActions = name === 'accounts' && resource === 'groups' && financialModel === 'transaction_journals' && accountRead;
  const allocationActions = name === 'allocations' && resource === 'transactions' && financialModel === 'transaction_journals' && journalRecovery;
  return <Card><div className="core-detail"><h2>{label(name)}</h2>{state === 'error' && <p role="alert">This page could not be verified. Reopen the record before continuing.</p>}
    {rows.length === 0 ? <p>No records found.</p> : <div className="admin-table-wrap" role="region" aria-label={`${label(name)} records`} tabIndex={0}><table className="admin-table"><thead><tr>{visibleFields.map(([key, title]) => <th scope="col" key={key}>{title}</th>)}{(membershipActions || accountActions || allocationActions) && <th scope="col">Action</th>}</tr></thead><tbody>{rows.map((row, index) => <tr key={typeof row.id === 'string' ? row.id : index}>{visibleFields.map(([key]) => <td key={key}>{formatField(key, row[key])}</td>)}{membershipActions && <td>{isId(row.group_id) && isId(row.user_id) && <Button type="button" onClick={() => navigate(`/admin/groups/${row.group_id}/members/${row.user_id}/edit`)}>{membershipWrite && (financialModel === 'transaction_journals' ? ['admin', 'receiver', 'member', 'contributor', 'viewer'].includes(String(row.role)) : ['member', 'admin'].includes(String(row.role)) && row.account_status === 'active') ? 'Edit membership' : 'Check membership request'}</Button>}</td>}{accountActions && <td>{isId(row.id) && <Button type="button" onClick={() => navigate(`/admin/ledger-accounts/${row.id}`)}>View account</Button>}</td>}{allocationActions && <td>{isId(row.id) && <Button type="button" onClick={() => navigate(`/admin/transactions/${id}/allocations/${row.id}/journal/new`)}>{journalWrite && isSafeCount(row.amount_rwf) && row.amount_rwf > 0 ? 'Review linked draft' : 'Check linked journal request'}</Button>}</td>}</tr>)}</tbody></table></div>}
    {currentPage && <div className="core-pager"><span>{currentPage.total === 0 ? '0 records' : `${currentPage.offset + 1}–${currentPage.offset + rows.length} of ${currentPage.total}`}</span><div><Button type="button" disabled={state !== 'ready' || currentPage.offset === 0} onClick={() => void go(Math.max(0, currentPage.offset - currentPage.limit))}>Previous</Button><Button type="button" disabled={state !== 'ready' || currentPage.nextOffset === null} onClick={() => void go(currentPage.nextOffset!)}>Next</Button></div></div>}
  </div></Card>;
}

function MembershipRecoveries({ identity, scope, resource, id, navigate }: { identity: PendingIdentity; scope: string; resource: string; id: string; navigate: FeatureAccess['navigate'] }) {
  const permissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({ id: identity.id, sessionId: identity.sessionId, email: identity.email, role: identity.role,
    permissions: JSON.parse(permissionKey) as string[], expiresAt: identity.expiresAt }), [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, permissionKey]);
  const [result, setResult] = useState<{scope: string; entries: PendingAttempt[]; error: boolean} | null>(null);
  useEffect(() => {
    let live = true;
    listPending(stableIdentity, 'operating-updatemembership', 'users.manage').then(entries => {
      for (const entry of entries) {
        const pair = entry.resource_id.split(':');
        if (pair.length !== 2 || !isId(pair[0]) || !isId(pair[1]) || !isSafeCount(entry.intent.expected_version) || entry.intent.expected_version < 1) throw new Error('Invalid membership recovery');
      }
      if (live) setResult({scope, entries: entries.filter(entry => {
        const [groupId, userId] = entry.resource_id.split(':');
        return resource === 'groups' ? groupId === id : userId === id;
      }), error: false});
    }).catch(() => { if (live) setResult({scope, entries: [], error: true}); });
    return () => { live = false; };
  }, [stableIdentity, scope, resource, id]);
  if (!result || result.scope !== scope) return null;
  if (result.error) return <Card><div className="core-detail"><p role="alert">Membership recovery data could not be verified. Check the original request before another change.</p></div></Card>;
  if (!result.entries.length) return null;
  return <Card><div className="core-detail"><h2>Pending membership requests</h2>{result.entries.map(entry => {
    const [groupId, userId] = entry.resource_id.split(':');
    return <div key={entry.request_key}><p>Group {groupId} · Member {userId} · Request <code>{entry.request_key}</code></p><Button type="button" onClick={() => navigate(`/admin/groups/${groupId}/members/${userId}/edit`)}>Check pending membership change</Button></div>;
  })}</div></Card>;
}

export function CoreRecordPage({ area, id, request, permissions, actorId, principalId, role, authorityKey, financialModel, navigate, returnTo, allowMutations = false, identity, isCurrent }: RecordProps) {
  const allowed = permissions.includes(CORE_PERMISSIONS[area]);
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null);
  const [detailScope, setDetailScope] = useState('');
  const currentScope = JSON.stringify([authorityKey, area, financialModel, id]);
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [retry, setRetry] = useState(0);
  const resource = area === 'members' ? 'users' : area === 'ledgers' && financialModel === 'transaction_journals' ? 'journals' : area;
  useEffect(() => {
    if (!allowed || !isId(id)) return;
    const controller = new AbortController(); let active = true;
    request(`operations/${resource}/${id}`, { signal: controller.signal }).then(data => {
      if (data.resource_type !== resource || data.current_actor_id !== actorId || typeof data.can_manage !== 'boolean' || !isObject(data.resource) || !isObject(data.related)) throw new Error('Invalid detail');
      if (financialModel === 'canonical_evidence_ledger') {
        if (data.contract_version !== 2 || data.model !== financialModel) throw new Error('Invalid model');
        parseCoreRow(area === 'members' ? 'users' : area, financialModel, data.resource);
      } else if (data.contract_version !== undefined || data.model !== undefined || (data.resource.id !== id && !(resource === 'users' && data.resource.operator_admin_id === id))) throw new Error('Invalid detail');
      if (data.resource.id !== id && !(resource === 'users' && data.resource.operator_admin_id === id)) throw new Error('Invalid identity');
      validateRelated(data, resource);
      if (active) { setDetail(data); setDetailScope(currentScope); setState('ready'); }
    }).catch(() => { if (active) { setDetailScope(currentScope); setState('error'); } });
    return () => { active = false; controller.abort(); };
  }, [allowed, id, resource, request, actorId, authorityKey, financialModel, area, currentScope, retry]);
  const back = safeReturn(area, returnTo);
  const canEditGroup = allowMutations && detailScope === currentScope && state === 'ready' && area === 'groups' &&
    role !== 'staff' && permissions.includes('collections.manage') && detail?.can_manage === true &&
    (financialModel === 'canonical_evidence_ledger' ? Array.isArray(detail.allowed_operations) && detail.allowed_operations.includes('updateGroup') :
      permissions.includes('overview.read') && isObject(detail.resource) && detail.resource.status !== 'archived');
  const canRecoverGroup = detailScope === currentScope && state === 'ready' && area === 'groups' &&
    role !== 'staff' && permissions.includes('collections.manage');
  const canRecoverPayee = detailScope === currentScope && state === 'ready' && area === 'payees' && role !== 'staff' && permissions.includes('receivers.manage') &&
    (financialModel === 'canonical_evidence_ledger' || !!identity && identity.id === actorId && identity.role === role &&
      ['receivers.read', 'receivers.manage', 'collections.read', 'overview.read'].every(permission => permissions.includes(permission) && identity.permissions.includes(permission)));
  const canEditPayee = allowMutations && canRecoverPayee && detail?.can_manage === true &&
    (financialModel === 'transaction_journals' || Array.isArray(detail.allowed_operations) && detail.allowed_operations.includes('updatePayee'));
  const canRecoverMembership = detailScope === currentScope && state === 'ready' && area === 'groups' && role !== 'staff' && permissions.includes('users.read') && permissions.includes('users.manage') &&
    (financialModel === 'canonical_evidence_ledger' || permissions.includes('collections.read') && permissions.includes('overview.read'));
  const canAddMembership = allowMutations && canRecoverMembership && detail?.can_manage === true && (financialModel === 'canonical_evidence_ledger' ? permissions.includes('collections.manage') && Array.isArray(detail.allowed_operations) && detail.allowed_operations.includes('createMembership') : isObject(detail.resource) && detail.resource.status !== 'archived');
  const canRecoverUser = detailScope === currentScope && state === 'ready' && (area === 'users' || area === 'members') && role !== 'staff' && permissions.includes('users.manage') &&
    (financialModel === 'canonical_evidence_ledger' || isObject(detail?.resource) && detail.resource.collect_user_id === id);
  const canEditUser = allowMutations && canRecoverUser && detail?.can_manage === true && isObject(detail.resource) && detail.resource.operator_admin_id === null &&
    ['app', 'direct'].includes(String(detail.resource.member_type)) && (financialModel === 'canonical_evidence_ledger' ? Array.isArray(detail.allowed_operations) && detail.allowed_operations.includes('updateUser') :
      permissions.includes('overview.read') && detail.resource.status !== 'closed');
  const canReviewMembershipRows = detailScope === currentScope && state === 'ready' && ['groups', 'users'].includes(resource) && role !== 'staff' &&
    ['collections.read', 'users.read', 'users.manage', ...(financialModel === 'transaction_journals' ? ['overview.read'] : [])].every(permission => permissions.includes(permission));
  const canEditMembershipRows = allowMutations && canReviewMembershipRows && detail?.can_manage === true && (financialModel === 'canonical_evidence_ledger' ? resource === 'groups' && permissions.includes('collections.manage') && Array.isArray(detail.allowed_operations) && detail.allowed_operations.includes('updateMembership') : isObject(detail.resource) && (resource !== 'groups' || detail.resource.status !== 'archived'));
  const canRecoverReversal = detailScope === currentScope && state === 'ready' && area === 'transactions' && financialModel === 'canonical_evidence_ledger' &&
    role !== 'staff' && permissions.includes('payments.reconcile');
  const canReverse = allowMutations && canRecoverReversal && permissions.includes('ledger.read') && detail?.can_manage === true &&
    Array.isArray(detail.allowed_operations) && detail.allowed_operations.includes('reverseTransaction');
  const canRecoverLegacyPayee = detailScope === currentScope && state === 'ready' && area === 'groups' && financialModel === 'transaction_journals' &&
    role !== 'staff' && permissions.includes('receivers.manage');
  const canCreateLegacyPayee = allowMutations && canRecoverLegacyPayee && permissions.includes('overview.read') && detail?.can_manage === true &&
    isObject(detail.resource) && ['draft', 'active', 'suspended'].includes(String(detail.resource.status));
  const canRecoverLegacyAccount = detailScope === currentScope && state === 'ready' && area === 'groups' && financialModel === 'transaction_journals' &&
    role !== 'staff' && !!identity && identity.id === actorId && identity.role === role &&
    ['collections.read', 'ledger.read', 'ledger.manage', 'overview.read'].every(permission => permissions.includes(permission) && identity.permissions.includes(permission));
  const canCreateLegacyAccount = allowMutations && canRecoverLegacyAccount && detail?.can_manage === true && isObject(detail.resource) && detail.resource.status !== 'archived';
  const canRecoverGroupJournal = canRecoverLegacyAccount;
  const canCreateGroupJournal = allowMutations && canRecoverGroupJournal && detail?.can_manage === true && isObject(detail.resource) && detail.resource.status === 'active';
  const canRecoverGroupTransaction = detailScope === currentScope && state === 'ready' && area === 'groups' && financialModel === 'transaction_journals' &&
    role !== 'staff' && !!identity && identity.id === actorId && identity.role === role &&
    ['collections.read', 'receivers.read', 'payments.read', 'payments.manage', 'overview.read'].every(permission => permissions.includes(permission) && identity.permissions.includes(permission));
  const canCreateGroupTransaction = allowMutations && canRecoverGroupTransaction && detail?.can_manage === true && isObject(detail.resource) && detail.resource.status === 'active';
  const canRecoverLinkedJournal = detailScope === currentScope && state === 'ready' && area === 'transactions' && financialModel === 'transaction_journals' &&
    role !== 'staff' && permissions.includes('ledger.read') && permissions.includes('ledger.manage');
  const canCreateLinkedJournal = allowMutations && canRecoverLinkedJournal && ['collections.read', 'overview.read'].every(permission => permissions.includes(permission)) &&
    detail?.can_manage === true && isObject(detail.resource) && detail.resource.verification_status === 'confirmation_recorded';
  const canRecoverLegacyJournal = detailScope === currentScope && state === 'ready' && area === 'ledgers' && financialModel === 'transaction_journals' &&
    role !== 'staff' && permissions.includes('ledger.manage');
  const canPostLegacyJournal = allowMutations && canRecoverLegacyJournal && ['collections.read', 'overview.read'].every(permission => permissions.includes(permission)) &&
    detail?.can_manage === true && isObject(detail.resource) && detail.resource.status === 'draft' &&
    isId(detail.resource.created_by_admin_id) && isId(detail.resource.edited_by_admin_id) &&
    detail.resource.created_by_admin_id !== actorId && detail.resource.edited_by_admin_id !== actorId &&
    (detail.resource.allocation_id === null || permissions.includes('payments.read'));
  const canEditLegacyJournal = allowMutations && canRecoverLegacyJournal && ['collections.read', 'overview.read'].every(permission => permissions.includes(permission)) &&
    detail?.can_manage === true && isObject(detail.resource) && detail.resource.status === 'draft' &&
    (detail.resource.allocation_id === null || permissions.includes('payments.read'));
  return <>
    <PageHeader title={AREA_TITLES[area]} subtitle="Review this record and its related information." actions={<><Button type="button" onClick={() => navigate(back)}>Back to {AREA_TITLES[area].toLowerCase()}</Button>{canRecoverGroup && <Button type="button" variant={canEditGroup ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/groups/${id}/edit`)}>{canEditGroup ? 'Edit group' : 'Check group change request'}</Button>}{canRecoverMembership && <Button type="button" variant={canAddMembership ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/groups/${id}/members/new`)}>{canAddMembership ? 'Add member' : 'Check membership request'}</Button>}{canRecoverLegacyPayee && <Button type="button" variant={canCreateLegacyPayee ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/groups/${id}/payees/new`)}>{canCreateLegacyPayee ? 'Add receiver' : 'Check receiver creation request'}</Button>}{canRecoverLegacyAccount && <Button type="button" variant={canCreateLegacyAccount ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/groups/${id}/ledger-accounts/new`)}>{canCreateLegacyAccount ? 'Add ledger account' : 'Check ledger account request'}</Button>}{canRecoverGroupJournal && <Button type="button" variant={canCreateGroupJournal ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/groups/${id}/journals/new`)}>{canCreateGroupJournal ? 'Create journal draft' : 'Check journal draft request'}</Button>}{canRecoverGroupTransaction && <Button type="button" variant={canCreateGroupTransaction ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/groups/${id}/transactions/new`)}>{canCreateGroupTransaction ? 'Record payment evidence' : 'Check payment request'}</Button>}{canRecoverUser && <Button type="button" variant={canEditUser ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/users/${id}/edit`)}>{canEditUser ? 'Edit person' : 'Check person change request'}</Button>}{canRecoverPayee && <Button type="button" variant={canEditPayee ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/payees/${id}/edit`)}>{canEditPayee ? 'Edit receiver' : 'Check receiver change request'}</Button>}{canRecoverReversal && <Button type="button" variant={canReverse ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/transactions/${id}/reverse`)}>{canReverse ? 'Reverse contribution' : 'Check reversal request'}</Button>}{canRecoverLegacyJournal && <Button type="button" variant={canPostLegacyJournal ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/ledgers/${id}/post`)}>{canPostLegacyJournal ? 'Review posting' : 'Check journal posting request'}</Button>}{canRecoverLegacyJournal && <Button type="button" variant={canEditLegacyJournal ? 'primary' : 'secondary'} onClick={() => navigate(`/admin/ledgers/${id}/edit`)}>{canEditLegacyJournal ? 'Replace draft' : 'Check journal draft change'}</Button>}</>} />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view this record." /> :
      !isId(id) ? <ErrorState message="Select a valid record." /> :
      state === 'loading' || detailScope !== currentScope ? <LoadingState label="Loading record" /> :
      state === 'error' || !detail ? <ErrorState message="The record could not be verified or the service is unavailable." onRetry={() => { setState('loading'); setRetry(value => value + 1); }} /> : <>
        <Card><div className="core-detail"><h2>Record details</h2><dl>{fields[area].filter(([key]) => (detail.resource as Record<string, unknown>)[key] !== undefined).map(([key, title]) => <div key={key}><dt>{title}</dt><dd>{area === 'transactions' && financialModel === 'canonical_evidence_ledger' && key === 'title' ? paymentReference(detail.resource as Record<string, unknown>) : formatField(key, (detail.resource as Record<string, unknown>)[key])}</dd></div>)}</dl></div></Card>
        {area === 'transactions' && <p className="core-note">Recorded evidence does not establish provider settlement.</p>}
        {area === 'transactions' && financialModel === 'transaction_journals' && identity && identity.id === actorId && identity.role === role && isCurrent &&
          (['add', 'review'] as const).map(mode => <LegacyTransactionActions key={`${currentScope}:${mode}`} id={id} mode={mode} request={request} identity={identity}
            permissions={permissions} financialModel={financialModel} authorityKey={authorityKey} isCurrent={isCurrent} allowMutations={allowMutations}
            onUpdated={() => {setState('loading'); setRetry(value => value + 1);}} />)}
        {canReviewMembershipRows && identity && identity.id === actorId && identity.role === role && identity.permissions.includes('users.manage') && <MembershipRecoveries identity={identity} scope={currentScope} resource={resource} id={id} navigate={navigate} />}
        {financialModel === 'canonical_evidence_ledger' && identity && identity.role === role && (resource === 'groups' || resource === 'users') &&
          <OperatorNotes key={`${currentScope}:notes`} request={request} permissions={permissions} authorityKey={authorityKey} area={resource}
            id={id} identity={identity} actorId={actorId} principalId={principalId} allowMutations={allowMutations} />}
        {Object.entries(detail.related as Record<string, unknown>).map(([name, values]) => <CoreRelatedSection key={`${currentScope}:${name}`} name={name} initial={values as Record<string, unknown>[]} page={relatedPage(detail, name, values as unknown[])} resource={resource} id={id} actorId={actorId} financialModel={financialModel} request={request} version={(detail.resource as Record<string, unknown>).version} membershipRecovery={canReviewMembershipRows} membershipWrite={canEditMembershipRows} accountRead={permissions.includes('ledger.read')} journalRecovery={canRecoverLinkedJournal} journalWrite={canCreateLinkedJournal} navigate={navigate} />)}
      </>}
  </>;
}
