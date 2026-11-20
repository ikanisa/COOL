import {useEffect, useLayoutEffect, useRef, useState, type FormEvent} from 'react';
import {Button, Card, EmptyState, ErrorState, Field, LoadingState, PageHeader, StatusBadge} from '../../ui';
import {listPending, type FeatureAccess, type PendingAttempt, type PendingIdentity} from '../core';
import {label} from '../core/contracts';
import {CancellationPanel} from './CancellationPanel';
import {CANCELLATION_FAMILY} from './cancellation';
import {parseHistory, parseLookup, validRequestKey, type RequestHistory, type RequestLookup} from './contracts';
import {canReadRequestHistory} from './permissions';
import './requests.css';

function explanation(status: string): string {
  switch (status) {
    case 'succeeded': return 'The server recorded this request. The receipt does not establish provider settlement.';
    case 'not_found': return 'No request was found for this reference and your account. This does not prove that an attempted change failed.';
    case 'unconfirmed': case 'pending': return 'This request is still unconfirmed. Check the original reference again before continuing.';
    case 'cancelled': return 'The original reference is blocked. A delayed retry cannot apply it.';
    default: return 'The server recorded a failed request. Refresh the affected record before making another change.';
  }
}

export interface RequestHistoryProps extends FeatureAccess {
  locationSearch?: string;
  identity?: PendingIdentity;
  verifyFresh?: () => Promise<boolean>;
  /** Must remain disabled until the backend, old tabs and recovery are qualified. */
  allowCancellation?: boolean;
}
export function RequestHistoryPage({request, permissions, principalId, financialModel, authorityKey, locationSearch = '',
  identity, verifyFresh, allowCancellation = false, actorId, role, navigate}: RequestHistoryProps) {
  const initial = new URLSearchParams(locationSearch).get('key') ?? '';
  const [key, setKey] = useState(validRequestKey(initial) ? initial : '');
  const [lookup, setLookup] = useState<{scope: string; key: string; value: RequestLookup | null; error: string} | null>(null);
  const [busyScope, setBusyScope] = useState('');
  const [page, setPage] = useState(0), [refresh, setRefresh] = useState(0);
  const [history, setHistory] = useState<{scope: string; data: RequestHistory | null; error: string} | null>(null);
  const [recoveries, setRecoveries] = useState<{scope: string; rows: PendingAttempt[]; error: string} | null>(null);
  const generation = useRef(0);
  const allowed = canReadRequestHistory(financialModel, permissions);
  const authScope = JSON.stringify([authorityKey, financialModel, actorId, principalId, role, [...new Set(permissions)].sort(), identity?.sessionId]);
  const authScopeRef = useRef(authScope);
  useLayoutEffect(() => {authScopeRef.current = authScope; generation.current += 1; return () => {authScopeRef.current = ''; generation.current += 1;};}, [authScope]);
  const scope = JSON.stringify([authorityKey, financialModel, principalId, page, refresh]);
  const current = history?.scope === scope ? history : null;
  const currentLookup = lookup?.scope === authScope && lookup.key === key.trim() ? lookup : null;
  const currentRecoveries = recoveries?.scope === authScope ? recoveries : null;
  const busy = busyScope === authScope;
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController();
    void request(`operations/requests?limit=25&offset=${page * 25}`, {authenticated: true, signal: controller.signal})
      .then((value) => parseHistory(value, financialModel, principalId, page * 25))
      .then((data) => {if (!controller.signal.aborted) setHistory({scope, data, error: ''});})
      .catch(() => {if (!controller.signal.aborted) setHistory({scope, data: null, error: 'Request history could not be verified.'});});
    return () => controller.abort();
  }, [allowed, financialModel, page, principalId, request, scope]);
  async function check(requestKey: string) {
    const selected = requestKey.trim();
    if (!validRequestKey(selected)) {setLookup({scope: authScope, key: selected, value: null, error: 'Enter a valid request reference.'}); return;}
    const attempt = ++generation.current;
    setBusyScope(authScope); setLookup(null);
    try {
      const response = await request(`operations/requests/${selected}`, {authenticated: true});
      const value = await parseLookup(response, financialModel, principalId, selected);
      if (attempt === generation.current && authScopeRef.current === authScope) setLookup({scope: authScope, key: selected, value, error: ''});
    } catch {
      if (attempt === generation.current && authScopeRef.current === authScope) setLookup({scope: authScope, key: selected, value: null, error: 'The request status could not be verified. Keep the original reference and check again.'});
    } finally {if (attempt === generation.current && authScopeRef.current === authScope) setBusyScope('');}
  }
  async function findRecoveries() {
    if (!identity || busy || identity.id !== actorId || identity.role !== role || !identity.permissions.includes('account.manage')) return;
    const attempt = ++generation.current; setBusyScope(authScope);
    try {
      const rows = await listPending(identity, CANCELLATION_FAMILY, 'account.manage');
      if (rows.some((row) => !validRequestKey(row.resource_id))) throw new Error('Invalid target reference');
      if (attempt === generation.current && authScopeRef.current === authScope) setRecoveries({scope: authScope, rows, error: ''});
    } catch {if (attempt === generation.current && authScopeRef.current === authScope) setRecoveries({scope: authScope, rows: [], error: 'Cancellation recovery could not be verified in this tab.'});}
    finally {if (attempt === generation.current && authScopeRef.current === authScope) setBusyScope('');}
  }
  function submit(event: FormEvent<HTMLFormElement>) {event.preventDefault(); void check(key);}
  if (!allowed) return <><PageHeader title="Request history" /><ErrorState title="Access unavailable" message="Your account cannot view request history." /></>;
  return <>
    <PageHeader title="Request history" subtitle="Check the server receipt for a change made by your account." />
    <Card className="request-lookup"><h2>Check a request</h2><form onSubmit={submit}>
      <Field label="Request reference" htmlFor="request-key"><input className="admin-input" id="request-key" value={key} maxLength={200}
        onChange={(event) => {generation.current += 1; setBusyScope(''); setLookup(null); setKey(event.target.value);}} /></Field>
      <Button type="submit" variant="primary" loading={busy}>Check request</Button>
    </form>
      {currentLookup?.error && <p role="alert">{currentLookup.error}</p>}
      {currentLookup?.value && <div className="request-result" role="status"><StatusBadge tone={currentLookup.value.status === 'succeeded' ? 'success' : 'warning'}>{label(currentLookup.value.status)}</StatusBadge>
        <p>{explanation(currentLookup.value.status)}</p>
        {currentLookup.value.receipt && <dl><dt>Request ID</dt><dd>{currentLookup.value.receipt.requestId}</dd><dt>Resource</dt><dd>{label(currentLookup.value.receipt.resourceType)}</dd><dt>Record ID</dt><dd>{currentLookup.value.receipt.resourceId}</dd></dl>}
      </div>}
      {identity && verifyFresh && financialModel === 'canonical_evidence_ledger' && currentLookup?.value && <CancellationPanel
        key={`${authScope}:${currentLookup.key}`} request={request} identity={identity} verifyFresh={verifyFresh} targetKey={currentLookup.key} target={currentLookup.value}
        permissions={permissions} actorId={actorId} principalId={principalId} role={role} financialModel={financialModel} authorityKey={authorityKey} navigate={navigate}
        allowCancellation={allowCancellation} onOutcome={(targetKey, outcome) => {if (authScopeRef.current === authScope) {setLookup({scope: authScope, key: targetKey, value: outcome, error: ''}); setRefresh((value) => value + 1);}}} />}
    </Card>
    {identity && financialModel === 'canonical_evidence_ledger' && <Card className="request-recovery"><h2>Cancellation recovery</h2>
      <p>Review cancellation references retained in this tab and check the original target. Checking does not submit a cancellation.</p>
      <Button disabled={busy} onClick={() => void findRecoveries()}>Find retained cancellations</Button>
      {currentRecoveries?.error && <p role="alert">{currentRecoveries.error}</p>}
      {currentRecoveries && !currentRecoveries.error && currentRecoveries.rows.length === 0 && <p>No cancellation references were found in this tab.</p>}
      {currentRecoveries?.rows.map((entry) => <div key={entry.resource_id}><p>Original reference: <code>{entry.resource_id}</code> · Cancellation reference: <code>{entry.request_key}</code></p>
        <Button disabled={busy} onClick={() => {setKey(entry.resource_id); void check(entry.resource_id);}}>Check original target</Button></div>)}
    </Card>}
    <div className="request-history-heading"><h2>Your recent requests</h2><Button icon="refresh" onClick={() => setRefresh((n) => n + 1)}>Refresh</Button></div>
    <Card>{!current ? <LoadingState label="Loading request history" /> : current.error ?
      <ErrorState message={current.error} onRetry={() => setRefresh((n) => n + 1)} /> : !current.data?.rows.length ?
      <EmptyState title="No requests found" /> : <>
        <div className="admin-table-wrap" role="region" aria-label="Request history" tabIndex={0}><table className="admin-table"><thead><tr>
          <th scope="col">Reference</th><th scope="col">Action</th><th scope="col">Status</th><th scope="col">Created</th><th scope="col">Open</th>
        </tr></thead><tbody>{current.data.rows.map((row) => <tr key={row.id}><td>{row.key}</td><td>{label(row.scope.replaceAll('.', ' '))}</td>
          <td><StatusBadge tone={row.status === 'succeeded' ? 'success' : 'warning'}>{label(row.status)}</StatusBadge></td>
          <td>{new Date(typeof row.createdAt === 'number' ? row.createdAt * 1000 : row.createdAt).toLocaleString()}</td>
          <td><Button onClick={() => {setKey(row.key); void check(row.key);}}>Check</Button></td></tr>)}</tbody></table></div>
        <div className="request-pagination"><span>Showing {page * 25 + 1}–{page * 25 + current.data.rows.length} of {current.data.total}</span>
          <div><Button disabled={page === 0} onClick={() => setPage((n) => n - 1)}>Previous</Button>{' '}
          <Button disabled={(page + 1) * 25 >= current.data.total} onClick={() => setPage((n) => n + 1)}>Next</Button></div></div>
      </>}</Card>
  </>;
}
