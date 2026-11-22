import {useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState} from 'react';
import type {AdminRequest} from '../../api/client';
import {Button, Card, Dialog, ErrorState, Field, LoadingState} from '../../ui';
import {isId} from '../core/contracts';
import {useScopedRead} from '../../api/useScopedRead';
import {usePendingIdentity} from '../core/usePendingIdentity';
import {parseOperatorNotes, type NoteArea} from './noteContracts';
import type {PendingAttempt, PendingIdentity} from '../core/pendingAttempt';
import {checkNote, readNoteAttempt, retryNote, submitNote, type NoteContext} from './noteActions';
import './notes.css';

export {parseOperatorNotes} from './noteContracts';

export function OperatorNotes({request, permissions, authorityKey, area, id, identity, actorId, principalId, allowMutations = false}: {
  request: AdminRequest; permissions: readonly string[]; authorityKey: string; area: NoteArea; id: string;
  identity: PendingIdentity; actorId: string; principalId: string | null; allowMutations?: boolean;
}) {
  const [offset, setOffset] = useState(0);
  const [pendingState, setPendingState] = useState<{scope: string; value: PendingAttempt | null; error: boolean} | null>(null);
  const [pendingRevision, setPendingRevision] = useState(0), [retryKey, setRetryKey] = useState('');
  const [draftState, setDraftState] = useState({scope: '', value: ''});
  const [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [retryOpen, setRetryOpen] = useState(false);
  const stableIdentity = usePendingIdentity(identity);
  const permissionKey = JSON.stringify([...new Set(permissions)].sort());
  const stablePermissions = useMemo<string[]>(() => JSON.parse(permissionKey) as string[], [permissionKey]);
  const identityScope = JSON.stringify([authorityKey, area, id, actorId, principalId, stableIdentity, stablePermissions]);
  const authorityRef = useRef(identityScope), writeGate = useRef(allowMutations);
  useLayoutEffect(() => {authorityRef.current = identityScope; return () => {authorityRef.current = '';};}, [identityScope]);
  useLayoutEffect(() => {writeGate.current = allowMutations; return () => {writeGate.current = false;};}, [allowMutations]);
  const required = area === 'groups' ? 'collections.read' : 'users.read';
  const allowed = permissions.includes(required) && stableIdentity.permissions.includes(required) && stableIdentity.id === actorId && isId(id);
  const canRecover = allowed && isId(principalId) &&
    stablePermissions.includes('account.manage') && stableIdentity.permissions.includes('account.manage');
  const readScope = JSON.stringify([identityScope, offset]);
  const load = useCallback(async (signal: AbortSignal) => {
    const value = await request(`operations/${area}/${id}/notes?limit=25&offset=${offset}`, {authenticated: true, signal});
    return parseOperatorNotes(value, area, id, offset);
  }, [area, id, offset, request]);
  const {result: current, refresh} = useScopedRead(allowed, readScope, load);
  useEffect(() => {
    if (!canRecover) return;
    let live = true;
    const context: NoteContext = {request, permissions: stablePermissions, actorId, principalId, area, id,
      identity: stableIdentity, allowMutations: false, isCurrent: () => authorityRef.current === identityScope && Date.parse(stableIdentity.expiresAt) > Date.now()};
    void readNoteAttempt(context).then(value => {
      if (live && context.isCurrent()) setPendingState({scope: identityScope, value, error: false});
    }).catch(() => {if (live && context.isCurrent()) setPendingState({scope: identityScope, value: null, error: true});});
    return () => {live = false;};
  }, [canRecover, request, stablePermissions, actorId, principalId, area, id, stableIdentity, identityScope, pendingRevision]);
  const pending = pendingState?.scope === identityScope ? pendingState : null;
  const draft = draftState.scope === identityScope ? draftState.value : '';
  function context(writing: boolean): NoteContext {
    return {request, permissions: stablePermissions, actorId, principalId, area, id, identity: stableIdentity,
      allowMutations: writing && writeGate.current,
      isCurrent: () => authorityRef.current === identityScope && Date.parse(stableIdentity.expiresAt) > Date.now() && (!writing || writeGate.current)};
  }
  async function check() {
    if (busy || !pending?.value) return;
    const original = pending.value, ctx = context(false); setBusy(true); setMessage(''); setRetryKey('');
    try {
      const status = await checkNote(ctx, original);
      if (!ctx.isCurrent()) return;
      if (status === 'not_found') {setRetryKey(original.request_key); setMessage('No completed request was found. Re-enter the exact original note to review a retry.');}
      else if (status === 'unconfirmed') setMessage('The original note request is still unconfirmed.');
      else {setMessage(status === 'cancelled' ? 'The original request was cancelled.' : 'The note was recorded.');
        setDraftState({scope: identityScope, value: ''}); setPendingRevision(value => value + 1); refresh();}
    } catch {if (ctx.isCurrent()) setMessage('The original note request could not be verified. Keep its reference.');}
    finally {if (ctx.isCurrent()) setBusy(false);}
  }
  async function send(retry: boolean) {
    if (busy || !allowMutations || !pending || pending.error || (retry && (!pending.value || retryKey !== pending.value.request_key))) return;
    const original = pending.value, ctx = context(true); setBusy(true); setMessage(''); setRetryOpen(false);
    try {
      const outcome = retry && original ? await retryNote(ctx, original, draft) : (await submitNote(ctx, draft), 'succeeded');
      if (!ctx.isCurrent()) return;
      setDraftState({scope: identityScope, value: ''}); setRetryKey(''); setMessage(outcome === 'cancelled' ? 'The original request was cancelled.' : 'The note request was recorded.');
      setPendingRevision(value => value + 1); refresh();
    } catch {
      if (ctx.isCurrent()) {setMessage('The note was not confirmed. Check the original request before continuing.'); setRetryKey(''); setPendingRevision(value => value + 1);}
    } finally {
      if (authorityRef.current === identityScope && Date.parse(stableIdentity.expiresAt) > Date.now()) {
        setBusy(false);
        if (!writeGate.current) setPendingRevision(value => value + 1);
      }
    }
  }
  if (!allowed) return null;
  return <Card className="notes-card"><div className="notes-heading"><div><h2>Support notes</h2><p>Notes recorded for this record.</p></div>
    <Button icon="refresh" onClick={refresh}>Refresh notes</Button></div>
    {!allowMutations && <p className="notes-unavailable">Recording new notes is currently unavailable.</p>}
    {canRecover && pending?.error && <p role="alert">Note recovery data could not be verified.</p>}
    {canRecover && pending?.value && <div className="notes-attempt"><p>Original note request: <code>{pending.value.request_key}</code></p>
      <Button disabled={busy} onClick={() => void check()}>Check original note request</Button></div>}
    {canRecover && allowMutations && pending && !pending.error && <div className="notes-editor">
      <Field label="Support note" htmlFor={`support-note-${id}`} hint="Record relevant facts. Do not include passwords or verification codes.">
        <textarea className="admin-input" id={`support-note-${id}`} rows={3} maxLength={2000} value={draft} disabled={busy || (!!pending.value && retryKey !== pending.value.request_key)}
          onChange={event => setDraftState({scope: identityScope, value: event.target.value})} />
      </Field>
      <Button variant="primary" disabled={busy || !draft.trim() || (!!pending.value && retryKey !== pending.value.request_key)}
        onClick={() => pending.value ? setRetryOpen(true) : void send(false)}>{pending.value ? 'Review original note retry' : 'Record note'}</Button>
    </div>}
    {message && <p role="status">{message}</p>}
    <Dialog open={retryOpen && !!pending?.value && allowMutations} title="Retry the original note?" onClose={() => setRetryOpen(false)}
      footer={<><Button onClick={() => setRetryOpen(false)}>Keep request</Button><Button variant="primary" disabled={busy} onClick={() => void send(true)}>Retry original note</Button></>}>
      <p>This sends the exact original note with the same reference. If it was not previously recorded, this retry can record it now.</p>
    </Dialog>
    {!current ? <LoadingState label="Loading support notes" /> : current.failed ?
      <ErrorState message="Support notes could not be verified." onRetry={refresh} /> : current.value && <>
        {current.value.rows.length === 0 ? <p>No support notes on this page.</p> : <ul className="notes-list">{current.value.rows.map(row =>
          <li key={row.id}><p className="notes-body">{row.body}</p><p className="notes-meta">{row.author} · {new Date(row.createdAt).toLocaleString()}</p></li>)}</ul>}
        <div className="notes-pagination"><span>{current.value.total} support notes</span><div>
          <Button disabled={offset === 0} onClick={() => setOffset(value => Math.max(0, value - 25))}>Previous notes</Button>{' '}
          <Button disabled={offset + current.value.rows.length >= current.value.total || offset >= 10000} onClick={() => setOffset(value => value + 25)}>Next notes</Button>
        </div></div>
      </>}
  </Card>;
}
