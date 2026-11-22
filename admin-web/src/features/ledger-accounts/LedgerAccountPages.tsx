import { useEffect, useLayoutEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from 'react';
import { Link, useParams } from 'react-router';
import {featureAuthorityKey} from '../../app/authority';
import { useSession } from '../../session/SessionProvider';
import { Button, Card, Dialog, ErrorState, Field, LoadingState, PageHeader, StatusBadge } from '../../ui';
import type {AdminRequest} from '../core/types';
import type { PendingIdentity } from '../core/pendingAttempt';
import { lookupLedgerAccountChange, parseLedgerAccountIntent, restoreLedgerAccountChange, retryLedgerAccountChange, submitLedgerAccountChange, type LedgerAccountChangeContext, type LedgerAccountIntent, type LedgerAccountPending } from './actions';
import { isLedgerId, parseLedgerAccountDetail, type LedgerAccount, type LedgerAccountDetail } from './contracts';
import './ledgerAccounts.css';

function timestamp(value: number) {
  const date = new Date(value * 1000);
  return Number.isFinite(date.getTime()) ? new Intl.DateTimeFormat('en-GB', {timeZone: 'Africa/Kigali', dateStyle: 'medium', timeStyle: 'short'}).format(date) : 'Not recorded';
}
function Facts({items}: {items: [string, ReactNode][]}) {
  return <dl className="ledger-account-facts">{items.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value}</dd></div>)}</dl>;
}
function useAccount(id: string) {
  const session = useSession(), user = session.user;
  const scope = JSON.stringify([user ? featureAuthorityKey(session.epoch, user) : session.epoch, id]), actor = user?.id, role = user?.role, model = user?.financialModel, request = session.request;
  const canRead = session.status === 'authenticated' && !!user?.permissions.includes('ledger.read') && model === 'transaction_journals' && isLedgerId(id) && !!actor && !!role;
  const [state, setState] = useState<{scope: string; detail?: LedgerAccountDetail; error?: true} | null>(null), [refresh, setRefresh] = useState(0);
  useEffect(() => {
    if (!canRead || !actor || !role) return;
    const controller = new AbortController(); let active = true;
    request(`operations/accounts/${id}`, {signal: controller.signal}).then((value) => parseLedgerAccountDetail(value, id, actor, role)).then((detail) => {
      if (active) setState({scope, detail});
    }, () => {if (active) setState({scope, error: true});});
    return () => {active = false; controller.abort();};
  }, [actor, canRead, id, refresh, request, role, scope]);
  return {session, scope, model, canRead, state: state?.scope === scope ? state : null, refresh: () => {setState(null); setRefresh((value) => value + 1);}};
}
function ReadUnavailable({model, id}: {model: string | undefined; id: string}) {
  if (!isLedgerId(id)) return <ErrorState title="Account unavailable" message="Select a valid ledger account." />;
  if (model !== 'transaction_journals') return <ErrorState title="Account unavailable" message="This workspace does not expose ledger accounts through this route." />;
  return <ErrorState title="Access unavailable" message="Your current account cannot open this ledger account." />;
}
export function LedgerAccountDetailPage({allowMutations = false}: {allowMutations?: boolean}) {
  const {id = ''} = useParams(), {session, model, canRead, state, refresh} = useAccount(id), user = session.user;
  const header = <><PageHeader eyebrow="Collect Admin / Finance" title="Ledger account" subtitle="Review the account and its current status." /><p><Link className="ledger-account-link" to="/admin/ledgers">← Back to ledgers</Link></p></>;
  if (!canRead) return <>{header}<ReadUnavailable model={model} id={id} /></>;
  if (!state) return <>{header}<LoadingState label="Loading ledger account" /></>;
  if (state.error || !state.detail) return <>{header}<ErrorState message="The ledger account could not be verified." onRetry={refresh} /></>;
  const {account, canManage} = state.detail;
  const canRecover = !!user && user.role !== 'staff' && canManage && ['ledger.read', 'ledger.manage', 'overview.read'].every((permission) => user.permissions.includes(permission));
  return <>{header}<Card className="ledger-account-detail"><div className="ledger-account-heading"><h2>{account.code} · {account.name}</h2><StatusBadge tone={account.status === 'active' ? 'success' : 'neutral'}>{account.status === 'active' ? 'Active' : 'Closed'}</StatusBadge></div>
    <Facts items={[[ 'Account ID', account.id ], [ 'Group ID', account.group_id ], [ 'Account code', account.code ], [ 'Account type', account.account_type ], [ 'Normal side', account.normal_side ], [ 'Currency', account.currency ], [ 'Version', account.version ], [ 'Created · Kigali', timestamp(account.created_at) ], [ 'Created by', account.created_by_admin_id ]]} />
    {canRecover && <p><Link className="ledger-account-link" to={`/admin/ledger-accounts/${account.id}/edit`}>{allowMutations ? 'Edit ledger account' : 'Check ledger account change request'}</Link></p>}
  </Card></>;
}

export function LedgerAccountEditPage({allowMutations = false}: {allowMutations?: boolean}) {
  const {id = ''} = useParams(), {session, scope, model, canRead, state, refresh} = useAccount(id), user = session.user;
  const actorId = user?.id, sessionId = user?.sessionId, email = user?.email, role = user?.role, expiresAt = user?.expiresAt;
  const permissionKey = JSON.stringify([...(user?.permissions ?? [])].sort());
  const identity = useMemo<PendingIdentity | null>(() => actorId && sessionId && email && role && expiresAt ? {id: actorId, sessionId, email, role, expiresAt, permissions: JSON.parse(permissionKey) as string[]} : null, [actorId, sessionId, email, role, expiresAt, permissionKey]);
  const header = <><PageHeader eyebrow="Collect Admin / Finance" title="Edit ledger account" subtitle="Review the account name and status before recording a change." /><p><Link className="ledger-account-link" to={`/admin/ledger-accounts/${id}`}>← Back to account</Link></p></>;
  if (!canRead) return <>{header}<ReadUnavailable model={model} id={id} /></>;
  if (!state) return <>{header}<LoadingState label="Loading ledger account" /></>;
  if (state.error || !state.detail) return <>{header}<ErrorState message="The ledger account could not be verified." onRetry={refresh} /></>;
  const {account} = state.detail;
  const allowed = !!identity && identity.role !== 'staff' && state.detail.canManage &&
    ['ledger.read', 'ledger.manage', 'overview.read'].every(permission => identity.permissions.includes(permission));
  if (!identity || !allowed) return <>{header}<ErrorState title="Access unavailable" message="Your current account cannot change or recover this ledger account." /></>;
  const formKey = JSON.stringify([scope, account.version, allowMutations]);
  return <>{header}<LedgerAccountChangeForm key={formKey} request={session.request} identity={identity}
    account={account} allowMutations={allowMutations} /></>;
}

interface ChangeFormProps {
  request: AdminRequest;
  identity: PendingIdentity;
  account: LedgerAccount;
  allowMutations: boolean;
}

function LedgerAccountChangeForm({request, identity, account, allowMutations}: ChangeFormProps) {
  const id = account.id;
  const mounted = useRef(false);
  useLayoutEffect(() => {
    mounted.current = true;
    return () => {mounted.current = false;};
  }, []);
  const expiresAt = useRef(identity.expiresAt);
  useLayoutEffect(() => {expiresAt.current = identity.expiresAt;}, [identity.expiresAt]);
  const context = useMemo<LedgerAccountChangeContext>(() => ({
    request, identity, account, canManage: true, financialModel: 'transaction_journals', enabled: allowMutations,
    isCurrent: () => mounted.current && Date.parse(expiresAt.current) > Date.now(),
  }), [request, identity, account, allowMutations]);

  const [recovery, setRecovery] = useState<LedgerAccountPending | null>(null), [loaded, setLoaded] = useState(false);
  const [name, setName] = useState(''), [status, setStatus] = useState<'active' | 'closed'>('active'), [reason, setReason] = useState('');
  const [message, setMessage] = useState(''), [completed, setCompleted] = useState(false);
  const [review, setReview] = useState<'new' | 'retry' | null>(null), [reviewIntent, setReviewIntent] = useState<LedgerAccountIntent | null>(null), [revision, setRevision] = useState(''), [confirmed, setConfirmed] = useState(false), [retryAvailable, setRetryAvailable] = useState(false);
  const [busy, setBusy] = useState(false), busyRef = useRef(false);
  useEffect(() => {
    let active = true;
    restoreLedgerAccountChange(context).then((saved) => {if (active && context.isCurrent()) {setRecovery(saved); setLoaded(true); setName(context.account.name); setStatus(context.account.status); if (saved.kind !== 'ready') setMessage('Check the original account request before continuing.');}},
      () => {if (active && context.isCurrent()) {setLoaded(true); setMessage('Recovery data could not be verified. Check the original request before continuing.');}});
    return () => {active = false;};
  }, [context]);
  if (!loaded) return <LoadingState label="Checking account request recovery" />;
  const pending = recovery && recovery.kind !== 'ready' ? recovery : null, ready = recovery?.kind === 'ready' ? recovery : null;
  const beginReview = (event: FormEvent) => {
    event.preventDefault(); if (!allowMutations || !ready || busyRef.current || completed) return;
    try {
      const intent = parseLedgerAccountIntent({name: name.trim(), status, expected_version: account.version, reason: reason.trim()});
      if (intent.name === account.name && intent.status === account.status) throw new Error('No change');
      setReviewIntent(intent); setRevision(ready.revision); setConfirmed(false); setMessage(''); setReview('new');
    } catch {setMessage('Change the account name or status and provide a valid reason of 8 to 1000 characters.');}
  };
  const submit = async () => {
    if (!allowMutations || !review || !reviewIntent || !confirmed || busyRef.current || review === 'new' && !revision || review === 'retry' && (!retryAvailable || pending?.kind !== 'owned' || !pending.attempt)) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = review === 'new' ? await submitLedgerAccountChange(context, reviewIntent, revision) : await retryLedgerAccountChange(context, pending!);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setRecovery(null); setCompleted(true); setMessage(`Account change recorded. Request ${result.receipt.requestId}.`);}
      else if (result.status === 'existing') {setRecovery(result.pending); setMessage('Check the original account request before continuing.');}
      else {setRecovery({kind: 'owned', requestKey: result.requestKey, attempt: null}); setMessage(`The outcome is unknown. Keep request reference ${result.requestKey} and check the original request.`); try {setRecovery(await restoreLedgerAccountChange(context));} catch { /* Keep the original reference visible. */ }}
    } catch {if (context.isCurrent()) {setMessage('The request could not be started safely. Check the original request and current account before reviewing again.'); try {setRecovery(await restoreLedgerAccountChange(context));} catch {setRecovery(null);}}}
    finally {busyRef.current = false; if (context.isCurrent()) {setBusy(false); setReview(null); setConfirmed(false);}}
  };
  const checkRequest = async () => {
    if (!pending || pending.kind !== 'owned' || busyRef.current) return;
    busyRef.current = true; setBusy(true); setMessage(''); setRetryAvailable(false);
    try {
      const result = await lookupLedgerAccountChange(context, pending);
      if (!context.isCurrent()) return;
      if (result.status === 'succeeded') {setRecovery(null); setCompleted(true); setMessage(`Account change recorded. Request ${result.receipt.requestId}.`);}
      else if (result.status === 'not_found') {setRetryAvailable(result.retryAvailable); setMessage(result.retryAvailable && allowMutations ? 'No receipt was found. You may review the identical request before retrying its original key.' : result.retryAvailable ? 'No receipt was found. Keep the original reference and check again before continuing.' : 'No receipt was found. The original intent is unavailable, so keep this reference and check again.');}
      else setMessage('The original account request remains unresolved. Keep its reference and check again.');
    } catch {if (context.isCurrent()) setMessage('The original account request could not be verified. Keep its reference and check again.');}
    finally {busyRef.current = false; if (context.isCurrent()) setBusy(false);}
  };
  const beginRetry = () => {
    if (!allowMutations || !retryAvailable || pending?.kind !== 'owned' || !pending.attempt || busyRef.current) return;
    try {setReviewIntent(parseLedgerAccountIntent(pending.attempt.intent)); setConfirmed(false); setReview('retry');} catch {setMessage('The original account intent could not be verified.');}
  };
  return <Card className="ledger-account-detail"><h2>{account.code} · {account.name}</h2><p>Account type, normal side and group identity are retained.</p>
    {message && <p role="status">{message}</p>}
    {completed && <p><Link className="ledger-account-link" to={`/admin/ledger-accounts/${id}`}>Open current account</Link></p>}
    {pending?.kind === 'owned' && <section><h3>Original request</h3><p>Reference: <code>{pending.requestKey}</code></p><Button onClick={() => void checkRequest()} disabled={busy}>Check original request</Button>{allowMutations && retryAvailable && pending.attempt && <Button onClick={beginRetry} disabled={busy}>Review identical retry</Button>}</section>}
    {pending?.kind === 'foreign' && <p>Another account or session has an unresolved request for this ledger account. The original account must check it.</p>}
    {!allowMutations && !pending && !completed && <p>Ledger account editing is unavailable in this workspace.</p>}
    {allowMutations && ready && !completed && <form className="ledger-account-form" onSubmit={beginReview}><Field label="Account name" htmlFor="ledger-account-name"><input className="admin-input" id="ledger-account-name" value={name} onChange={(event) => setName(event.target.value)} minLength={2} maxLength={120} required disabled={busy} /></Field><Field label="Account status" htmlFor="ledger-account-status"><select className="admin-input" id="ledger-account-status" value={status} onChange={(event) => setStatus(event.target.value as 'active' | 'closed')} disabled={busy}><option value="active">Active</option><option value="closed">Closed</option></select></Field><Field label="Reason for account change" htmlFor="ledger-account-reason"><textarea className="admin-input" id="ledger-account-reason" value={reason} onChange={(event) => setReason(event.target.value)} minLength={8} maxLength={1000} required disabled={busy} /></Field><Button type="submit" variant="primary" disabled={busy}>Review account change</Button></form>}
    <Dialog open={review !== null} title={review === 'retry' ? 'Review identical account retry' : 'Review account change'} onClose={() => {if (!busy) setReview(null);}} footer={<><Button onClick={() => setReview(null)} disabled={busy}>Cancel</Button><Button variant="primary" onClick={() => void submit()} disabled={!confirmed || busy}>{review === 'retry' ? 'Confirm identical retry' : 'Confirm account change'}</Button></>}>
      {reviewIntent && <><Facts items={[[ 'Account', `${account.code} · ${account.name}` ], [ 'Expected version', reviewIntent.expected_version ], [ 'New name', reviewIntent.name ], [ 'New status', reviewIntent.status ], [ 'Reason', reviewIntent.reason ]]} /><label><input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} /> I reviewed the account, version and change.</label></>}
    </Dialog>
  </Card>;
}
