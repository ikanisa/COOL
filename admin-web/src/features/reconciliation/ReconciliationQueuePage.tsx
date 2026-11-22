import {useCallback, useState} from 'react';
import {useScopedRead} from '../../api/useScopedRead';
import {Button, Card, EmptyState, ErrorState, LoadingState, PageHeader, StatusBadge} from '../../ui';
import {formatMoney, label, paymentReference} from '../core/contracts';
import type {FeatureAccess} from '../core/types';
import {parseReconciliationPage} from './contracts';
import {
  queuePath, reconciliationFilters, reconciliationPageSize, reconciliationQueueLocation, reconciliationStatuses, safeReconciliationSearch,
} from './reconciliationRoutes';
import '../core/core.css';

interface QueueProps extends FeatureAccess {locationSearch?: string}

function rowText(value: unknown): string {
  return typeof value === 'string' && value.trim() ? value : 'Not recorded';
}

export function ReconciliationQueuePage({ request, permissions, actorId, authorityKey, financialModel, navigate, locationSearch = '' }: QueueProps) {
  const allowed = permissions.includes('reconciliations.read');
  const filter = reconciliationFilters(locationSearch, financialModel);
  const [draftState, setDraftState] = useState({base: filter.search, value: filter.search});
  const draft = draftState.base === filter.search ? draftState.value : filter.search;
  const {page, status, search} = filter;
  const limit = reconciliationPageSize;
  const currentScope = JSON.stringify([authorityKey, actorId, financialModel, search, status, page]);
  const load = useCallback(async (signal: AbortSignal) => {
    const offset = (page - 1) * limit;
    const query = new URLSearchParams({limit: String(limit), offset: String(offset)});
    if (financialModel === 'canonical_evidence_ledger') {
      query.set('search', search);
      query.set('status', status);
    } else {
      if (search) query.set('search', search);
      if (status) query.set('verification_status', status);
    }
    const data = await request(`reconciliations?${query}`, {signal});
    return parseReconciliationPage(data, financialModel, limit, offset, status);
  }, [financialModel, limit, page, request, search, status]);
  const {result: read, refresh} = useScopedRead(allowed, currentScope, load);
  const result = read?.value;
  const go = (search: string, status: string, page: number) => navigate(reconciliationQueueLocation(search, status, page));
  const selected = reconciliationQueueLocation(filter.search, filter.status, filter.page);
  return <>
    <PageHeader title="Reconciliations" subtitle="Review recorded payment evidence and attribution." />
    {!allowed ? <ErrorState title="Access unavailable" message="Your account does not have permission to view reconciliations." /> : <Card>
      <div className="core-toolbar"><div><h2>Review queue</h2><p>Evidence and recorded contributions are not provider settlement.</p></div>
        <form className="core-search" onSubmit={event => { event.preventDefault(); go(safeReconciliationSearch(draft.trim()), filter.status, 1); }}>
          <label className="core-visually-hidden" htmlFor="reconciliation-search">Search reconciliations</label><input id="reconciliation-search" className="admin-input" placeholder="Search records" maxLength={200} value={draft} onChange={event => setDraftState({ base: filter.search, value: event.target.value })} />
          <Button type="submit">Search</Button><Button type="button" onClick={() => { setDraftState({ base: '', value: '' }); go('', '', 1); }}>Clear</Button>
        </form>
      </div>
      <div className="core-filters"><label>Status <select className="admin-input" value={filter.status} onChange={event => go(filter.search, event.target.value, 1)}><option value="">All statuses</option>{reconciliationStatuses(financialModel).map(status => <option key={status} value={status}>{label(status)}</option>)}</select></label></div>
      {!read ? <LoadingState label="Loading reconciliations" /> :
       read.failed ? <ErrorState message="The reconciliation records could not be verified or the service is unavailable." onRetry={refresh} /> :
       !result || result.rows.length === 0 ? <EmptyState title="No records found" description="Change your search or filters and try again." /> : <>
        <div className="admin-table-wrap" role="region" aria-label="Reconciliation queue" tabIndex={0}><table className="admin-table"><thead><tr><th scope="col">Reference</th><th scope="col">Group</th><th scope="col">Receiver</th><th scope="col">Amount</th><th scope="col">Evidence status</th><th scope="col">Open</th></tr></thead><tbody>{result.rows.map(row => {
          const status = rowText(financialModel === 'canonical_evidence_ledger' ? row.status : row.verification_status);
          const title = financialModel === 'canonical_evidence_ledger' ? paymentReference(row) : rowText(row.provider_reference);
          const group = rowText(financialModel === 'canonical_evidence_ledger' ? row.group_name : row.group_title);
          const payee = rowText(financialModel === 'canonical_evidence_ledger' ? row.payee_label : row.payee_name);
          const query = new URLSearchParams({ returnTo: selected });
          return <tr key={String(row.id)}><td>{title}</td><td>{group}</td><td>{payee}</td><td>{formatMoney(row.amount_rwf)}</td><td><StatusBadge tone={status === 'confirmed' || status === 'reconciled' || status === 'confirmation_recorded' ? 'success' : 'warning'}>{label(status)}</StatusBadge></td><td><Button type="button" aria-label={`View ${title}`} onClick={() => navigate(`${queuePath}/${row.id}?${query}`)}>View</Button></td></tr>;
        })}</tbody></table></div>
        <div className="core-pager"><span>Showing {result.offset + 1}–{result.offset + result.rows.length} of {result.total}</span><div><Button type="button" disabled={filter.page === 1} onClick={() => go(filter.search, filter.status, filter.page - 1)}>Previous</Button><span aria-current="page">{filter.page}</span><Button type="button" disabled={result.nextOffset === null} onClick={() => go(filter.search, filter.status, filter.page + 1)}>Next</Button></div></div>
       </>}
    </Card>}
  </>;
}
