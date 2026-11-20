/* eslint-disable no-control-regex -- Reject disallowed control characters in private note content. */
import {useEffect, useLayoutEffect, useMemo, useRef, useState} from 'react';
import type {AdminRequest} from '../../api/client';
import {Button, Card, Dialog, ErrorState, Field, LoadingState} from '../../ui';
import {isId, isObject, isSafeCount} from '../core/contracts';
import type {PendingAttempt, PendingIdentity} from '../core/pendingAttempt';
import {checkNote, readNoteAttempt, retryNote, submitNote, type NoteContext} from './noteActions';
import './notes.css';

type NoteArea = 'groups' | 'users';
interface Note {id: string; body: string; author: string; createdAt: string}
interface NotePage {rows: Note[]; total: number}

function invalid(): never {throw new Error('Support notes could not be verified.');}
function exactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}

/** The endpoint returns private note text; validate its entity and page before rendering. */
export function parseOperatorNotes(value: unknown, area: NoteArea, id: string, offset: number): NotePage {
  if (!isId(id) || !Number.isSafeInteger(offset) || offset < 0 || offset > 10000 || !isObject(value) ||
      !exactKeys(value, ['contract_version', 'entity_type', 'entity_id', 'rows', 'total', 'limit', 'offset']) ||
      value.contract_version !== 1 || value.entity_type !== (area === 'groups' ? 'collection' : 'profile') ||
      value.entity_id !== id || value.limit !== 25 || value.offset !== offset ||
      !isSafeCount(value.total) || !Array.isArray(value.rows) ||
      value.rows.length !== Math.min(25, Math.max(0, value.total - offset))) return invalid();
  const seen = new Set<string>();
  const rows = value.rows.map((row): Note => {
    if (!isObject(row) || !exactKeys(row, ['id', 'body', 'created_by', 'author_name', 'created_at']) ||
        !isId(row.id) || !isId(row.created_by) || seen.has(row.id) ||
        typeof row.body !== 'string' || !row.body.trim() || row.body.length > 2000 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(row.body) ||
        typeof row.author_name !== 'string' || !row.author_name.trim() || row.author_name.length > 120 || /[\x00-\x1f\x7f]/.test(row.author_name) ||
        typeof row.created_at !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(row.created_at) ||
        !Number.isFinite(Date.parse(row.created_at)) || new Date(row.created_at).toISOString() !== row.created_at) return invalid();
    seen.add(row.id);
    return {id: row.id, body: row.body, author: row.author_name, createdAt: row.created_at};
  });
  return {rows, total: value.total};
}

export function OperatorNotes({request, permissions, authorityKey, area, id, identity, actorId, principalId, allowMutations = false}: {
  request: AdminRequest; permissions: readonly string[]; authorityKey: string; area: NoteArea; id: string;
  identity: PendingIdentity; actorId: string; principalId: string | null; allowMutations?: boolean;
}) {
  const [offset, setOffset] = useState(0), [revision, setRevision] = useState(0);
  const [result, setResult] = useState<{scope: string; page: NotePage | null; error: boolean} | null>(null);
  const [pendingState, setPendingState] = useState<{scope: string; value: PendingAttempt | null; error: boolean} | null>(null);
  const [pendingRevision, setPendingRevision] = useState(0), [retryKey, setRetryKey] = useState('');
  const [draftState, setDraftState] = useState({scope: '', value: ''});
  const [busy, setBusy] = useState(false), [message, setMessage] = useState(''), [retryOpen, setRetryOpen] = useState(false);
  const identityPermissionKey = JSON.stringify([...new Set(identity.permissions)].sort());
  const permissionKey = JSON.stringify([...new Set(permissions)].sort());
  const stableIdentity = useMemo<PendingIdentity>(() => ({id: identity.id, sessionId: identity.sessionId,
    email: identity.email, role: identity.role, permissions: JSON.parse(identityPermissionKey) as string[], expiresAt: identity.expiresAt}),
  [identity.id, identity.sessionId, identity.email, identity.role, identity.expiresAt, identityPermissionKey]);
  const stablePermissions = useMemo<string[]>(() => JSON.parse(permissionKey) as string[], [permissionKey]);
  const identityScope = JSON.stringify([authorityKey, area, id, actorId, principalId, stableIdentity, stablePermissions]);
  const authorityRef = useRef(identityScope), writeGate = useRef(allowMutations);
  useLayoutEffect(() => {authorityRef.current = identityScope; return () => {authorityRef.current = '';};}, [identityScope]);
  useLayoutEffect(() => {writeGate.current = allowMutations; return () => {writeGate.current = false;};}, [allowMutations]);
  const required = area === 'groups' ? 'collections.read' : 'users.read';
  const allowed = permissions.includes(required) && stableIdentity.permissions.includes(required) && stableIdentity.id === actorId && isId(id);
  const canRecover = allowed && isId(principalId) && stableIdentity.id === actorId &&
    stableIdentity.permissions.includes(area === 'groups' ? 'collections.read' : 'users.read') &&
    stablePermissions.includes('account.manage') && stableIdentity.permissions.includes('account.manage');
  const scope = JSON.stringify([identityScope, offset, revision]);
  const current = result?.scope === scope ? result : null;
  useEffect(() => {
    if (!allowed) return;
    const controller = new AbortController();
    void request(`operations/${area}/${id}/notes?limit=25&offset=${offset}`, {authenticated: true, signal: controller.signal})
      .then(value => parseOperatorNotes(value, area, id, offset))
      .then(page => {if (!controller.signal.aborted) setResult({scope, page, error: false});})
      .catch(() => {if (!controller.signal.aborted) setResult({scope, page: null, error: true});});
    return () => controller.abort();
  }, [allowed, area, id, offset, request, scope]);
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
        setDraftState({scope: identityScope, value: ''}); setPendingRevision(value => value + 1); setRevision(value => value + 1);}
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
      setPendingRevision(value => value + 1); setRevision(value => value + 1);
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
    <Button icon="refresh" onClick={() => setRevision(value => value + 1)}>Refresh notes</Button></div>
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
    {!current ? <LoadingState label="Loading support notes" /> : current.error ?
      <ErrorState message="Support notes could not be verified." onRetry={() => setRevision(value => value + 1)} /> : current.page && <>
        {current.page.rows.length === 0 ? <p>No support notes on this page.</p> : <ul className="notes-list">{current.page.rows.map(row =>
          <li key={row.id}><p className="notes-body">{row.body}</p><p className="notes-meta">{row.author} · {new Date(row.createdAt).toLocaleString()}</p></li>)}</ul>}
        <div className="notes-pagination"><span>{current.page.total} support notes</span><div>
          <Button disabled={offset === 0} onClick={() => setOffset(value => Math.max(0, value - 25))}>Previous notes</Button>{' '}
          <Button disabled={offset + current.page.rows.length >= current.page.total || offset >= 10000} onClick={() => setOffset(value => value + 25)}>Next notes</Button>
        </div></div>
      </>}
  </Card>;
}
